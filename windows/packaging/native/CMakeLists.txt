cmake_minimum_required(VERSION 3.20)
project(BiliSailInstallerUI LANGUAGES CXX)

if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "The installer UI requires Windows x64.")
endif()
if(NOT BILISAIL_WIX_SDK_DIR)
  message(FATAL_ERROR "Pass the hash-verified WiX SDK directory.")
endif()

add_library(BiliSailInstallerUI SHARED folder_picker.cpp)
target_compile_features(BiliSailInstallerUI PRIVATE cxx_std_17)
target_compile_definitions(BiliSailInstallerUI PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_include_directories(BiliSailInstallerUI SYSTEM PRIVATE
  "${BILISAIL_WIX_SDK_DIR}/wixtoolset.bootstrapperapplicationapi/build/native/include"
  "${BILISAIL_WIX_SDK_DIR}/wixtoolset.wixstandardbootstrapperapplicationfunctionapi/lib/native/include")
target_compile_options(BiliSailInstallerUI PRIVATE /W4 /WX /utf-8 /permissive- /EHsc)
# The picker runs before the app-local VC++ runtime has been installed.
set_property(TARGET BiliSailInstallerUI PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
target_link_libraries(BiliSailInstallerUI PRIVATE ole32 shell32 uuid user32 msi)
