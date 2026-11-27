#include "bili_mux.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <new>
#include <string>

extern "C" {
#include <libavformat/avformat.h>
#include <libavutil/log.h>
}

struct bili_mux_job {
  std::string video;
  std::string audio;
  std::string output;
  int32_t container{0};
  std::atomic<bool> cancelled{false};
  std::atomic<bool> started{false};
  std::atomic<int32_t> progress{0};
  const std::chrono::steady_clock::time_point deadline{
      std::chrono::steady_clock::now() + std::chrono::hours{3}};
};

namespace {
enum class result : int32_t {
  success, cancelled, input, output, verification, internal, deadline
};
constexpr int max_packet_bytes = 64 * 1024 * 1024;

class mux_error final {
 public:
  explicit mux_error(result code) : code{code} {}
  result code;
};

void check_cancel(const bili_mux_job& job) {
  if (job.cancelled.load(std::memory_order_relaxed)) {
    throw mux_error{result::cancelled};
  }
  if (std::chrono::steady_clock::now() >= job.deadline) {
    throw mux_error{result::deadline};
  }
}

int interrupt(void* opaque) {
  const auto& job = *static_cast<const bili_mux_job*>(opaque);
  return job.cancelled.load(std::memory_order_relaxed) ||
         std::chrono::steady_clock::now() >= job.deadline;
}

struct input_deleter {
  void operator()(AVFormatContext* value) const {
    avformat_close_input(&value);
  }
};
using input_ptr = std::unique_ptr<AVFormatContext, input_deleter>;

input_ptr open_input(const std::string& path, bili_mux_job& job,
                     bool require_av1_header = false) {
  AVFormatContext* context = avformat_alloc_context();
  if (!context) throw mux_error{result::internal};
  context->interrupt_callback = AVIOInterruptCB{interrupt, &job};
  const auto status = avformat_open_input(&context, path.c_str(), nullptr, nullptr);
  if (status < 0) {
    avformat_close_input(&context);
    check_cancel(job);
    throw mux_error{result::input};
  }
  input_ptr input{context};
  // Some fragmented AV1 inputs carry the sequence header only in packets.
  // Matroska needs it before writing CodecPrivate. The library has no decoders:
  // bounded local probing uses the existing parser/extradata filter only.
  if (require_av1_header) {
    for (unsigned int i = 0; i < context->nb_streams; ++i) {
      const auto* parameters = context->streams[i]->codecpar;
      if (parameters->codec_id == AV_CODEC_ID_AV1 &&
          parameters->extradata_size == 0) {
        context->probesize = 8 * 1024 * 1024;
        context->max_analyze_duration = 5 * AV_TIME_BASE;
        context->max_probe_packets = 256;
        if (avformat_find_stream_info(context, nullptr) < 0 ||
            parameters->extradata_size == 0) {
          check_cancel(job);
          throw mux_error{result::input};
        }
        break;
      }
    }
  }
  return input;
}

struct output_context {
  AVFormatContext* value{nullptr};
  ~output_context() {
    if (value) {
      if (value->pb) avio_closep(&value->pb);
      avformat_free_context(value);
    }
  }
  output_context() = default;
  output_context(const output_context&) = delete;
  output_context& operator=(const output_context&) = delete;
};

struct packet_deleter {
  void operator()(AVPacket* value) const { av_packet_free(&value); }
};
using packet_ptr = std::unique_ptr<AVPacket, packet_deleter>;

int stream_index(const AVFormatContext& context, AVMediaType type) {
  for (unsigned int i = 0; i < context.nb_streams; ++i) {
    if (context.streams[i]->codecpar->codec_type == type) {
      return static_cast<int>(i);
    }
  }
  throw mux_error{result::input};
}

bool read_packet(AVFormatContext& context, int index, AVPacket& packet,
                 const bili_mux_job& job) {
  while (true) {
    check_cancel(job);
    av_packet_unref(&packet);
    const int status = av_read_frame(&context, &packet);
    if (status == AVERROR_EOF) return false;
    if (status < 0) throw mux_error{result::input};
    if (packet.stream_index == index) {
      if (packet.size <= 0 || packet.size > max_packet_bytes) {
        throw mux_error{result::input};
      }
      if (packet.pts == AV_NOPTS_VALUE || packet.dts == AV_NOPTS_VALUE) {
        throw mux_error{result::input};
      }
      return true;
    }
  }
}

void copy_stream(const AVStream& input, AVFormatContext& output) {
  auto* stream = avformat_new_stream(&output, nullptr);
  if (!stream || avcodec_parameters_copy(stream->codecpar, input.codecpar) < 0) {
    throw mux_error{result::internal};
  }
  stream->codecpar->codec_tag = 0;
  stream->time_base = input.time_base;
  stream->avg_frame_rate = input.avg_frame_rate;
  stream->sample_aspect_ratio = input.sample_aspect_ratio;
  stream->disposition = input.disposition;
  if (av_dict_copy(&stream->metadata, input.metadata, 0) < 0) {
    throw mux_error{result::internal};
  }
}

void merge(bili_mux_job& job) {
  check_cancel(job);
  auto video = open_input(job.video, job, job.container == 1);
  auto audio = open_input(job.audio, job);
  const int vi = stream_index(*video, AVMEDIA_TYPE_VIDEO);
  const int ai = stream_index(*audio, AVMEDIA_TYPE_AUDIO);
  const auto vc = video->streams[vi]->codecpar->codec_id;
  const auto ac = audio->streams[ai]->codecpar->codec_id;
  if ((vc != AV_CODEC_ID_H264 && vc != AV_CODEC_ID_HEVC && vc != AV_CODEC_ID_AV1) ||
      (ac != AV_CODEC_ID_AAC && ac != AV_CODEC_ID_FLAC &&
       ac != AV_CODEC_ID_AC3 && ac != AV_CODEC_ID_EAC3)) {
    throw mux_error{result::input};
  }
  output_context output;
  const char* format = job.container == 0 ? "mp4" : "matroska";
  if (avformat_alloc_output_context2(&output.value, nullptr, format,
                                      job.output.c_str()) < 0 || !output.value) {
    throw mux_error{result::output};
  }
  output.value->interrupt_callback = AVIOInterruptCB{interrupt, &job};
  // Keep the common source timeline, including negative decode timestamps for
  // B frames. Never independently shift audio/video to zero.
  output.value->avoid_negative_ts = AVFMT_AVOID_NEG_TS_DISABLED;
  copy_stream(*video->streams[vi], *output.value);
  copy_stream(*audio->streams[ai], *output.value);
  if (avio_open2(&output.value->pb, job.output.c_str(), AVIO_FLAG_WRITE,
                 &output.value->interrupt_callback, nullptr) < 0) {
    check_cancel(job);
    throw mux_error{result::output};
  }
  AVDictionary* options{nullptr};
  if (job.container == 0) {
    av_dict_set(&options, "movflags", "+faststart", 0);
    av_dict_set(&options, "use_editlist", "1", 0);
    av_dict_set(&options, "movie_timescale", "1000000", 0);
  }
  const int header_status = avformat_write_header(output.value, &options);
  av_dict_free(&options);
  if (header_status < 0) throw mux_error{result::output};

  const std::array<AVFormatContext*, 2> inputs{video.get(), audio.get()};
  const std::array<int, 2> indices{vi, ai};
  std::array<packet_ptr, 2> packets{packet_ptr{av_packet_alloc()},
                                    packet_ptr{av_packet_alloc()}};
  if (!packets[0] || !packets[1]) throw mux_error{result::internal};
  std::array<int64_t, 2> packet_counts{};
  std::array<bool, 2> pending{
      read_packet(*video, vi, *packets[0], job),
      read_packet(*audio, ai, *packets[1], job)};
  const auto video_size = avio_size(video->pb);
  const auto audio_size = avio_size(audio->pb);
  const double total_size = static_cast<double>(video_size) +
                            static_cast<double>(audio_size);
  while (pending[0] || pending[1]) {
    check_cancel(job);
    int track = pending[0] ? 0 : 1;
    if (pending[0] && pending[1] &&
        av_compare_ts(packets[0]->dts, video->streams[vi]->time_base,
                      packets[1]->dts, audio->streams[ai]->time_base) > 0) {
      track = 1;
    }
    auto& packet = *packets[track];
    ++packet_counts[track];
    av_packet_rescale_ts(&packet, inputs[track]->streams[indices[track]]->time_base,
                         output.value->streams[track]->time_base);
    packet.stream_index = track;
    packet.pos = -1;
    if (av_interleaved_write_frame(output.value, &packet) < 0) {
      check_cancel(job);
      throw mux_error{result::output};
    }
    pending[track] = read_packet(*inputs[track], indices[track], packet, job);
    if (total_size > 0) {
      const double consumed = static_cast<double>(avio_tell(video->pb)) +
                              static_cast<double>(avio_tell(audio->pb));
      job.progress.store(static_cast<int32_t>(
          std::clamp(consumed / total_size, 0.0, 1.0) * 9500));
    }
  }
  if (packet_counts[0] == 0 || packet_counts[1] == 0) {
    throw mux_error{result::input};
  }
  check_cancel(job);
  if (av_write_trailer(output.value) < 0 || avio_closep(&output.value->pb) < 0) {
    check_cancel(job);
    throw mux_error{result::output};
  }
  // Successful packet writes, trailer and close commit the output. Do not
  // reopen and hash the whole movie: local playback accepts user modifications.
  // Independent regression tests still compare the remuxed packet streams.
  job.progress.store(10000);
}
}  // namespace

int32_t bili_mux_abi() { return 2; }

bili_mux_job* bili_mux_create(const char* video, const char* audio,
                             const char* output, int32_t container) {
  if (!video || !audio || !output || !*video || !*audio || !*output ||
      std::strcmp(video, output) == 0 || std::strcmp(audio, output) == 0 ||
      (container != 0 && container != 1)) return nullptr;
  try {
    static std::once_flag log_setup;
    // FFmpeg symbols are private to this component. Suppress its native logs
    // so local paths and library diagnostics never bypass app error mapping.
    std::call_once(log_setup, [] { av_log_set_level(AV_LOG_QUIET); });
    auto job = std::make_unique<bili_mux_job>();
    job->video = video;
    job->audio = audio;
    job->output = output;
    job->container = container;
    return job.release();  // Ownership crosses the C ABI; destroy releases it.
  } catch (...) {
    return nullptr;
  }
}

int32_t bili_mux_run(bili_mux_job* job) {
  if (!job || job->started.exchange(true)) return static_cast<int32_t>(result::internal);
  try {
    merge(*job);
    return static_cast<int32_t>(result::success);
  } catch (const mux_error& error) {
    return static_cast<int32_t>(error.code);
  } catch (...) {
    return static_cast<int32_t>(result::internal);
  }
}

void bili_mux_cancel(bili_mux_job* job) {
  if (job) job->cancelled.store(true, std::memory_order_relaxed);
}
int32_t bili_mux_progress(const bili_mux_job* job) {
  return job ? job->progress.load() : 0;
}
void bili_mux_destroy(bili_mux_job* job) {
  const std::unique_ptr<bili_mux_job> owned{job};
}
