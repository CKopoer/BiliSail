# Pin the experimental SDK independently of the unchanged media-kit assets.
include("${CMAKE_CURRENT_LIST_DIR}/resolve.cmake")
if(WIN32)
  if(FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64")
    set(_bilisail_fvp_platform windows-arm64)
    set(_bilisail_fvp_alias mdk-sdk-windows.7z)
  else()
    set(_bilisail_fvp_platform windows-x64)
    set(_bilisail_fvp_alias mdk-sdk-windows-x64.7z)
  endif()
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
  set(_bilisail_fvp_platform linux-x64)
else()
  message(FATAL_ERROR "The experimental fvp SDK is only pinned for Linux x64 and Windows x64/ARM64")
endif()
bilisail_fvp_asset("${_bilisail_fvp_platform}"
  _bilisail_fvp_base _bilisail_fvp_archive _bilisail_fvp_sha)
if(WIN32)
  # Upstream fvp uses a generic filename; the fixed release adds the toolchain
  # suffix. Stage its verified bytes under that alias in the build directory.
  # Isolate SDK revisions, including partial downloads with the same filename.
  set(_bilisail_fvp_stage "${CMAKE_BINARY_DIR}/fvp-deps/${_bilisail_fvp_sha}")
  file(MAKE_DIRECTORY "${_bilisail_fvp_stage}")
  set(_bilisail_fvp_sdk "${_bilisail_fvp_stage}/${_bilisail_fvp_alias}")
  set(_bilisail_fvp_cached_sha "")
  if(EXISTS "${_bilisail_fvp_sdk}")
    file(SHA256 "${_bilisail_fvp_sdk}" _bilisail_fvp_cached_sha)
  endif()
  if(NOT _bilisail_fvp_cached_sha STREQUAL _bilisail_fvp_sha)
    # Use Windows' curl TLS implementation, retaining certificate validation.
    find_program(_bilisail_fvp_curl curl.exe REQUIRED)
    execute_process(COMMAND "${_bilisail_fvp_curl}" --fail --location --silent
      --show-error --http1.1 --continue-at - --retry 3 --retry-all-errors
      --speed-time 25 --speed-limit 1024 --max-time 300
      "${_bilisail_fvp_base}/${_bilisail_fvp_archive}" --output "${_bilisail_fvp_sdk}.part"
      RESULT_VARIABLE _bilisail_fvp_download_code)
    if(NOT _bilisail_fvp_download_code EQUAL 0)
      message(FATAL_ERROR "Could not download the pinned fvp SDK: ${_bilisail_fvp_download_code}")
    endif()
    file(SHA256 "${_bilisail_fvp_sdk}.part" _bilisail_fvp_download_sha)
    if(NOT _bilisail_fvp_download_sha STREQUAL _bilisail_fvp_sha)
      # Rejected bytes cannot be resumed safely on the next configure attempt.
      file(REMOVE "${_bilisail_fvp_sdk}.part")
      message(FATAL_ERROR "The fvp SDK archive SHA-256 does not match the lock")
    endif()
    file(RENAME "${_bilisail_fvp_sdk}.part" "${_bilisail_fvp_sdk}")
  endif()
  set(FVP_DEPS_URL "file:///${_bilisail_fvp_stage}" CACHE STRING "Pinned MDK SDK location" FORCE)
else()
  set(FVP_DEPS_URL "${_bilisail_fvp_base}" CACHE STRING "Pinned MDK SDK release" FORCE)
endif()
set(FVP_DEPS_SHA256 "${_bilisail_fvp_sha}" CACHE STRING "Pinned MDK SDK SHA-256" FORCE)
