// Copyright (c) 2026 BiliSail contributors. All rights reserved.
#pragma once
#include <stdint.h>

#if defined(_WIN32)
#define BILI_AUDIO_API __declspec(dllexport)
#else
#define BILI_AUDIO_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// The caller owns this state until native player destruction has completed.
BILI_AUDIO_API void* bili_fvp_audio_attach(uintptr_t player_api);
BILI_AUDIO_API uint64_t bili_fvp_audio_frames(void* activity);
BILI_AUDIO_API void* bili_fvp_audio_clock(uintptr_t video_api, uintptr_t audio_api);
// While paused seek decodes its target, do not wait on the frozen audio clock.
// End this state with hold() only after both target callbacks have completed.
BILI_AUDIO_API void bili_fvp_audio_clock_seek(void* clock);
BILI_AUDIO_API void bili_fvp_audio_clock_hold(void* clock, int64_t position_ms);
BILI_AUDIO_API void bili_fvp_audio_clock_play(void* clock);
BILI_AUDIO_API void bili_fvp_audio_clock_release(void* clock);
BILI_AUDIO_API void bili_fvp_audio_release(void* activity);

#ifdef __cplusplus
}
#endif
