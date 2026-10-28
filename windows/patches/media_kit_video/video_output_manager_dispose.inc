// BiliSail lifecycle replacement for Predidit media-kit 83b7ca6 (MIT; see LICENSE).

void VideoOutputManager::Dispose(int64_t handle,
                                 std::function<void()> on_disposed) {
  std::thread([this, handle, on_disposed = std::move(on_disposed)] {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      video_outputs_.erase(handle);
    }
    // The VideoOutput destructor has drained rendering and freed the mpv
    // context. Only now may Dart proceed to Player's delayed core destruction.
    on_disposed();
  }).detach();
}
