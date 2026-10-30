#include "flutter_window.h"

#include <optional>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "window_size_constraints.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  // System.exitApplication can end the message loop without WM_DESTROY. Run
  // derived cleanup before member destruction can reenter window messages.
  Destroy();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  system_media_channel_ = std::make_unique<SystemMediaControlsChannel>(
      flutter_controller_->engine()->messenger(), GetHandle());
  system_fonts_channel_ =
      RegisterSystemFonts(flutter_controller_->engine()->messenger());
  image_export_channel_ = std::make_unique<ImageExportChannel>(
      flutter_controller_->engine()->messenger(),
      flutter_controller_->view()->GetNativeWindow());
  const auto text_input_registrar =
      flutter_controller_->engine()->GetRegistrarForPlugin("BiliSailTextInput");
  const auto resolve_view = [text_input_registrar](int64_t view_id) -> HWND {
    const auto view = FlutterDesktopPluginRegistrarGetViewById(
        text_input_registrar, view_id);
    return view ? FlutterDesktopViewGetHWND(view) : nullptr;
  };
  text_input_channel_ = std::make_unique<TextInputChannel>(
      flutter_controller_->engine()->messenger(),
      flutter_controller_->view()->GetNativeWindow(),
      resolve_view);
  desktop_window_channel_ = std::make_unique<DesktopWindowChannel>(
      flutter_controller_->engine()->messenger(), resolve_view);
  application_exit_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "bilisail/application_exit",
          &flutter::StandardMethodCodec::GetInstance());
  application_exit_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "setCloseHandler") {
          result->NotImplemented();
          return;
        }
        const auto* enabled = call.arguments()
                                  ? std::get_if<bool>(call.arguments())
                                  : nullptr;
        if (!enabled) {
          result->Error("invalid_argument", "Expected a close-handler flag.");
          return;
        }
        intercept_main_window_close_ = *enabled;
        result->Success();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  intercept_main_window_close_ = false;
  application_exit_channel_.reset();
  system_media_channel_.reset();
  image_export_channel_.reset();
  desktop_window_channel_.reset();
  text_input_channel_.reset();
  system_fonts_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == SystemMediaControlsChannel::kCommandMessage && system_media_channel_) {
    system_media_channel_->DispatchCommands();
    return 0;
  }
  // This runner window owns the engine. Do not use a global plugin delegate:
  // SDK-managed playback HWNDs share those delegates and must close separately.
  if (message == WM_CLOSE && intercept_main_window_close_ &&
      application_exit_channel_) {
    application_exit_channel_->InvokeMethod("closeRequested", nullptr);
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      if (message == WM_GETMINMAXINFO && lparam != 0) {
        // The plugin scales its logical minimum to physical pixels first.
        // Clamp against this monitor's current work area, including taskbars.
        window_layout::ConstrainMinimumTrackSizeToMonitor(
            hwnd, *reinterpret_cast<MINMAXINFO*>(lparam));
      }
      return *result;
    }
  }

  switch (message) {
    case WM_SYSCOMMAND:
      if ((wparam & 0xFFF0) == SC_KEYMENU) {
        // TODO(flutter/flutter#177822): Remove once the pinned Flutter SDK
        // delivers Alt and the following key without activating the native menu.
        // https://github.com/flutter/flutter/issues/177822#issuecomment-3477313405
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
