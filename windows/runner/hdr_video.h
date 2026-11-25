#ifndef RUNNER_HDR_VIDEO_H_
#define RUNNER_HDR_VIDEO_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <functional>
#include <memory>

class HdrVideoChannel {
 public:
  HdrVideoChannel(flutter::BinaryMessenger* messenger,
                  std::function<HWND(int64_t)> resolve_view);
  ~HdrVideoChannel();

 private:
  struct State;
  std::unique_ptr<State> state_;
};

#endif  // RUNNER_HDR_VIDEO_H_
