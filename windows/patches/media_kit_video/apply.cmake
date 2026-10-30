# Apply only to verified upstream sources, in the build tree, never Pub cache.
set(BILISAIL_VIDEO_PATCH_DIR "${CMAKE_CURRENT_LIST_DIR}")

function(bilisail_replace_once file before after)
  file(READ "${file}" text)
  string(LENGTH "${text}" original_length)
  string(LENGTH "${before}" match_length)
  string(REPLACE "${before}" "" removed "${text}")
  string(LENGTH "${removed}" remaining_length)
  math(EXPR removed_length "${original_length} - ${remaining_length}")
  if(NOT removed_length EQUAL match_length)
    message(FATAL_ERROR "media_kit_video patch anchor must occur once: ${file}")
  endif()
  string(REPLACE "${before}" "${after}" text "${text}")
  file(WRITE "${file}" "${text}")
endfunction()

function(bilisail_patch_video_sources source output)
  get_filename_component(source "${source}" REALPATH)
  get_filename_component(output "${output}" ABSOLUTE)
  if(source STREQUAL output)
    message(FATAL_ERROR "media_kit_video patch requires a separate build directory")
  endif()
  set(files video_output.h video_output.cc video_output_manager.h video_output_manager.cc media_kit_video_plugin.cc d3d11_renderer.h d3d11_renderer.cc mailbox_swap_chain.h mailbox_swap_chain.cc)
  set(hashes
    36c4bac24c3a1d6abd937f1319a7acca55f329aceb552e92a610aed0bdcd7ecd
    cfa81c441ccb1deea1c93e5d137b860bfea78cbc80a51c92db8cff3a9519c804
    de48824c62d6b7f003b65f4891431ab016987806c395755e2b8a53d7063cf780
    5952a6e22f1161719f17dc350a18fbf8919d067bb6f05bf1447557ce59424135
    5f17001004f240c48656bd64e44037b1822d0055c78fa64cf91aa99d015937fb
    371a029087e82c43c18b01ca2963d3d47c88069f344dab40824dedf435d82b8a
    125ad611e3dc3332e325a117c68d450acf6d51dc8c2c01ebf6fbac3107660756
    d55e39e4705440490ddc1551f4db41ae91fbeee5d8330fcbcdd3edb3caf58740
    8bb19233dc0727f3b5e85c8a6d902dc1ac4ac0aea09aed28e6ee1326d4198ead)
  foreach(index RANGE 0 8)
    list(GET files ${index} file)
    list(GET hashes ${index} expected)
    # Git checkouts may use LF or CRLF. Validate exactly the same source text
    # on both; substantive changes still fail closed against the pinned blob.
    file(READ "${source}/${file}" original)
    string(REPLACE "\r\n" "\n" original "${original}")
    string(SHA256 actual "${original}")
    if(NOT actual STREQUAL expected)
      message(FATAL_ERROR "Predidit media-kit 83b7ca6 source changed: ${file}; review the D3D11 lifecycle patch")
    endif()
  endforeach()
  file(GLOB inputs RELATIVE "${source}" "${source}/*")
  foreach(file IN LISTS inputs)
    if(NOT IS_DIRECTORY "${source}/${file}")
      configure_file("${source}/${file}" "${output}/${file}" COPYONLY)
    endif()
  endforeach()
  # The C API translation unit uses include/media_kit_video/... relative to its
  # source directory. Preserve that public tree in a fresh build-local copy.
  file(COPY "${source}/include" DESTINATION "${output}")
  # Copied sources keep their upstream ../common includes.
  file(COPY "${source}/../common" DESTINATION "${output}/..")
  foreach(file video_output_dispose.inc video_output_manager_dispose.inc
      video_output_dimensions.inc video_output_viewport.inc video_output_resize.inc
      mailbox_first_frame.inc)
    configure_file("${BILISAIL_VIDEO_PATCH_DIR}/${file}" "${output}/${file}" COPYONLY)
  endforeach()

  bilisail_replace_once("${output}/video_output.h" "#include <optional>"
    "#include <optional>\n#include <atomic>\n#include <cmath>\n#include <condition_variable>\n#include <utility>")
  bilisail_replace_once("${output}/video_output.h" "  void NotifyRender();"
    "  void UnregisterTexture(int64_t id, std::function<void()> callback);\n\n  void NotifyRender();\n  void RenderQueued();")
  bilisail_replace_once("${output}/video_output.h"
    "  void SetSize(std::optional<int64_t> width, std::optional<int64_t> height);"
    "  void SetSize(std::optional<int64_t> width, std::optional<int64_t> height);\n  void SetViewportSize(std::optional<int64_t> width, std::optional<int64_t> height, uint64_t revision);")
  bilisail_replace_once("${output}/video_output.h" "  int64_t GetVideoWidth();"
    "  std::pair<int64_t, int64_t> GetOutputDimensions() const;\n\n  int64_t GetVideoWidth();")
  bilisail_replace_once("${output}/video_output.h"
    "  std::optional<int64_t> width_ = std::nullopt;"
    "  std::optional<int64_t> width_ = std::nullopt;\n  std::optional<int64_t> viewport_width_ = std::nullopt;\n  std::optional<int64_t> viewport_height_ = std::nullopt;")
  bilisail_replace_once("${output}/video_output.h"
    "  std::optional<int64_t> viewport_height_ = std::nullopt;"
    "  std::optional<int64_t> viewport_height_ = std::nullopt;\n  uint64_t viewport_revision_ = 0;")
  bilisail_replace_once("${output}/video_output.h" "  std::atomic<bool> destroyed_{false};" [=[
  std::atomic<bool> destroyed_{false};
  std::mutex render_tasks_mutex_;
  bool render_task_queued_ = false;
  bool rendering_ = false;
  bool render_again_ = false;
  std::mutex texture_release_mutex_;
  std::condition_variable textures_released_;
  size_t pending_texture_releases_ = 0;]=])
  bilisail_replace_once("${output}/video_output.h" "  std::mutex textures_mutex_ = std::mutex();" [=[
  Microsoft::WRL::ComPtr<ID3D11Texture2D> last_video_texture_;
  HANDLE last_video_handle_ = nullptr;
  FlutterDesktopPixelBuffer last_pixel_buffer_{};
  std::mutex textures_mutex_ = std::mutex();]=])

  # A first/paused redraw cannot depend on a later ProducerCommit to promote
  # its fence. Steady-state mailbox frames retain their non-blocking path.
  bilisail_replace_once("${output}/mailbox_swap_chain.h"
    "  int write_slot_ = 0;  // producer-private"
    "  bool has_completed_frame_ = false;\n  int write_slot_ = 0;  // producer-private")
  bilisail_replace_once("${output}/mailbox_swap_chain.h" "  int32_t width() const { return width_; }" [=[
  ID3D11Texture2D* ReadTextureSnapshot() const {
    return has_completed_frame_
        ? slots_[latest_completed_slot_.load(std::memory_order_acquire)].texture.Get()
        : nullptr;
  }

  int32_t width() const { return width_; }]=])
  bilisail_replace_once("${output}/mailbox_swap_chain.cc"
    "  context4_->Signal(ws.fence.Get(), ++ws.fence_value);"
    "  context4_->Signal(ws.fence.Get(), ++ws.fence_value);\n#include \"mailbox_first_frame.inc\"")
  bilisail_replace_once("${output}/mailbox_swap_chain.cc"
    "          latest_completed_slot_.store(pend, std::memory_order_release);"
    "          latest_completed_slot_.store(pend, std::memory_order_release);\n          has_completed_frame_ = true;")
  bilisail_replace_once("${output}/mailbox_swap_chain.cc"
    "  latest_completed_slot_.store(2, std::memory_order_relaxed);"
    "  latest_completed_slot_.store(2, std::memory_order_relaxed);\n  has_completed_frame_ = false;")
  bilisail_replace_once("${output}/mailbox_swap_chain.cc" "#include <iostream>"
    "#include <iostream>\n#include <memory>")
  bilisail_replace_once("${output}/d3d11_renderer.h" "  HANDLE ConsumerAcquire();" [=[
  HANDLE ConsumerAcquire();
  // Caller serializes this snapshot with SetSize and ProducerCommit.
  ID3D11Texture2D* ReadTextureSnapshot() const {
    return mailbox_swap_chain_->ReadTextureSnapshot();
  }]=])

  file(READ "${output}/video_output.cc" text)
  string(FIND "${text}" "VideoOutput::~VideoOutput() {" begin)
  string(FIND "${text}" "void VideoOutput::Render() {" end)
  if(begin LESS 0 OR end LESS begin)
    message(FATAL_ERROR "media_kit_video disposal method boundaries changed")
  endif()
  math(EXPR count "${end} - ${begin}")
  string(SUBSTRING "${text}" ${begin} ${count} old_dispose)
  bilisail_replace_once("${output}/video_output.cc" "${old_dispose}"
    "#include \"video_output_dispose.inc\"\n\n")
  file(READ "${output}/video_output.cc" text)
  string(FIND "${text}" "int64_t VideoOutput::GetVideoWidth() {" dimensions_begin)
  if(dimensions_begin LESS 0)
    message(FATAL_ERROR "media_kit_video dimension method boundaries changed")
  endif()
  string(SUBSTRING "${text}" ${dimensions_begin} -1 old_dimensions)
  bilisail_replace_once("${output}/video_output.cc" "${old_dimensions}"
    "#include \"video_output_dimensions.inc\"\n")
  bilisail_replace_once("${output}/video_output.cc" [=[    } else {
      height_ = std::nullopt;
    }
  });]=] [=[    } else {
      height_ = std::nullopt;
    }
    // A paused/first frame may have already consumed its update notification.
    // Apply the size event immediately on the same serialized render thread.
    CheckAndResize();
    Render();
  });]=])
  bilisail_replace_once("${output}/video_output.cc"
    "void VideoOutput::CheckAndResize() {"
    "#include \"video_output_viewport.inc\"\n\nvoid VideoOutput::CheckAndResize() {")
  bilisail_replace_once("${output}/video_output.cc"
    "registrar_->texture_registrar()->UnregisterTexture(" "UnregisterTexture(")
  file(READ "${output}/video_output.cc" text)
  string(FIND "${text}" "void VideoOutput::Resize(" resize_begin)
  string(FIND "${text}" "#include \"video_output_dimensions.inc\"" resize_end)
  if(resize_begin LESS 0 OR resize_end LESS resize_begin)
    message(FATAL_ERROR "media_kit_video resize method boundary changed")
  endif()
  math(EXPR resize_length "${resize_end} - ${resize_begin}")
  string(SUBSTRING "${text}" ${resize_begin} ${resize_length} old_resize)
  bilisail_replace_once("${output}/video_output.cc" "${old_resize}"
    "#include \"video_output_resize.inc\"\n")
  bilisail_replace_once("${output}/video_output.cc" "void VideoOutput::Render() {"
    "void VideoOutput::Render() {\n  std::lock_guard<std::mutex> lock(textures_mutex_);")
  if("$ENV{BILISAIL_VIDEO_RENDER_TRACE}" STREQUAL "1")
    # Opt-in Profile probe only; regular builds have no per-frame trace work.
    bilisail_replace_once("${output}/video_output.h" "#include <optional>"
      "#include <optional>\n#include <chrono>\n#include <iostream>")
    bilisail_replace_once("${output}/video_output.h" "class VideoOutput {" [=[
class VideoRenderOperationTrace {
 public:
  VideoRenderOperationTrace(const char* name, int64_t handle)
      : name_(name), handle_(handle), start_(std::chrono::steady_clock::now()) {}
  ~VideoRenderOperationTrace() {
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start_).count();
    if (elapsed > 40) {
      std::cout << "VIDEO_RENDER_OPERATION name=" << name_ << " handle=" << handle_
                << " elapsedMs=" << elapsed << std::endl;
    }
  }
 private:
  const char* name_;
  int64_t handle_;
  std::chrono::steady_clock::time_point start_;
};
class VideoOutput {]=])
    bilisail_replace_once("${output}/video_output.cc"
      "  auto future = thread_pool_ref_->Post([&]() {" [=[
  auto future = thread_pool_ref_->Post([&]() {
    VideoRenderOperationTrace trace("create", reinterpret_cast<int64_t>(handle_));]=])
    foreach(method Render CheckAndResize)
      bilisail_replace_once("${output}/video_output.cc" "void VideoOutput::${method}() {"
        "void VideoOutput::${method}() {\n  VideoRenderOperationTrace trace(\"${method}\", reinterpret_cast<int64_t>(handle_));")
    endforeach()
    bilisail_replace_once("${output}/video_output.h" "  std::mutex render_tasks_mutex_;" [=[
  std::chrono::steady_clock::time_point trace_last_render_{};
  int64_t trace_frames_ = 0;
  int64_t trace_max_gap_ms_ = 0;
  std::atomic<int64_t> trace_update_callbacks_{0};
  std::mutex render_tasks_mutex_;]=])
    bilisail_replace_once("${output}/video_output_dispose.inc"
      "void VideoOutput::NotifyRender() {" [=[void VideoOutput::NotifyRender() {
  ++trace_update_callbacks_;]=])
    bilisail_replace_once("${output}/video_output.cc" "void VideoOutput::Render() {" [=[
void VideoOutput::Render() {
  const auto now = std::chrono::steady_clock::now();
  if (trace_frames_ > 4) {
    const auto gap = std::chrono::duration_cast<std::chrono::milliseconds>(
        now - trace_last_render_).count();
    trace_max_gap_ms_ = std::max<int64_t>(trace_max_gap_ms_, gap);
    if (gap > 50) {
      std::cout << "VIDEO_RENDER_GAP handle=" << reinterpret_cast<int64_t>(handle_)
                << " gapMs=" << gap << " atMs="
                << std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::system_clock::now().time_since_epoch()).count()
                << std::endl;
    }
  }
  trace_last_render_ = now;
  ++trace_frames_;]=])
    bilisail_replace_once("${output}/video_output_dispose.inc"
      "  thread_pool_ref_->Post([] {}).get();" [=[
  thread_pool_ref_->Post([] {}).get();
  std::cout << "VIDEO_RENDER_TRACE frames=" << trace_frames_
            << " maxGapMs=" << trace_max_gap_ms_
            << " callbacks=" << trace_update_callbacks_
            << " hardware=" << configuration_.enable_hardware_acceleration
            << std::endl;]=])
  endif()
  foreach(method Render CheckAndResize)
    bilisail_replace_once("${output}/video_output.cc" "void VideoOutput::${method}() {"
      "void VideoOutput::${method}() {\n  if (destroyed_) return;")
  endforeach()

  bilisail_replace_once("${output}/video_output_manager.h"
    "  void Dispose(int64_t handle, std::function<void()> on_disposed);"
    "  void SetViewportSize(int64_t handle, std::optional<int64_t> width, std::optional<int64_t> height, uint64_t revision);\n  void Dispose(int64_t handle, std::function<void()> on_disposed);")
  bilisail_replace_once("${output}/video_output_manager.cc" [=[void VideoOutputManager::Dispose(int64_t handle,
                                std::function<void()> on_disposed) {
  std::thread([=]() {
    std::lock_guard<std::mutex> lock(mutex_);
    video_outputs_.erase(handle);
    on_disposed();
  }).detach();
}]=] "#include \"video_output_manager_dispose.inc\"")
  bilisail_replace_once("${output}/video_output_manager.cc"
    "#include \"video_output_manager_dispose.inc\"" [=[void VideoOutputManager::SetViewportSize(
    int64_t handle, std::optional<int64_t> width,
    std::optional<int64_t> height, uint64_t revision) {
  std::thread([=]() {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto output = video_outputs_.find(handle);
    if (output != video_outputs_.end()) {
      output->second->SetViewportSize(width, height, revision);
    }
  }).detach();
}

#include "video_output_manager_dispose.inc"]=])
  bilisail_replace_once("${output}/media_kit_video_plugin.cc"
    [=[  } else if (method_call.method_name().compare("Utils.EnterNativeFullscreen") ==]=]
    [=[  } else if (method_call.method_name().compare("VideoOutputManager.SetViewportSize") ==
             0) {
    auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
    const auto handle =
        std::get<std::string>(arguments[flutter::EncodableValue("handle")]);
    const auto width =
        std::get<std::string>(arguments[flutter::EncodableValue("width")]);
    const auto height =
        std::get<std::string>(arguments[flutter::EncodableValue("height")]);
    const auto revision =
        std::get<std::string>(arguments[flutter::EncodableValue("revision")]);
    video_output_manager_->SetViewportSize(
        static_cast<int64_t>(std::stoll(handle)),
        width == "null" ? std::nullopt
                        : std::optional<int64_t>(std::stoll(width)),
        height == "null" ? std::nullopt
                         : std::optional<int64_t>(std::stoll(height)),
        static_cast<uint64_t>(std::stoull(revision)));
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("Utils.EnterNativeFullscreen") ==]=])
endfunction()

function(bilisail_patch_video_target)
  if(NOT TARGET media_kit_video_plugin)
    message(FATAL_ERROR "Expected Windows media_kit_video_plugin target")
  endif()
  get_target_property(source media_kit_video_plugin SOURCE_DIR)
  set(output "${CMAKE_BINARY_DIR}/bilisail_patches/media_kit_video")
  bilisail_patch_video_sources("${source}" "${output}")
  get_target_property(inputs media_kit_video_plugin SOURCES)
  set(patched)
  foreach(file IN LISTS inputs)
    get_filename_component(name "${file}" NAME)
    if(EXISTS "${output}/${name}")
      list(APPEND patched "${output}/${name}")
    elseif(file STREQUAL "../common/mpv/media_kit_mpv.c")
      get_filename_component(binding "${source}/${file}" ABSOLUTE)
      list(APPEND patched "${binding}")
    else()
      message(FATAL_ERROR "Unexpected media_kit_video compile input: ${file}")
    endif()
  endforeach()
  set_property(TARGET media_kit_video_plugin PROPERTY SOURCES "${patched}")
endfunction()

# Standalone source preparation for the focused native regression tests.
if(DEFINED BILISAIL_VIDEO_TEST_SOURCE AND DEFINED BILISAIL_VIDEO_TEST_OUTPUT)
  bilisail_patch_video_sources("${BILISAIL_VIDEO_TEST_SOURCE}" "${BILISAIL_VIDEO_TEST_OUTPUT}")
endif()
