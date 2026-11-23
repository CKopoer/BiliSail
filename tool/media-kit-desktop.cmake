# Compile the plugin from a build copy so Flutter's generated registration
# and the Pub checkout both retain their original layout.
function(bilisail_stage_video_plugin platform)
  find_package(Python3 REQUIRED COMPONENTS Interpreter)
  set(tool "${CMAKE_CURRENT_SOURCE_DIR}/../tool")
  set(stage "${CMAKE_CURRENT_BINARY_DIR}/bilisail-media-kit/${platform}")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${tool}/media-kit-patches/mpv-client.patch"
    "${tool}/media-kit-patches/${platform}.patch" "${tool}/media_kit_sources.py"
    "${CMAKE_CURRENT_SOURCE_DIR}/../.dart_tool/package_config.json")
  execute_process(COMMAND "${Python3_EXECUTABLE}" "${tool}/media_kit_sources.py"
    "${platform}" "${stage}" RESULT_VARIABLE status)
  if(NOT status EQUAL 0)
    message(FATAL_ERROR "Could not stage the pinned ${platform} video plugin")
  endif()
  set(BILISAIL_NATIVE_BUNDLE_CATALOG "${stage}/native_bundles.json" PARENT_SCOPE)
  target_include_directories(media_kit_video_plugin BEFORE PRIVATE "${stage}/common/mpv/include")
  get_target_property(sources media_kit_video_plugin SOURCES)
  set(staged_sources "")
  foreach(source IN LISTS sources)
    list(APPEND staged_sources "${stage}/${platform}/${source}")
  endforeach()
  set_property(TARGET media_kit_video_plugin PROPERTY SOURCES "${staged_sources}")
endfunction()
