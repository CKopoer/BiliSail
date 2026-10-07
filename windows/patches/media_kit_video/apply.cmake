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
    video_output_manager.cc media_kit_video_plugin.cc)
  set(hashes
    e276c8b80e9e117d60713b3b25b12ddb0df1878a2c076fe946847ac7eec7c17a
    198cb59a97070b61df5ee8ae35ac3e0bc344f3174f6e4aaf7b77e7357d606548
    42228d0f1bb2cb99cf31a3b12422d4246207ad227298c723744a1806f1ebfc65
    bfdd46d2bf19094af5b912f6ac922d91f41fd3b3e6202a11a9c2012ce59461be
    00ecd361cd61791bf4cb9c6beb84f82614ef5788dcb1ae51e70c66d347a080a0)
  foreach(index RANGE 0 4)
    list(GET files ${index} file)
    list(GET hashes ${index} expected)
    file(SHA256 "${source}/${file}" actual)
    if(NOT actual STREQUAL expected)
      message(FATAL_ERROR "media_kit_video 2.0.1 source changed: ${file}; review the Windows lifecycle patch before building")
    endif()
  endforeach()
  file(GLOB_RECURSE inputs RELATIVE "${source}" "${source}/*")
  foreach(file IN LISTS inputs)
    configure_file("${source}/${file}" "${output}/${file}" COPYONLY)
  endforeach()
  foreach(file video_output_dispose.inc video_output_manager_dispose.inc)
    configure_file("${BILISAIL_VIDEO_PATCH_DIR}/${file}" "${output}/${file}" COPYONLY)
  endforeach()

  bilisail_replace_once("${output}/video_output.h" "#include <optional>"
    "#include <optional>\n#include <atomic>\n#include <condition_variable>")
  bilisail_replace_once("${output}/video_output.h" "  void NotifyRender();"
    "  void UnregisterTexture(int64_t id, std::function<void()> callback);\n\n  void NotifyRender();")
  bilisail_replace_once("${output}/video_output.h" "  bool destroyed_ = false;" [=[
  std::atomic<bool> destroyed_{false};
  std::mutex render_tasks_mutex_;
  std::mutex texture_release_mutex_;
  std::condition_variable textures_released_;
  size_t pending_texture_releases_ = 0;]=])

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
  bilisail_replace_once("${output}/video_output.cc"
    "registrar_->texture_registrar()->UnregisterTexture(" "UnregisterTexture(")
  foreach(method Render CheckAndResize)
    bilisail_replace_once("${output}/video_output.cc" "void VideoOutput::${method}() {"
      "void VideoOutput::${method}() {\n  if (destroyed_) return;")
  endforeach()

  bilisail_replace_once("${output}/video_output_manager.h" "  void Dispose(int64_t handle);"
    "  void Dispose(int64_t handle, std::function<void()> on_disposed);")
  bilisail_replace_once("${output}/video_output_manager.cc" [=[void VideoOutputManager::Dispose(int64_t handle) {
  std::thread([=]() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (video_outputs_.find(handle) != video_outputs_.end()) {
      video_outputs_.erase(handle);
    }
  }).detach();
}]=] "#include \"video_output_manager_dispose.inc\"")
  bilisail_replace_once("${output}/media_kit_video_plugin.cc" [=[    video_output_manager_->Dispose(handle_value);
    result->Success(flutter::EncodableValue(std::monostate{}));]=] [=[    auto reply = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
        std::move(result));
    video_output_manager_->Dispose(handle_value, [this, reply] {
      RunOnMainThread([reply] {
        reply->Success(flutter::EncodableValue(std::monostate{}));
      });
    });]=])
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
