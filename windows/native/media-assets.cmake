# One manifest for preparation, compilation and bundling. Standard OpenGL render
# API only: never combine this SDK with a DXGI render extension/header.
set(BILISAIL_MPV_ARCHIVE "mpv-dev-lgpl-x86_64-20261012-git-88eb9f2e73.7z")
set(BILISAIL_MPV_URL "https://github.com/zhongfly/mpv-winbuild/releases/download/2026-10-12-88eb9f2e73/${BILISAIL_MPV_ARCHIVE}")
set(BILISAIL_MPV_SHA256 "d1a3f57dfb3c7f07e5456e32e9ecc9e406f6457f2560ff5801c9b37a8036f507")
set(BILISAIL_MPV_FILES
  libmpv-2.dll libmpv.dll.a include/mpv/client.h include/mpv/render.h
  include/mpv/render_gl.h include/mpv/stream_cb.h)
set(BILISAIL_MPV_HASHES
  222da57d12a47680df84a8d0ad06f713fbbce4da923784ddeebe9d666135e943
  bef1b89f534bc86b33135e1f04fa2d5064b9d48b5de8bc9866665bbf43def793
  1acf99ee77c8c2a6f1d1993bd81bbc8a91d27fb5924e80171670e6139a4bd353
  192691941602052f00df0587f126246c48785a1cf21de68d22a92ea1908d1c55
  48662c0ed9872a14dd9e1684105c97f69f94a0414709c254c5d372adc41d2e69
  188e58b6d14383e15a5dffdc4ecebbdfbf2e412b9c099ff21b571f747a8ce32d)

# The pinned library plugin still resolves its own archive. Keep it verified,
# but select the corrected SDK as a complete unit after plugin registration.
set(BILISAIL_UPSTREAM_MPV_ARCHIVE "mpv-dev-x86_64-20260607-git-43b14a4.7z")
set(BILISAIL_UPSTREAM_MPV_URL "https://github.com/bggRGjQaUbCoE/mpv-winbuild-cmake/releases/download/20260607/${BILISAIL_UPSTREAM_MPV_ARCHIVE}")
set(BILISAIL_UPSTREAM_MPV_SHA256 "4efaccac571b390ba12db822a0acb50a89e9ccf0797827ca0d3b223341ceff52")
set(BILISAIL_ANGLE_ARCHIVE "ANGLE.7z")
set(BILISAIL_ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z")
set(BILISAIL_ANGLE_SHA256 "cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a")

function(bilisail_verify_file path expected)
  if(NOT EXISTS "${path}")
    message(FATAL_ERROR "Missing Windows media asset: ${path}")
  endif()
  file(SHA256 "${path}" actual)
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR "Windows media asset SHA-256 mismatch: ${path}")
  endif()
endfunction()

function(bilisail_fetch_media_archive path url expected)
  if(NOT EXISTS "${path}")
    foreach(attempt RANGE 1 3)
      file(DOWNLOAD "${url}" "${path}.partial"
        TLS_VERIFY ON TIMEOUT 180 STATUS status)
      list(GET status 0 code)
      if(code EQUAL 0)
        break()
      endif()
    endforeach()
    if(NOT code EQUAL 0)
      message(FATAL_ERROR "Windows media asset download failed: ${status}")
    endif()
    bilisail_verify_file("${path}.partial" "${expected}")
    file(RENAME "${path}.partial" "${path}")
  endif()
  bilisail_verify_file("${path}" "${expected}")
endfunction()

function(bilisail_verify_mpv_sdk sdk)
  foreach(index RANGE 0 5)
    list(GET BILISAIL_MPV_FILES ${index} file)
    list(GET BILISAIL_MPV_HASHES ${index} expected)
    bilisail_verify_file("${sdk}/${file}" "${expected}")
  endforeach()
endfunction()

function(bilisail_prepare_media_assets cache)
  file(MAKE_DIRECTORY "${cache}")
  foreach(asset UPSTREAM_MPV ANGLE)
    bilisail_fetch_media_archive("${cache}/${BILISAIL_${asset}_ARCHIVE}"
      "${BILISAIL_${asset}_URL}" "${BILISAIL_${asset}_SHA256}")
  endforeach()
  file(MAKE_DIRECTORY "${cache}/bilisail_native")
  bilisail_fetch_media_archive("${cache}/bilisail_native/${BILISAIL_MPV_ARCHIVE}"
    "${BILISAIL_MPV_URL}" "${BILISAIL_MPV_SHA256}")
endfunction()

function(bilisail_use_media_assets)
  foreach(asset UPSTREAM_MPV ANGLE)
    bilisail_verify_file("${CMAKE_BINARY_DIR}/${BILISAIL_${asset}_ARCHIVE}"
      "${BILISAIL_${asset}_SHA256}")
  endforeach()
  set(cache "${CMAKE_BINARY_DIR}/bilisail_native")
  file(MAKE_DIRECTORY "${cache}")
  bilisail_fetch_media_archive("${cache}/${BILISAIL_MPV_ARCHIVE}"
    "${BILISAIL_MPV_URL}" "${BILISAIL_MPV_SHA256}")
  set(sdk "${cache}/${BILISAIL_MPV_SHA256}")
  if(NOT EXISTS "${sdk}/libmpv-2.dll")
    file(MAKE_DIRECTORY "${sdk}")
    execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xf "${cache}/${BILISAIL_MPV_ARCHIVE}"
      WORKING_DIRECTORY "${sdk}" RESULT_VARIABLE extracted)
    if(NOT extracted EQUAL 0)
      message(FATAL_ERROR "Windows media SDK extraction failed")
    endif()
  endif()
  bilisail_verify_mpv_sdk("${sdk}")
  get_target_property(includes media_kit_video_plugin INCLUDE_DIRECTORIES)
  list(FIND includes "${CMAKE_BINARY_DIR}/libmpv/include" old_include)
  get_target_property(links media_kit_video_plugin LINK_LIBRARIES)
  list(FIND links "${CMAKE_BINARY_DIR}/libmpv/libmpv.dll.a" old_link)
  list(FIND PLUGIN_BUNDLED_LIBRARIES "${CMAKE_BINARY_DIR}/libmpv/libmpv-2.dll" old_dll)
  if(old_include LESS 0 OR old_link LESS 0 OR old_dll LESS 0)
    message(FATAL_ERROR "Pinned media-kit Windows SDK contract changed; review before building")
  endif()
  list(REMOVE_AT includes ${old_include})
  list(PREPEND includes "${sdk}/include/mpv")
  list(REMOVE_AT links ${old_link})
  list(APPEND links "${sdk}/libmpv.dll.a")
  set_property(TARGET media_kit_video_plugin PROPERTY INCLUDE_DIRECTORIES "${includes}")
  set_property(TARGET media_kit_video_plugin PROPERTY LINK_LIBRARIES "${links}")
  list(REMOVE_AT PLUGIN_BUNDLED_LIBRARIES ${old_dll})
  list(APPEND PLUGIN_BUNDLED_LIBRARIES "${sdk}/libmpv-2.dll")
  set(PLUGIN_BUNDLED_LIBRARIES "${PLUGIN_BUNDLED_LIBRARIES}" PARENT_SCOPE)
  # Recheck at install: compilation alone must never authorize shipping a stale
  # or subsequently replaced DLL. No runtime fall back to the older library.
  list(GET BILISAIL_MPV_HASHES 0 dll_hash)
  install(CODE "file(SHA256 \"${sdk}/libmpv-2.dll\" actual)
    if(NOT actual STREQUAL \"${dll_hash}\")
      message(FATAL_ERROR \"Windows libmpv changed after configuration\")
    endif()" COMPONENT Runtime)
  message(STATUS "BiliSail Windows video: ANGLE / corrected libmpv 88eb9f2e73 / Skia")
endfunction()

# Shared entry point for the PowerShell prefetch script and focused tests.
if(DEFINED BILISAIL_MEDIA_ASSET_CACHE)
  bilisail_prepare_media_assets("${BILISAIL_MEDIA_ASSET_CACHE}")
endif()
