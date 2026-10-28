// BiliSail render-thread dimensions for Predidit media-kit 83b7ca6 (MIT; see LICENSE).

// NativeVideoController sends decoded display dimensions (including rotation
// and pixel aspect) through SetSize. The BiliSail viewport is independent, so
// later decoder size events cannot overwrite a small window's output cap.
// Never call mpv_get_property on the render thread: mpv can be waiting for it.
std::pair<int64_t, int64_t> VideoOutput::GetOutputDimensions() const {
  const auto width = width_.value_or(0);
  const auto height = height_.value_or(0);
  if (width < 1 || height < 1 || !viewport_width_.has_value() ||
      !viewport_height_.has_value() || viewport_width_.value() < 1 ||
      viewport_height_.value() < 1) {
    return {width, height};
  }
  const auto scale = (std::min)(
      {1.0, static_cast<double>(viewport_width_.value()) / width,
       static_cast<double>(viewport_height_.value()) / height});
  return {
      (std::min)(viewport_width_.value(),
                 (std::max<int64_t>)(1, static_cast<int64_t>(std::ceil(width * scale)))),
      (std::min)(viewport_height_.value(),
                 (std::max<int64_t>)(1, static_cast<int64_t>(std::ceil(height * scale))))};
}

int64_t VideoOutput::GetVideoWidth() {
  return GetOutputDimensions().first;
}

int64_t VideoOutput::GetVideoHeight() {
  return GetOutputDimensions().second;
}
