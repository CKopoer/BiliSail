# window_manager 0.5.2 is a main-window plugin. Flutter's windowing owner sends
# messages from every view to plugin delegates, so confine its policies to the
# implicit window. Patch only a verified build copy, never the Pub cache.
function(bilisail_patch_window_manager_target)
  if(NOT TARGET window_manager_plugin)
    message(FATAL_ERROR "Expected Windows window_manager_plugin target")
  endif()
  get_target_property(source window_manager_plugin SOURCE_DIR)
  get_filename_component(source "${source}" REALPATH)
  file(SHA256 "${source}/window_manager_plugin.cpp" actual)
  if(NOT actual STREQUAL "6fa2dc3eea3543108957a142e273a4fc9faf101bae09444bcd9be4712d3238d0")
    message(FATAL_ERROR "window_manager 0.5.2 source changed; review the multi-view message guard")
  endif()
  set(output "${CMAKE_BINARY_DIR}/bilisail_patches/window_manager")
  file(GLOB_RECURSE inputs RELATIVE "${source}" "${source}/*")
  foreach(file IN LISTS inputs)
    configure_file("${source}/${file}" "${output}/${file}" COPYONLY)
  endforeach()
  bilisail_replace_once("${output}/window_manager_plugin.cpp"
    "  std::optional<LRESULT> result = std::nullopt;"
    [=[  const auto implicit_view = registrar->GetView();
  if (!implicit_view ||
      ::GetAncestor(implicit_view->GetNativeWindow(), GA_ROOT) != hWnd) {
    return std::nullopt;
  }
  std::optional<LRESULT> result = std::nullopt;]=])
  get_target_property(inputs window_manager_plugin SOURCES)
  set(patched)
  foreach(file IN LISTS inputs)
    get_filename_component(name "${file}" NAME)
    if(NOT EXISTS "${output}/${name}")
      message(FATAL_ERROR "Unexpected window_manager compile input: ${file}")
    endif()
    list(APPEND patched "${output}/${name}")
  endforeach()
  set_property(TARGET window_manager_plugin PROPERTY SOURCES "${patched}")
endfunction()
include("${CMAKE_CURRENT_LIST_DIR}/../replace_once.cmake")
