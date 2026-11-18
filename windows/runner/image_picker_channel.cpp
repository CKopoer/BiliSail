#include "image_picker_channel.h"

#include <commctrl.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "image_picker.h"

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
using Result = flutter::MethodResult<EncodableValue>;
}  // namespace

class ImagePickerChannel::Impl final {
 public:
  Impl(flutter::BinaryMessenger* messenger, ViewResolver resolve_view,
       image_picker::Request::Factory factory)
      : channel_(messenger, "bilisail/image_picker",
                 &flutter::StandardMethodCodec::GetInstance()),
        resolve_view_(std::move(resolve_view)),
        factory_(std::move(factory)) {
    control_ = CreateWindowExW(0, L"STATIC", L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                               nullptr, GetModuleHandleW(nullptr), nullptr);
    if (control_ && !SetWindowSubclass(control_, ControlProc, 1,
                                       reinterpret_cast<DWORD_PTR>(this))) {
      DestroyWindow(control_);
      control_ = nullptr;
    }
    channel_.SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() != "pickImages") {
        result->NotImplemented();
        return;
      }
      const auto* args = call.arguments()
                             ? std::get_if<EncodableMap>(call.arguments())
                             : nullptr;
      const auto value = args ? args->find(EncodableValue("viewId"))
                              : EncodableMap::const_iterator{};
      const auto* wide = args && value != args->end()
                             ? std::get_if<int64_t>(&value->second)
                             : nullptr;
      const auto* narrow_id = args && value != args->end()
                                  ? std::get_if<int32_t>(&value->second)
                                  : nullptr;
      if (!wide && !narrow_id) {
        result->Error("invalid_argument", "Expected an image picker view ID.");
        return;
      }
      if (request_) {
        result->Error("picker_busy", "An image picker is already open.");
        return;
      }
      view_id_ = wide ? *wide : *narrow_id;
      owner_ = image_picker::ResolveOwner(resolve_view_, view_id_);
      if (!owner_) {
        result->Error("window_unavailable", "The image picker view is closed.");
        return;
      }
      if (!control_ || !SetTimer(control_, 1, 30, nullptr)) {
        result->Error("picker_failed", "Could not schedule image selection.");
        return;
      }
      try {
        request_ = std::make_unique<image_picker::Request>(owner_, factory_);
      } catch (...) {
        KillTimer(control_, 1);
        result->Error("picker_failed", "Could not start image selection.");
        return;
      }
      pending_ = std::move(result);
    });
  }

  ~Impl() {
    channel_.SetMethodCallHandler(nullptr);
    // Stop platform callbacks before joining the STA. Keep the engine alive
    // until the dialog and all of its COM resources have been released.
    if (control_) {
      KillTimer(control_, 1);
      RemoveWindowSubclass(control_, ControlProc, 1);
      DestroyWindow(control_);
    }
    request_.reset();
    if (pending_) pending_->Error("window_unavailable", "The app is closing.");
  }

 private:
  void Poll() {
    if (!request_) return;
    const bool current =
        owner_ && owner_ == image_picker::ResolveOwner(resolve_view_, view_id_);
    if (!current) request_->Cancel();
    if (!request_->finished()) return;
    const auto selection = request_->selection();
    KillTimer(control_, 1);
    request_.reset();
    auto result = std::move(pending_);
    if (!current) {
      result->Error("window_unavailable", "The image picker view is closed.");
    } else if (selection.status == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
      result->Success(EncodableValue(flutter::EncodableList{}));
    } else if (selection.status != S_OK) {
      result->Error("picker_failed", "Could not select images.",
                    EncodableValue(static_cast<int32_t>(selection.status)));
    } else {
      flutter::EncodableList paths;
      for (const auto& path : selection.paths) paths.emplace_back(path);
      result->Success(EncodableValue(paths));
    }
  }

  static LRESULT CALLBACK ControlProc(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam, UINT_PTR,
                                      DWORD_PTR reference) {
    if (message == WM_TIMER && wparam == 1) {
      reinterpret_cast<Impl*>(reference)->Poll();
      return 0;
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }

  flutter::MethodChannel<EncodableValue> channel_;
  ViewResolver resolve_view_;
  image_picker::Request::Factory factory_;
  HWND control_ = nullptr;
  HWND owner_ = nullptr;
  int64_t view_id_ = -1;
  std::unique_ptr<image_picker::Request> request_;
  std::unique_ptr<Result> pending_;
};

ImagePickerChannel::ImagePickerChannel(flutter::BinaryMessenger* messenger,
                                       ViewResolver resolve_view,
                                       image_picker::Request::Factory factory)
    : impl_(std::make_unique<Impl>(messenger, std::move(resolve_view),
                                   std::move(factory))) {}
ImagePickerChannel::~ImagePickerChannel() = default;
