// Copyright (c) 2026 BiliSail contributors. All rights reserved.
#include "fvp_audio_activity.h"
#include "../third_party/mdk/Player.h"
#include <atomic>
#include <new>

namespace {
struct AudioActivity final {
  std::atomic<uint64_t> frames{0};
};

int observe_audio(mdkAudioFrameAPI** frame, int, void* opaque) noexcept {
  // Keep PCM and borrowed frame pointers in MDK. This callback must never call
  // Dart, allocate, wait, or modify the frame/filter's pending-frame count.
  if (frame != nullptr && *frame != nullptr) {
    static_cast<AudioActivity*>(opaque)->frames.fetch_add(
        1, std::memory_order_relaxed);
  }
  return 0;
}
}  // namespace

void* bili_fvp_audio_attach(uintptr_t player_api) {
  if (player_api == 0) return nullptr;
  auto* api = reinterpret_cast<mdkPlayerAPI*>(player_api);
  if (api->onAudio == nullptr) return nullptr;
  auto* activity = new (std::nothrow) AudioActivity;
  if (activity == nullptr) return nullptr;
  api->onAudio(api->object, {observe_audio, activity});
  return activity;
}

uint64_t bili_fvp_audio_frames(void* activity) {
  return activity == nullptr ? 0 : static_cast<AudioActivity*>(activity)->frames.load(
      std::memory_order_relaxed);
}

void bili_fvp_audio_release(void* activity) {
  delete static_cast<AudioActivity*>(activity);
}
