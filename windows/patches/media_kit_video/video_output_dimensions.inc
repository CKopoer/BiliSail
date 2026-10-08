// BiliSail render-thread dimensions for media_kit_video 2.0.1 (MIT; see LICENSE).

// NativeVideoController sends decoded display dimensions (including rotation
// and pixel aspect) through SetSize. Never call mpv_get_property on the render
// thread: the mpv core can be waiting for that same thread to render a frame.
// Before the first size event, keep the placeholder texture and skip resizing.
int64_t VideoOutput::GetVideoWidth() {
  return width_.value_or(0);
}

int64_t VideoOutput::GetVideoHeight() {
  return height_.value_or(0);
}
