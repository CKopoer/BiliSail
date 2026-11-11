// Copyright (c) 2026 BiliSail contributors. All rights reserved.
#include "fvp_audio_activity.h"
#include "../third_party/mdk/Player.h"
#include "../third_party/mdk/AudioFrame.h"
#include <atomic>
#include <chrono>
#include <cmath>
#include <limits>
#include <new>

namespace {
struct AudioActivity final {
  std::atomic<uint64_t> frames{0};
  std::atomic<int64_t> end_ms{-1};
};

struct AudioClock final {
  mdkPlayerAPI* video{nullptr};
  mdkPlayerAPI* audio{nullptr};
  std::atomic<bool> detached{false};
  std::atomic<int64_t> anchor_ms{0};
  std::atomic<bool> held{true};
  std::atomic<bool> seeking{false};
  std::atomic<uint64_t> epoch{1};
  std::atomic<uint64_t> started_epoch{0};
  std::atomic<int64_t> last_position_ms{0};
  std::atomic<int64_t> resumed_at_ns{0};
};

int64_t monotonic_nanoseconds() noexcept {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
      std::chrono::steady_clock::now().time_since_epoch()).count();
}

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
    // onSync runs when video is about to render, not when audio starts. A
    // delayed renderer can miss the first 100ms of a healthy audio epoch. Only
    // reject positions outside the range audio could have reached since play;
    // never synthesize a clock from elapsed time or require that narrow tick.
    const auto elapsed_ns = monotonic_nanoseconds() -
        clock.resumed_at_ns.load(std::memory_order_relaxed);
    const auto native_rate = clock.audio->playbackRate == nullptr
        ? 1.0 : static_cast<double>(clock.audio->playbackRate(clock.audio->object));
    const auto rate = std::isfinite(native_rate) && native_rate > 0 ? native_rate : 1.0;
    const auto elapsed_ms = elapsed_ns > 0 ? static_cast<double>(elapsed_ns) / 1000000 : 0;
    const auto offset_ms = static_cast<double>(position) - static_cast<double>(anchor);
    if (offset_ms < -100 || offset_ms > 100 + elapsed_ms * rate) {
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
    auto& activity = *static_cast<AudioActivity*>(opaque);
    activity.frames.fetch_add(1, std::memory_order_relaxed);
    const auto* api = *frame;
    if (api->timestamp != nullptr && api->duration != nullptr &&
        api->samplesPerChannel != nullptr && api->samplesPerChannel(api->object) > 0) {
      const auto timestamp = api->timestamp(api->object);
      const auto duration = api->duration(api->object);
      const auto end_ms = (timestamp + duration) * 1000;
      // EOS has TimestampEOS and no samples. Never let it, NaN or an invalid
      // timestamp conceal a truncated stream. No PCM or frame pointer escapes.
      if (std::isfinite(timestamp) && timestamp >= 0 &&
          std::isfinite(duration) && duration >= 0 && std::isfinite(end_ms) &&
          end_ms >= 0 && end_ms < static_cast<double>((std::numeric_limits<int64_t>::max)())) {
        activity.end_ms.store(static_cast<int64_t>(end_ms), std::memory_order_relaxed);
      }
    }
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

int64_t bili_fvp_audio_end(void* activity) {
  return activity == nullptr ? -1 : static_cast<AudioActivity*>(activity)->end_ms.load(
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
  clock->video = video;
  video->onSync(video->object, {audio_clock, clock}, 10);
  return clock;
}

void bili_fvp_audio_clock_seek(void* clock) {
  if (clock == nullptr) return;
  auto& state = *static_cast<AudioClock*>(clock);
  state.held.store(true, std::memory_order_release);
  state.seeking.store(true, std::memory_order_release);
  state.epoch.fetch_add(1, std::memory_order_release);
  if (state.detached.exchange(false, std::memory_order_acq_rel)) {
    state.video->onSync(state.video->object, {audio_clock, &state}, 10);
  }
}

void bili_fvp_audio_clock_end(void* clock) {
  if (clock == nullptr) return;
  auto& state = *static_cast<AudioClock*>(clock);
  if (!state.detached.exchange(true, std::memory_order_acq_rel)) {
    state.video->onSync(state.video->object, {nullptr, nullptr}, 10);
  }
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
    auto& state = *static_cast<AudioClock*>(clock);
    if (state.held.load(std::memory_order_acquire)) {
      state.resumed_at_ns.store(monotonic_nanoseconds(), std::memory_order_relaxed);
      state.held.store(false, std::memory_order_release);
    }
  }
}

void bili_fvp_audio_clock_release(void* clock) {
  delete static_cast<AudioClock*>(clock);
}

void bili_fvp_audio_release(void* activity) {
  delete static_cast<AudioActivity*>(activity);
}
