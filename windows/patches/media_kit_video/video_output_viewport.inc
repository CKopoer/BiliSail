// BiliSail Windows viewport cap for PiliPlus media_kit_video fd8421d (MIT; see LICENSE).

void VideoOutput::SetViewportSize(std::optional<int64_t> width,
                                  std::optional<int64_t> height,
                                  uint64_t revision) {
  thread_pool_ref_->Post([this, width, height, revision] {
    if (destroyed_ || revision <= viewport_revision_) {
      return;
    }
    viewport_revision_ = revision;
    viewport_width_ = width;
    viewport_height_ = height;
    // Apply expansion immediately and redraw even if paused. Dart defers
    // shrink requests during live window drag; this queue remains serialized.
    CheckAndResize();
    Render();
  });
}
