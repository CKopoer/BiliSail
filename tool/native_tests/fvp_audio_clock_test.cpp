#include "../../packages/bili_player/src/fvp_audio_activity.cpp"
#include <cstdlib>
#include <iostream>

namespace {
mdkSyncCallback sync_callback{};
int sync_interval = 0;
int64_t audio_position = 0;

void install_sync(mdkPlayer*, mdkSyncCallback callback, int interval) {
  sync_callback = callback;
  sync_interval = interval;
}
int64_t position(mdkPlayer*) { return audio_position; }
void expect_clock(double expected) {
  if (std::abs(sync_callback.cb(sync_callback.opaque) - expected) > 0.000001) {
    std::cerr << "Unexpected audio master clock\n";
    std::exit(1);
  }
}
}  // namespace

int main() {
  mdkPlayerAPI video{}, audio{};
  video.onSync = install_sync;
  audio.position = position;
  if (bili_fvp_audio_clock(0, 0) != nullptr) return 1;
  auto* clock = bili_fvp_audio_clock(reinterpret_cast<uintptr_t>(&video),
                                    reinterpret_cast<uintptr_t>(&audio));
  if (clock == nullptr || sync_interval != 10) return 1;
  // Paused preparation never consumes a stale native output clock.
  bili_fvp_audio_clock_hold(clock, 400000);
  audio_position = 0;
  expect_clock(400);
  bili_fvp_audio_clock_play(clock);
  expect_clock(400);
  audio_position = 400020;
  expect_clock(400.020);
  audio_position = 402000;
  expect_clock(402);
  audio_position = 0;
  expect_clock(402);
  // A stopped audio clock freezes video, independently of Dart sampling.
  expect_clock(402);
  bili_fvp_audio_clock_hold(clock, 80000);
  expect_clock(80);
  bili_fvp_audio_clock_play(clock);
  expect_clock(80);
  audio_position = 80015;
  expect_clock(80.015);
  // A small backwards seek must reset the epoch as well.
  bili_fvp_audio_clock_hold(clock, 79800);
  bili_fvp_audio_clock_play(clock);
  expect_clock(79.8);
  audio_position = 79820;
  expect_clock(79.820);
  bili_fvp_audio_clock_hold(clock, 79820);
  audio_position = 90000;
  expect_clock(79.820);
  // Precise direct-Surface targets can round to a timestamp beyond the frozen
  // audio anchor. MDK must render that paused frame to complete its seek; waiting
  // for the audio clock here would prevent either target from becoming ready.
  for (const auto target_ms : {59700, 71133, 2000}) {
    bili_fvp_audio_clock_hold(clock, target_ms);
    expect_clock(static_cast<double>(target_ms) / 1000);
    bili_fvp_audio_clock_seek(clock);
    expect_clock((std::numeric_limits<double>::max)());
    audio_position = target_ms + 33;
    expect_clock((std::numeric_limits<double>::max)());
    // A confirmed pair is held at its actual target before either pipe plays.
    bili_fvp_audio_clock_hold(clock, target_ms + 33);
    expect_clock(static_cast<double>(target_ms + 33) / 1000);
    audio_position = 90000;  // Old output still cannot escape the new epoch.
    bili_fvp_audio_clock_play(clock);
    expect_clock(static_cast<double>(target_ms + 33) / 1000);
    audio_position = target_ms + 50;
    expect_clock(static_cast<double>(target_ms + 50) / 1000);
  }
  // Cancellation/failure restores a paused anchor; the next seek can still
  // decode and confirm its own frame without inheriting that retired target.
  bili_fvp_audio_clock_seek(clock);
  bili_fvp_audio_clock_hold(clock, 2050);
  expect_clock(2.050);
  bili_fvp_audio_clock_seek(clock);
  expect_clock((std::numeric_limits<double>::max)());
  bili_fvp_audio_clock_hold(clock, 80000);
  expect_clock(80);
  // The owner destroys/joins video before releasing callback state.
  sync_callback = {};
  bili_fvp_audio_clock_release(clock);
  bili_fvp_audio_clock_release(nullptr);
  bili_fvp_audio_clock_hold(nullptr, 0);
  bili_fvp_audio_clock_seek(nullptr);
  bili_fvp_audio_clock_play(nullptr);
  std::cout << "Audio clock preparation, seek epochs, pause and resume passed\n";
}
