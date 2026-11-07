# Test harness only. Production sources now live in CKopoer/media-kit.
# Verify and copy the dependency; never modify it or apply an application patch.
if(DEFINED BILISAIL_VIDEO_TEST_SOURCE AND DEFINED BILISAIL_VIDEO_TEST_OUTPUT)
  include("${BILISAIL_VIDEO_TEST_SOURCE}/source_manifest.cmake")
  media_kit_verify_video_sources("${BILISAIL_VIDEO_TEST_SOURCE}")
  file(MAKE_DIRECTORY "${BILISAIL_VIDEO_TEST_OUTPUT}")
  file(COPY "${BILISAIL_VIDEO_TEST_SOURCE}/" DESTINATION "${BILISAIL_VIDEO_TEST_OUTPUT}")
endif()
