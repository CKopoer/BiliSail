// BiliSail first-frame promotion for Predidit media-kit 83b7ca6 (MIT).
// Included immediately after the producer signals its rendered frame's fence.
// Only the first frame of a new mailbox allocation waits; normal playback
// continues to promote completed frames without blocking either thread.
if (!has_completed_frame_) {
  bool completed = ws.fence->GetCompletedValue() >= ws.fence_value;
  if (!completed) {
    const auto close_event = [](HANDLE event) { CloseHandle(event); };
    const std::unique_ptr<void, decltype(close_event)> event(
        CreateEventW(nullptr, FALSE, FALSE, nullptr), close_event);
    if (event && SUCCEEDED(ws.fence->SetEventOnCompletion(ws.fence_value,
                                                          event.get()))) {
      context4_->Flush();
      completed = WaitForSingleObject(event.get(), 100) == WAIT_OBJECT_0;
    }
  }
  if (completed) {
    const auto state = mailbox_state_.load(std::memory_order_relaxed);
    const auto free = state & 0x3u;
    const auto previous_completed = (state >> 2) & 0x3u;
    const auto extra = (state >> 4) & 0x3u;
    // Publish this painted slot directly, retaining distinct completed/free/
    // extra/write roles. No second video frame is needed while paused.
    mailbox_state_.store((previous_completed << 4) |
                             (static_cast<uint32_t>(write_slot_) << 2) | extra,
                         std::memory_order_release);
    latest_completed_slot_.store(write_slot_, std::memory_order_release);
    write_slot_ = static_cast<int>(free);
    has_completed_frame_ = true;
    return;
  }
  // A stalled GPU must not block the rendering thread indefinitely. The
  // output keeps its previous completed texture until a later commit succeeds.
}
