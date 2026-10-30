#ifndef RUNNER_SYSTEM_MEDIA_CONTROLS_H_
#define RUNNER_SYSTEM_MEDIA_CONTROLS_H_

#include <windows.h>
#include <flutter/binary_messenger.h>
#include <memory>

// WinRT callbacks only enqueue bounded commands. Flutter channels are invoked
// by the runner's UI thread after receiving this private window message.
class SystemMediaControlsChannel {
 public:
  static constexpr UINT kCommandMessage = WM_APP + 0x426;
  SystemMediaControlsChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~SystemMediaControlsChannel();
  SystemMediaControlsChannel(const SystemMediaControlsChannel&) = delete;
  SystemMediaControlsChannel& operator=(const SystemMediaControlsChannel&) = delete;
  SystemMediaControlsChannel(SystemMediaControlsChannel&&) = delete;
  SystemMediaControlsChannel& operator=(SystemMediaControlsChannel&&) = delete;
  void DispatchCommands();

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif
