// Copyright (c) 2026 BiliSail contributors. All rights reserved.
#include "fvp_audio_activity.h"
#include "../third_party/mdk/Player.h"
#include <atomic>
#include <cmath>
#include <limits>
#include <new>

namespace {
struct AudioActivity final {
  std::atomic<uint64_t> frames{0};
};

struct AudioClock final {
  mdkPlayerAPI* audio{nullptr};
  std::atomic<int64_t> anchor_ms{0};
  std::atomic<bool> held{true};
  std::atomic<bool> seeking{false};
  std::atomic<uint64_t> epoch{1};
  std::atomic<uint64_t> started_epoch{0};
  std::atomic<int64_t> last_position_ms{0};
};

double audio_clock(void* opaque) noexcept {
  auto& clock = *static_cast<AudioClock*>(opaque);
  const auto epoch = clock.epoch.load(std::memory_order_acquire);
  // A precise seek can decode a frame slightly after the requested timestamp.
  // MDK's TimestampEOS lets that paused target render without waiting for audio
  // that cannot advance until the video seek callback has completed.
  if (clock.seeking.load(std::memory_order_acquire)) {
    return (std::numeric_limits<double>::max)();
  }
  const auto anchor = clock.anchor_ms.load(std::memory_order_relaxed);
  if (clock.held.load(std::memory_order_acquire)) {
    return static_cast<double>(anchor) / 1000;
  }
  const auto position = clock.audio->position(clock.audio->object);
  // Audio-only MDK has no presentation clock until its first output tick.
  // Keep the confirmed target until that clock has actually entered this epoch.
  if (clock.seeking.load(std::memory_order_acquire)) {
    return (std::numeric_limits<double>::max)();
  }
  if (clock.held.load(std::memory_order_acquire) ||
      epoch != clock.epoch.load(std::memory_order_acquire)) {
    return static_cast<double>(clock.anchor_ms.load(std::memory_order_relaxed)) / 1000;
  }
  if (clock.started_epoch.load(std::memory_order_relaxed) != epoch) {
    if (std::abs(static_cast<double>(position) - static_cast<double>(anchor)) > 100) {
      return static_cast<double>(anchor) / 1000;
    }
    clock.started_epoch.store(epoch, std::memory_order_relaxed);
    clock.last_position_ms.store(position, std::memory_order_relaxed);
  } else {
    // MDK resets an audio-only presentation clock to zero at natural EOF.
    // Keep the last audio tick so the final video frame can finish.
    const auto last = clock.last_position_ms.load(std::memory_order_relaxed);
    if (position < last) return static_cast<double>(last) / 1000;
    clock.last_position_ms.store(position, std::memory_order_relaxed);
  }
  return static_cast<double>(position) / 1000;
}

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

void* bili_fvp_audio_clock(uintptr_t video_api, uintptr_t audio_api) {
  if (video_api == 0 || audio_api == 0) return nullptr;
  auto* video = reinterpret_cast<mdkPlayerAPI*>(video_api);
  auto* audio = reinterpret_cast<mdkPlayerAPI*>(audio_api);
  if (video->onSync == nullptr || audio->position == nullptr) return nullptr;
  auto* clock = new (std::nothrow) AudioClock;
  if (clock == nullptr) return nullptr;
  clock->audio = audio;
  video->onSync(video->object, {audio_clock, clock}, 10);
  return clock;
}

void bili_fvp_audio_clock_seek(void* clock) {
  if (clock == nullptr) return;
  auto& state = *static_cast<AudioClock*>(clock);
  state.held.store(true, std::memory_order_release);
  state.seeking.store(true, std::memory_order_release);
  state.epoch.fetch_add(1, std::memory_order_release);
}

void bili_fvp_audio_clock_hold(void* clock, int64_t position_ms) {
  if (clock == nullptr) return;
  auto& state = *static_cast<AudioClock*>(clock);
  state.held.store(true, std::memory_order_release);
  state.anchor_ms.store(position_ms, std::memory_order_relaxed);
  state.epoch.fetch_add(1, std::memory_order_release);
  state.seeking.store(false, std::memory_order_release);
}

void bili_fvp_audio_clock_play(void* clock) {
  if (clock != nullptr) {
    static_cast<AudioClock*>(clock)->held.store(false, std::memory_order_release);
  }
}

void bili_fvp_audio_clock_release(void* clock) {
  delete static_cast<AudioClock*>(clock);
}

void bili_fvp_audio_release(void* activity) {
  delete static_cast<AudioActivity*>(activity);
}
