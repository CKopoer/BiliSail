# Match the exact archives declared by PiliPlus's pinned library plugin.
file(SHA256 "${CMAKE_BINARY_DIR}/mpv-dev-x86_64-20260607-git-43b14a4.7z" mpv_archive_sha)
file(SHA256 "${CMAKE_BINARY_DIR}/ANGLE.7z" angle_archive_sha)
if(NOT mpv_archive_sha STREQUAL "4efaccac571b390ba12db822a0acb50a89e9ccf0797827ca0d3b223341ceff52"
    OR NOT angle_archive_sha STREQUAL "cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a")
  message(FATAL_ERROR "PiliPlus native archive changed; review its source before building")
endif()

# Upstream reuses any nonempty extracted directory. Reject an old fork's DLL
# when reusing a build tree; do not silently ship an unrelated cached binary.
install(CODE "
  file(SHA256 \"${CMAKE_BINARY_DIR}/libmpv/libmpv-2.dll\" mpv_dll_sha)
  if(NOT mpv_dll_sha STREQUAL \"4b517ce76493c7d6b6568dde6e2839e3bb6a41c4b46b0e972492f354ad444ba4\")
    message(FATAL_ERROR \"Stale libmpv build directory: rebuild with a fresh build/windows/x64/libmpv directory\")
  endif()
" COMPONENT Runtime)
