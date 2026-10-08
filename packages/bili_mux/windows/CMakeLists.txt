cmake_minimum_required(VERSION 3.14)
project(bili_mux LANGUAGES CXX)
set(MUX_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../native/prebuilt/windows-x64")
if(NOT EXISTS "${MUX_DIR}/bili_mux.dll")
  message(FATAL_ERROR "Build the MP4 component first: pwsh -File tool/build-download-mux.ps1 -Target windows-x64 (from the repository root)")
endif()
set(bili_mux_bundled_libraries "${MUX_DIR}/bili_mux.dll"
  "${MUX_DIR}/bili_mux.LGPL.txt" "${MUX_DIR}/bili_mux.source.txt"
  "${MUX_DIR}/bili_mux.configuration.txt" PARENT_SCOPE)
