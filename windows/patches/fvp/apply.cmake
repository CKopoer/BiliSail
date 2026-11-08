# Patch a verified build-tree copy, never the Pub cache. The media-kit fork
# owns the D3D11 snapshot implementation shared by both Windows backends.
set(_bilisail_fvp_patch_dir "${CMAKE_CURRENT_LIST_DIR}")
function(bilisail_prepare_fvp_source source_dir output)
  file(READ "${source_dir}/fvp_plugin.cpp" source)
  string(REPLACE "\r\n" "\n" source "${source}")
  string(SHA256 digest "${source}")
  if(NOT digest STREQUAL "2e9c97959668257a37c1c258ae0023ab33e168b0f618145a916201cf487a330f")
    message(FATAL_ERROR "Review the fvp texture patch against the new pinned source")
  endif()
  string(FIND "${source}" "class TexturePlayer final: public Player" start)
  string(FIND "${source}" "template<typename T>" end)
  if(start LESS 0 OR end LESS start)
    message(FATAL_ERROR "Could not locate the verified fvp TexturePlayer")
  endif()
  string(SUBSTRING "${source}" 0 ${start} prefix)
  string(SUBSTRING "${source}" ${end} -1 suffix)
  set(patched "${prefix}#include \"texture_player.inc\"\n\n${suffix}")
  string(REPLACE "#include <flutter/standard_method_codec.h>"
    "#include <flutter/standard_method_codec.h>\n#include \"d3d11_texture_snapshot.h\""
    patched "${patched}")
  file(MAKE_DIRECTORY "${output}")
  file(WRITE "${output}/fvp_plugin.cpp" "${patched}")
endfunction()

function(bilisail_patch_fvp_target)
  get_target_property(source_dir fvp_plugin SOURCE_DIR)
  get_target_property(media_dir media_kit_video_plugin SOURCE_DIR)
  set(output "${CMAKE_CURRENT_BINARY_DIR}/fvp-texture-handoff")
  bilisail_prepare_fvp_source("${source_dir}" "${output}")
  get_target_property(sources fvp_plugin SOURCES)
  list(FILTER sources EXCLUDE REGEX "(^|/)fvp_plugin\\.cpp$")
  set_property(TARGET fvp_plugin PROPERTY SOURCES
    ${sources} "${output}/fvp_plugin.cpp")
  target_include_directories(fvp_plugin PRIVATE
    "${source_dir}" "${media_dir}" "${_bilisail_fvp_patch_dir}")
  # Reconfigure when either input changes, including edits after an initial build.
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${source_dir}/fvp_plugin.cpp" "${_bilisail_fvp_patch_dir}/texture_player.inc")
endfunction()

if(DEFINED BILISAIL_FVP_TEST_SOURCE AND DEFINED BILISAIL_FVP_TEST_OUTPUT)
  bilisail_prepare_fvp_source("${BILISAIL_FVP_TEST_SOURCE}" "${BILISAIL_FVP_TEST_OUTPUT}")
endif()
