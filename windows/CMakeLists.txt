# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(bilisail LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "bilisail")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)
include(../tool/media-kit-desktop.cmake)
bilisail_stage_video_plugin(windows)

# The pinned WebView plugin's C++17 WinRT headers use the coroutine TS ABI.
# Acknowledge their deprecation on VS 2026 without changing the coroutine ABI.
if(MSVC AND TARGET webview_all_windows_plugin)
  target_compile_definitions(webview_all_windows_plugin PRIVATE
    _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)
endif()

# MSBuild project parallelism still compiles each project's sources serially.
# Public Windows CI runners have four cores/16 GB. Keep local builds at two
# processes, and cap CI at the available processor count and four. Restrict /MP
# to Visual Studio: Ninja's /showIncludes dependency tracking is incompatible.
if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC" AND CMAKE_GENERATOR MATCHES "^Visual Studio")
  set(BILISAIL_MSVC_COMPILE_JOBS 2)
  if("$ENV{GITHUB_ACTIONS}" STREQUAL "true")
    include(ProcessorCount)
    ProcessorCount(BILISAIL_RUNNER_PROCESSORS)
    if(BILISAIL_RUNNER_PROCESSORS GREATER 0)
      set(BILISAIL_MSVC_COMPILE_JOBS ${BILISAIL_RUNNER_PROCESSORS})
      if(BILISAIL_MSVC_COMPILE_JOBS GREATER 4)
        set(BILISAIL_MSVC_COMPILE_JOBS 4)
      endif()
    endif()
  endif()
  message(STATUS "BiliSail MSVC compiler processes per target: ${BILISAIL_MSVC_COMPILE_JOBS}")
  foreach(COMPILE_TARGET IN ITEMS ${BINARY_NAME} webview_all_windows_plugin)
    if(TARGET ${COMPILE_TARGET})
      target_compile_options(${COMPILE_TARGET} PRIVATE /MP${BILISAIL_MSVC_COMPILE_JOBS})
    endif()
  endforeach()
endif()

include(patches/window_manager/apply.cmake)
bilisail_patch_window_manager_target()

# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

# An incremental build can still contain DLLs installed by the old library plugin.
install(CODE "file(REMOVE
  \"${INSTALL_BUNDLE_LIB_DIR}/libEGL.dll\"
  \"${INSTALL_BUNDLE_LIB_DIR}/libGLESv2.dll\"
  \"${INSTALL_BUNDLE_LIB_DIR}/media_kit_libs_windows_video_plugin.dll\")" COMPONENT Runtime)

# Replace the retired SDK's provenance on incremental builds.
install(CODE "file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/licenses/mpv\")" COMPONENT Runtime)

# libmpv and the native event loop are delivered by Dart code assets.
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/native/PREDIDIT_SOURCE.md"
  "${CMAKE_CURRENT_SOURCE_DIR}/native/mpv/COPYING.LGPLv2.1"
  "${CMAKE_CURRENT_SOURCE_DIR}/native/mpv/COPYING.LGPLv3"
  "${CMAKE_CURRENT_SOURCE_DIR}/native/mpv/COPYING.GPLv3"
  "${BILISAIL_NATIVE_BUNDLE_CATALOG}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/licenses/mpv"
  COMPONENT Runtime)

# The hook verifies the entire SDK archive and hashes its extracted files.
# Include the configuration and third-party notices from the same build.
if(FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64")
  set(BILISAIL_MPV_TARGET windows_arm64)
else()
  set(BILISAIL_MPV_TARGET windows_x64)
endif()
file(READ "${BILISAIL_NATIVE_BUNDLE_CATALOG}" BILISAIL_MPV_CATALOG)
string(JSON BILISAIL_MPV_DIGEST GET "${BILISAIL_MPV_CATALOG}" bundles "${BILISAIL_MPV_TARGET}" sha256)
set(BILISAIL_MPV_CACHE "${CMAKE_CURRENT_SOURCE_DIR}/../.dart_tool/hooks_runner/shared/media_kit/build/prebuilt")
install(DIRECTORY "${BILISAIL_MPV_CACHE}/${BILISAIL_MPV_DIGEST}/files/provenance/"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/licenses/mpv/provenance"
  COMPONENT Runtime)

install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../THIRD_PARTY_NOTICES.md"
  DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# The pinned WebView plugin imports this loader, but its bundled-libraries list
# omits it. NuGet copies it beside the plugin DLL before the install step.
if(TARGET webview_all_windows_plugin)
  install(FILES
    "$<TARGET_FILE_DIR:webview_all_windows_plugin>/WebView2Loader.dll"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
  set(WEBVIEW_LICENSE_DIR "${INSTALL_BUNDLE_DATA_DIR}/licenses/webview")
  install(FILES "${CMAKE_BINARY_DIR}/packages/Microsoft.Web.WebView2/LICENSE.txt"
    DESTINATION "${WEBVIEW_LICENSE_DIR}" RENAME WebView2-LICENSE.txt COMPONENT Runtime)
  install(FILES "${CMAKE_BINARY_DIR}/packages/Microsoft.Windows.ImplementationLibrary/LICENSE"
    DESTINATION "${WEBVIEW_LICENSE_DIR}" RENAME WIL-LICENSE.txt COMPONENT Runtime)
  install(FILES "${CMAKE_BINARY_DIR}/packages/Microsoft.Windows.ImplementationLibrary/ThirdPartyNotices.txt"
    DESTINATION "${WEBVIEW_LICENSE_DIR}" RENAME WIL-ThirdPartyNotices.txt COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
