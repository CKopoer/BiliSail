#ifndef RUNNER_APP_ICON_H_
#define RUNNER_APP_ICON_H_

#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <map>
#include <memory>
#include <tuple>
#include <type_traits>

class AppIconChannel {
 public:
  explicit AppIconChannel(flutter::BinaryMessenger* messenger);
  ~AppIconChannel();
  AppIconChannel(const AppIconChannel&) = delete;
  AppIconChannel& operator=(const AppIconChannel&) = delete;
  AppIconChannel(AppIconChannel&&) = delete;
  AppIconChannel& operator=(AppIconChannel&&) = delete;

  void ApplyTo(HWND window);

 private:
  struct IconDeleter {
    void operator()(HICON icon) const { DestroyIcon(icon); }
  };
  using Icon = std::unique_ptr<std::remove_pointer_t<HICON>, IconDeleter>;
  HICON Load(int resource, int width, int height);

  flutter::MethodChannel<flutter::EncodableValue> channel_;
  std::map<std::tuple<int, int, int>, Icon> icons_;
  int resource_id_ = 0;
};

#endif  // RUNNER_APP_ICON_H_
