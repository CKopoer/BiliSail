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
#include <libavutil/mem.h>
#include <libavutil/log.h>
#include <libavutil/sha.h>
}

struct bili_mux_job {
  std::string video;
  std::string audio;
  std::string output;
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

input_ptr open_input(const std::string& path, bili_mux_job& job) {
  AVFormatContext* context = avformat_alloc_context();
  if (!context) throw mux_error{result::internal};
  context->interrupt_callback = AVIOInterruptCB{interrupt, &job};
  const auto status = avformat_open_input(&context, path.c_str(), nullptr, nullptr);
  if (status < 0) {
    avformat_close_input(&context);
    check_cancel(job);
    throw mux_error{result::input};
  }
  // MP4 headers contain codec parameters. Do not probe with a decoder.
  return input_ptr{context};
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

struct sha_deleter {
  void operator()(AVSHA* value) const { av_free(value); }
};

// Per-track streaming hash includes packet boundaries and order. Memory stays
// bounded for long videos; only two pending packets are held during interleave.
class packet_digest {
 public:
  packet_digest() : context_{av_sha_alloc()} {
    if (!context_ || av_sha_init(context_.get(), 256) < 0) {
      throw mux_error{result::internal};
    }
  }
  void add(const AVPacket& packet) {
    if (packet.size <= 0 || packet.size > max_packet_bytes) {
      throw mux_error{result::input};
    }
    const auto size = static_cast<uint32_t>(packet.size);
    const std::array<uint8_t, 4> prefix{
        static_cast<uint8_t>(size >> 24), static_cast<uint8_t>(size >> 16),
        static_cast<uint8_t>(size >> 8), static_cast<uint8_t>(size)};
    av_sha_update(context_.get(), prefix.data(), prefix.size());
    av_sha_update(context_.get(), packet.data, size);
    ++packets_;
  }
  std::array<uint8_t, 32> finish() {
    std::array<uint8_t, 32> value{};
    av_sha_final(context_.get(), value.data());
    return value;
  }
  int64_t packets() const { return packets_; }
 private:
  std::unique_ptr<AVSHA, sha_deleter> context_;
  int64_t packets_{0};
};

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
  auto video = open_input(job.video, job);
  auto audio = open_input(job.audio, job);
  const int vi = stream_index(*video, AVMEDIA_TYPE_VIDEO);
  const int ai = stream_index(*audio, AVMEDIA_TYPE_AUDIO);
  const auto vc = video->streams[vi]->codecpar->codec_id;
  if ((vc != AV_CODEC_ID_H264 && vc != AV_CODEC_ID_HEVC && vc != AV_CODEC_ID_AV1) ||
      audio->streams[ai]->codecpar->codec_id != AV_CODEC_ID_AAC) {
    throw mux_error{result::input};
  }
  output_context output;
  if (avformat_alloc_output_context2(&output.value, nullptr, "mp4",
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
  av_dict_set(&options, "movflags", "+faststart", 0);
  av_dict_set(&options, "use_editlist", "1", 0);
  av_dict_set(&options, "movie_timescale", "1000000", 0);
  const int header_status = avformat_write_header(output.value, &options);
  av_dict_free(&options);
  if (header_status < 0) throw mux_error{result::output};

  const std::array<AVFormatContext*, 2> inputs{video.get(), audio.get()};
  const std::array<int, 2> indices{vi, ai};
  std::array<packet_ptr, 2> packets{packet_ptr{av_packet_alloc()},
                                    packet_ptr{av_packet_alloc()}};
  if (!packets[0] || !packets[1]) throw mux_error{result::internal};
  std::array<packet_digest, 2> source_digests{};
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
    source_digests[track].add(packet);
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
          std::clamp(consumed / total_size, 0.0, 1.0) * 8000));
    }
  }
  if (source_digests[0].packets() == 0 || source_digests[1].packets() == 0) {
    throw mux_error{result::input};
  }
  check_cancel(job);
  if (av_write_trailer(output.value) < 0 || avio_closep(&output.value->pb) < 0) {
    check_cancel(job);
    throw mux_error{result::output};
  }
  job.progress.store(8500);

  // Verify the committed container has precisely the original compressed
  // packets on both tracks. File hashing/atomic publication belongs to Dart.
  auto verified = open_input(job.output, job);
  if (verified->nb_streams != 2) throw mux_error{result::verification};
  const int ov = stream_index(*verified, AVMEDIA_TYPE_VIDEO);
  const int oa = stream_index(*verified, AVMEDIA_TYPE_AUDIO);
  if (verified->streams[ov]->codecpar->codec_id != vc ||
      verified->streams[oa]->codecpar->codec_id != AV_CODEC_ID_AAC) {
    throw mux_error{result::verification};
  }
  std::array<packet_digest, 2> output_digests{};
  auto packet = packet_ptr{av_packet_alloc()};
  if (!packet) throw mux_error{result::internal};
  while (true) {
    check_cancel(job);
    const int status = av_read_frame(verified.get(), packet.get());
    if (status == AVERROR_EOF) break;
    if (status < 0) throw mux_error{result::verification};
    const int track = packet->stream_index == ov ? 0 : 1;
    output_digests[track].add(*packet);
    av_packet_unref(packet.get());
  }
  for (int track = 0; track < 2; ++track) {
    if (source_digests[track].packets() != output_digests[track].packets() ||
        source_digests[track].finish() != output_digests[track].finish()) {
      throw mux_error{result::verification};
    }
  }
  job.progress.store(10000);
}
}  // namespace

int32_t bili_mux_abi() { return 1; }

bili_mux_job* bili_mux_create(const char* video, const char* audio,
                             const char* output) {
  if (!video || !audio || !output || !*video || !*audio || !*output ||
      std::strcmp(video, output) == 0 || std::strcmp(audio, output) == 0) return nullptr;
  try {
    static std::once_flag log_setup;
    // FFmpeg symbols are private to this component. Suppress its native logs
    // so local paths and library diagnostics never bypass app error mapping.
    std::call_once(log_setup, [] { av_log_set_level(AV_LOG_QUIET); });
    auto job = std::make_unique<bili_mux_job>();
    job->video = video;
    job->audio = audio;
    job->output = output;
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
