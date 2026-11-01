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
  set(files video_output.h video_output.cc video_output_manager.h
    video_output_manager.cc media_kit_video_plugin.cc
    angle_surface_manager.h angle_surface_manager.cc media_kit_video_plugin.h)
  set(hashes
    e276c8b80e9e117d60713b3b25b12ddb0df1878a2c076fe946847ac7eec7c17a
    198cb59a97070b61df5ee8ae35ac3e0bc344f3174f6e4aaf7b77e7357d606548
    42228d0f1bb2cb99cf31a3b12422d4246207ad227298c723744a1806f1ebfc65
    bfdd46d2bf19094af5b912f6ac922d91f41fd3b3e6202a11a9c2012ce59461be
    ae8b152269f0e9aee4d18a77d8d37a738e92742aba265346081d5e0a30e556ea
    3c7f24a94a8f7e8b551877142ea12b92d1543d4f8384370d55c3b5147eefe6ef
    04eadbea88ce1d825a732c8ea96f9557bb19c275330f4abf7836950e7efd2e2a
    57db187bd3832ccd4dbf9507cfe0c1252e0ca20d5663ddcd78e5c24becec7269)
  foreach(index RANGE 0 7)
    list(GET files ${index} file)
    list(GET hashes ${index} expected)
    file(READ "${source}/${file}" original)
    string(REPLACE "\r\n" "\n" original "${original}")
    string(SHA256 actual "${original}")
    if(NOT actual STREQUAL expected)
      message(FATAL_ERROR "PiliPlus media_kit_video fd8421d source changed: ${file}; review the Windows lifecycle patch before building")
    endif()
  endforeach()
  file(GLOB_RECURSE inputs RELATIVE "${source}" "${source}/*")
  foreach(file IN LISTS inputs)
    configure_file("${source}/${file}" "${output}/${file}" COPYONLY)
  endforeach()
  foreach(file video_output_dispose.inc video_output_manager_dispose.inc
    video_output_dimensions.inc video_output_viewport.inc angle_gpu_queue.inc plugin_main_thread.inc video_output_resize.inc)
    configure_file("${BILISAIL_VIDEO_PATCH_DIR}/${file}" "${output}/${file}" COPYONLY)
  endforeach()

  bilisail_replace_once("${output}/media_kit_video_plugin.h" "#include <flutter/method_channel.h>"
    "#include <flutter/method_channel.h>\n#include <Windows.h>\n#include <functional>\n#include <mutex>\n#include <optional>\n#include <queue>\n#include <stdexcept>")
  bilisail_replace_once("${output}/media_kit_video_plugin.h" " private:" [=[ private:
  static constexpr UINT kMainThreadTaskMessage = WM_APP + 1001;
  void InitializeMainThreadTasks();
  void RunOnMainThread(std::function<void()> task);
  static LRESULT CALLBACK MainThreadWindowProc(HWND, UINT, WPARAM, LPARAM);
  DWORD platform_thread_ = 0;
  HWND task_window_ = nullptr;
  std::queue<std::function<void()>> main_thread_tasks_;
  std::mutex main_thread_tasks_mutex_;
]=])
  bilisail_replace_once("${output}/media_kit_video_plugin.cc"
    "  channel_ = std::make_unique" "  InitializeMainThreadTasks();\n  channel_ = std::make_unique")
  bilisail_replace_once("${output}/media_kit_video_plugin.cc"
    "MediaKitVideoPlugin::~MediaKitVideoPlugin() {}" [=[MediaKitVideoPlugin::~MediaKitVideoPlugin() {
  ::DestroyWindow(task_window_);
}
#include "plugin_main_thread.inc"
]=])
  bilisail_replace_once("${output}/media_kit_video_plugin.cc"
    "[channel_ptr = channel_.get(), handle = handle_value]"
    "[this, channel_ptr = channel_.get(), handle = handle_value]")
  bilisail_replace_once("${output}/media_kit_video_plugin.cc"
    "          channel_ptr->InvokeMethod(" "          RunOnMainThread([channel_ptr, handle, id, width, height] {\n          channel_ptr->InvokeMethod(")
  bilisail_replace_once("${output}/media_kit_video_plugin.cc"
    "              nullptr);" "              nullptr);\n          });")

  bilisail_replace_once("${output}/angle_surface_manager.h" "#include <d3d11.h>"
    "#include <d3d11.h>\n#include <d3d10.h>\n#include <optional>")
  bilisail_replace_once("${output}/angle_surface_manager.h" "  void Read();"
    [=[  HANDLE Read();
  bool HasFrame() const { return has_frame_; }
  Microsoft::WRL::ComPtr<ID3D11Texture2D> TextureForHandle(HANDLE handle) const {
    return handle == internal_handle_ ? internal_d3d_11_texture_2D_
                                      : d3d_11_texture_2D_;
  }]=])
  bilisail_replace_once("${output}/angle_surface_manager.h" "  bool CreateD3DTexture();"
    "  bool CreateD3DTexture();\n  bool UseAngleDevice();")
  bilisail_replace_once("${output}/angle_surface_manager.h"
    "  ID3D11Device* d3d_11_device_ = nullptr;"
    "  bool has_frame_ = false;\n  bool uses_angle_device_ = false;\n  uint64_t draw_revision_ = 0;\n  std::optional<uint64_t> copied_revision_;\n  std::optional<bool> last_direct_;\n  ID3D11Device* d3d_11_device_ = nullptr;")
  file(READ "${output}/angle_surface_manager.cc" angle_text)
  string(FIND "${angle_text}" "void ANGLESurfaceManager::Draw(" angle_begin)
  string(FIND "${angle_text}" "void ANGLESurfaceManager::MakeCurrent(" angle_end)
  math(EXPR angle_count "${angle_end} - ${angle_begin}")
  string(SUBSTRING "${angle_text}" ${angle_begin} ${angle_count} angle_old)
  bilisail_replace_once("${output}/angle_surface_manager.cc" "${angle_old}"
    "#include \"angle_gpu_queue.inc\"\n\n")
  bilisail_replace_once("${output}/angle_surface_manager.cc" [=[void ANGLESurfaceManager::SwapBuffers() {
  glFinish();
}

]=] "")
  bilisail_replace_once("${output}/angle_surface_manager.cc" [=[  if (!CreateD3DTexture()) {
    throw std::runtime_error("Unable to create Windows Direct3D device.");
    return;
  }
  if (!CreateEGLDisplay()) {
    throw std::runtime_error("Unable to create ANGLE EGL display.");
    return;
  }]=] [=[  if (!CreateEGLDisplay()) {
    throw std::runtime_error("Unable to create ANGLE EGL display.");
  }
  if (!CreateD3DTexture()) {
    throw std::runtime_error("Unable to create Windows Direct3D device.");
  }]=])
  bilisail_replace_once("${output}/angle_surface_manager.cc"
    "  if (d3d_11_device_ == nullptr) {"
    "  if (d3d_11_device_ == nullptr) UseAngleDevice();\n  has_frame_ = false;\n  copied_revision_.reset();\n  if (d3d_11_device_ == nullptr) {")
  bilisail_replace_once("${output}/angle_surface_manager.cc" [=[    if (instance_count_ == 1) {
      eglTerminate(display_);
    }]=] [=[    // EGL's default display can also belong to Flutter. Contexts and surfaces
    // are released above; do not terminate another component's live display.]=])
  bilisail_replace_once("${output}/video_output.cc" [=[                surface_manager_->Read();
                return textures_.at(texture_id_).get();]=] [=[                auto* descriptor = textures_.at(texture_id_).get();
                descriptor->handle = surface_manager_->Read();
                return descriptor;]=])

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
  bilisail_replace_once("${output}/video_output.h" "  bool destroyed_ = false;" [=[
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

  bilisail_replace_once("${output}/video_output_manager.h" "  void Dispose(int64_t handle);"
    "  void Dispose(int64_t handle, std::function<void()> on_disposed);")
  bilisail_replace_once("${output}/video_output_manager.h"
    "  void Dispose(int64_t handle, std::function<void()> on_disposed);"
    "  void SetViewportSize(int64_t handle, std::optional<int64_t> width, std::optional<int64_t> height, uint64_t revision);\n  void Dispose(int64_t handle, std::function<void()> on_disposed);")
  bilisail_replace_once("${output}/video_output_manager.cc" [=[void VideoOutputManager::Dispose(int64_t handle) {
  std::thread([=]() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (video_outputs_.find(handle) != video_outputs_.end()) {
      video_outputs_.erase(handle);
    }
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
  bilisail_replace_once("${output}/media_kit_video_plugin.cc" [=[    video_output_manager_->Dispose(handle_value);
    result->Success(flutter::EncodableValue(std::monostate{}));]=] [=[    auto reply = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
        std::move(result));
    video_output_manager_->Dispose(handle_value, [this, reply] {
      RunOnMainThread([reply] {
        reply->Success(flutter::EncodableValue(std::monostate{}));
      });
    });]=])
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
    if(NOT EXISTS "${output}/${name}")
      message(FATAL_ERROR "Unexpected media_kit_video compile input: ${file}")
    endif()
    list(APPEND patched "${output}/${name}")
  endforeach()
  set_property(TARGET media_kit_video_plugin PROPERTY SOURCES "${patched}")
endfunction()

# Standalone source preparation for the focused native regression tests.
if(DEFINED BILISAIL_VIDEO_TEST_SOURCE AND DEFINED BILISAIL_VIDEO_TEST_OUTPUT)
  bilisail_patch_video_sources("${BILISAIL_VIDEO_TEST_SOURCE}" "${BILISAIL_VIDEO_TEST_OUTPUT}")
endif()
