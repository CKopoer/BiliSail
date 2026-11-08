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
  // The owner destroys/joins video before releasing callback state.
  sync_callback = {};
  bili_fvp_audio_clock_release(clock);
  bili_fvp_audio_clock_release(nullptr);
  bili_fvp_audio_clock_hold(nullptr, 0);
  bili_fvp_audio_clock_play(nullptr);
  std::cout << "Audio clock preparation, seek epochs, pause and resume passed\n";
}
