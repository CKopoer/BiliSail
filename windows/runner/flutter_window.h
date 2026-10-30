#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"
#include "system_fonts.h"
#include "image_export.h"
#include "text_input.h"
#include "desktop_window.h"
#include "system_media_controls.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      system_fonts_channel_;
  std::unique_ptr<TextInputChannel> text_input_channel_;
  std::unique_ptr<ImageExportChannel> image_export_channel_;
  std::unique_ptr<DesktopWindowChannel> desktop_window_channel_;
  std::unique_ptr<SystemMediaControlsChannel> system_media_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      application_exit_channel_;
  bool intercept_main_window_close_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
