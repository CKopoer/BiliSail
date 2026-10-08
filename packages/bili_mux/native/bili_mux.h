#ifndef BILISAIL_MUX_H
#define BILISAIL_MUX_H

#include <stdint.h>

#ifdef _WIN32
#define BILI_MUX_EXPORT __declspec(dllexport)
#else
#define BILI_MUX_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct bili_mux_job bili_mux_job;

// ABI 1: opaque jobs, UTF-8 local file paths. No FFmpeg types cross this ABI.
BILI_MUX_EXPORT int32_t bili_mux_abi(void);
BILI_MUX_EXPORT bili_mux_job* bili_mux_create(const char* video,
                                             const char* audio,
                                             const char* output);
// Run exactly once on a worker. 0 success, 1 cancelled, 2 input/codec,
// 3 output I/O, 4 output verification, 5 internal failure, 6 deadline.
BILI_MUX_EXPORT int32_t bili_mux_run(bili_mux_job* job);
// Thread-safe while run is active; progress is 0..10000.
BILI_MUX_EXPORT void bili_mux_cancel(bili_mux_job* job);
BILI_MUX_EXPORT int32_t bili_mux_progress(const bili_mux_job* job);
// Destroy only after run returns and all polling/cancellation has stopped.
BILI_MUX_EXPORT void bili_mux_destroy(bili_mux_job* job);

#ifdef __cplusplus
}
#endif
#endif
