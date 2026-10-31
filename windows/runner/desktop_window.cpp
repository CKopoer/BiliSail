#include "desktop_window.h"

#include <commctrl.h>
#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

namespace {
int64_t ReadInteger(const flutter::EncodableMap& arguments, const char* key) {
  const auto value = arguments.find(flutter::EncodableValue(key));
  if (value == arguments.end()) return -1;
  if (const auto* id = std::get_if<int64_t>(&value->second)) return *id;
  if (const auto* id = std::get_if<int32_t>(&value->second)) return *id;
  return -1;
}

double SegmentDistance(double x, double y, double ax, double ay, double bx,
                       double by) {
  const double dx = bx - ax;
  const double dy = by - ay;
  const double t = std::clamp(((x - ax) * dx + (y - ay) * dy) /
                                (dx * dx + dy * dy),
                            0.0, 1.0);
  return std::hypot(x - ax - t * dx, y - ay - t * dy);
}

HICON BackIcon(HWND window, bool enabled) {
  const UINT dpi = GetDpiForWindow(window);
  const int size = GetSystemMetricsForDpi(SM_CXSMICON, dpi);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = size;
  info.bmiHeader.biHeight = -size;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixels = nullptr;
  const HBITMAP color = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &pixels,
                                        nullptr, 0);
  if (!color) return nullptr;
  BOOL dark = FALSE;
  DwmGetWindowAttribute(window, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &dark,
                       sizeof(dark));
  const COLORREF foreground = !enabled ? GetSysColor(COLOR_GRAYTEXT)
                                      : dark ? RGB(255, 255, 255)
                                             : GetSysColor(COLOR_CAPTIONTEXT);
  auto* const rgba = static_cast<uint32_t*>(pixels);
  for (int y = 0; y < size; ++y) {
    for (int x = 0; x < size; ++x) {
      const double px = (x + 0.5) / size;
      const double py = (y + 0.5) / size;
      const double distance = std::min(
          {SegmentDistance(px, py, .62, .23, .34, .5),
           SegmentDistance(px, py, .34, .5, .62, .77),
           SegmentDistance(px, py, .34, .5, .84, .5)});
      const auto alpha = static_cast<uint32_t>(
          std::clamp((.055 - distance) * size + .5, 0.0, 1.0) * 255);
      rgba[y * size + x] = (alpha << 24) |
                          ((GetRValue(foreground) * alpha / 255) << 16) |
                          ((GetGValue(foreground) * alpha / 255) << 8) |
                          (GetBValue(foreground) * alpha / 255);
    }
  }
  const std::vector<uint8_t> mask_bits(((size + 15) / 16) * 2 * size, 0);
  const HBITMAP mask = CreateBitmap(size, size, 1, 1, mask_bits.data());
  ICONINFO icon_info{};
  icon_info.fIcon = TRUE;
  icon_info.hbmColor = color;
  icon_info.hbmMask = mask;
  const HICON icon = mask ? CreateIconIndirect(&icon_info) : nullptr;
  if (mask) DeleteObject(mask);
  DeleteObject(color);
  return icon;
}
}  // namespace

// Use the native caption's complete icon cell. Caption buttons, dragging,
// double-click zoom and Alt+Space retain their standard non-client handling.
class CaptionBackButton {
 public:
  CaptionBackButton(HWND window, std::function<void()> on_back)
      : window_(window), on_back_(std::move(on_back)) {
    original_icon_ = reinterpret_cast<HICON>(SendMessage(window_, WM_GETICON,
                                                        ICON_SMALL, 0));
    attached_ = SetWindowSubclass(window_, WindowProc,
                                 reinterpret_cast<UINT_PTR>(this),
                                 reinterpret_cast<DWORD_PTR>(this)) != FALSE;
    if (attached_ && !UpdateIcon()) Detach();
  }
  ~CaptionBackButton() {
    Detach();
    if (icon_) DestroyIcon(icon_);
  }
  CaptionBackButton(const CaptionBackButton&) = delete;
  CaptionBackButton& operator=(const CaptionBackButton&) = delete;

  bool IsReady() const { return attached_ && icon_ != nullptr; }

  bool SetEnabled(bool enabled) {
    if (enabled_ == enabled) return IsReady();
    enabled_ = enabled;
    return UpdateIcon();
  }

  bool Detach() {
    if (window_ && IsWindow(window_)) {
      if (attached_ && !RemoveWindowSubclass(window_, WindowProc,
                                             reinterpret_cast<UINT_PTR>(this))) {
        DWORD_PTR reference = 0;
        if (GetWindowSubclass(window_, WindowProc,
                               reinterpret_cast<UINT_PTR>(this), &reference)) {
          return false;
        }
      }
      attached_ = false;
      SendMessage(window_, WM_SETICON, ICON_SMALL,
                   reinterpret_cast<LPARAM>(original_icon_));
    }
    window_ = nullptr;
    return true;
  }

  void AbandonUntilWindowDestroyed() {
    on_back_ = {};
    orphaned_ = true;
  }

 private:
  bool UpdateIcon() {
    const HICON replacement = BackIcon(window_, enabled_);
    if (!replacement) return false;
    const HICON previous = icon_;
    icon_ = replacement;
    SendMessage(window_, WM_SETICON, ICON_SMALL,
                 reinterpret_cast<LPARAM>(replacement));
    if (previous) DestroyIcon(previous);
    return true;
  }

  bool Contains(POINT point) const {
    RECT bounds{};
    GetWindowRect(window_, &bounds);
    const UINT dpi = GetDpiForWindow(window_);
    const int border = IsZoomed(window_)
                           ? 0
                           : GetSystemMetricsForDpi(SM_CXFRAME, dpi) +
                                 GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
    const int height = GetSystemMetricsForDpi(SM_CYCAPTION, dpi);
    RECT cell{bounds.left + border, bounds.top + border,
              bounds.left + border + std::max(height,
                  GetSystemMetricsForDpi(SM_CXSIZE, dpi)),
              bounds.top + border + height};
    return PtInRect(&cell, point) != FALSE;
  }

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR subclass_id,
                                     DWORD_PTR reference) {
    auto* const self = reinterpret_cast<CaptionBackButton*>(reference);
    if (message == WM_SETICON && wparam == ICON_SMALL && self->attached_ &&
        self->icon_ && reinterpret_cast<HICON>(lparam) != self->icon_) {
      // Keep the Back caption visible while updating the icon restored on detach.
      const HICON previous = self->original_icon_;
      self->original_icon_ = reinterpret_cast<HICON>(lparam);
      return reinterpret_cast<LRESULT>(previous);
    }
    if (message == WM_NCHITTEST) {
      const LRESULT hit = DefSubclassProc(window, message, wparam, lparam);
      if ((hit == HTCAPTION || hit == HTSYSMENU) &&
          self->Contains(POINT{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)})) {
        return HTSYSMENU;
      }
      return hit;
    }
    if ((message == WM_NCLBUTTONDOWN || message == WM_NCLBUTTONDBLCLK ||
         message == WM_NCLBUTTONUP) && wparam == HTSYSMENU) {
      if (message == WM_NCLBUTTONDOWN) self->suppress_up_ = false;
      if (message == WM_NCLBUTTONDBLCLK) self->suppress_up_ = true;
      if (message == WM_NCLBUTTONUP) {
        if (self->suppress_up_) {
          self->suppress_up_ = false;
        } else if (self->enabled_ && self->on_back_) {
          self->on_back_();
        }
      }
      return 0;
    }
    if (message == WM_NCDESTROY) {
      RemoveWindowSubclass(window, WindowProc, subclass_id);
      self->window_ = nullptr;
      self->attached_ = false;
      const LRESULT result = DefSubclassProc(window, message, wparam, lparam);
      if (self->orphaned_) delete self;
      return result;
    } else if (message == WM_DPICHANGED || message == WM_THEMECHANGED ||
               message == WM_SYSCOLORCHANGE) {
      const LRESULT result = DefSubclassProc(window, message, wparam, lparam);
      self->UpdateIcon();
      return result;
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }

  HWND window_;
  std::function<void()> on_back_;
  HICON original_icon_ = nullptr;  // Borrowed from the original native caption.
  HICON icon_ = nullptr;
  bool enabled_ = true;
  bool suppress_up_ = false;
  bool attached_ = false;
  bool orphaned_ = false;
};

DesktopWindowChannel::DesktopWindowChannel(flutter::BinaryMessenger* messenger,
                                         ViewResolver resolve_view,
                                         std::function<void(HWND)> apply_icon)
    : channel_(messenger, "bilisail/desktop_window",
               &flutter::StandardMethodCodec::GetInstance()),
      resolve_view_(std::move(resolve_view)),
      apply_icon_(std::move(apply_icon)) {
  channel_.SetMethodCallHandler(
      [this](const auto& call, auto result) {
        const auto* arguments = call.arguments()
                                    ? std::get_if<flutter::EncodableMap>(
                                          call.arguments())
                                    : nullptr;
        const int64_t id = arguments ? ReadInteger(*arguments, "viewId") : -1;
        if (id < 0) {
          result->Error("invalid_argument", "Expected a view ID.");
          return;
        }
        const bool geometry_call = call.method_name() == "restoreGeometry" ||
            call.method_name() == "captureGeometry" ||
            call.method_name() == "saveGeometry" ||
            call.method_name() == "retireGeometry";
        const int64_t owner = geometry_call ? ReadInteger(*arguments, "owner") : -1;
        if (geometry_call && owner <= 0) {
          result->Error("invalid_argument", "Expected a geometry owner.");
          return;
        }
        if (call.method_name() == "retireGeometry") {
          if (geometry_.Owns(id, owner)) {
            geometry_.Retire(id, owner);
            if (frame_view_ == id) {
              playback_frame_.reset();
              frame_view_ = -1;
            }
          }
          result->Success();
          return;
        }
        if ((call.method_name() == "captureGeometry" ||
             call.method_name() == "saveGeometry") && !geometry_.Owns(id, owner)) {
          result->Success();
          return;
        }
        if (call.method_name() == "removeBackButton") {
          const auto caption = captions_.find(id);
          if (caption != captions_.end() && !caption->second->Detach()) {
            caption->second->SetEnabled(false);
            result->Error("caption_detach_failed", "Cannot detach the caption Back button.");
            return;
          }
          captions_.erase(id);
          result->Success();
          return;
        }
        const HWND view = resolve_view_(id);
        const HWND window = view ? GetAncestor(view, GA_ROOT) : nullptr;
        if (!window || !IsWindow(window)) {
          result->Error("window_unavailable", "Flutter view is unavailable.");
          return;
        }
        if (call.method_name() == "setPlaybackTitleBar") {
          apply_icon_(window);
          const auto dark_entry = arguments->find(flutter::EncodableValue("dark"));
          const auto* dark = dark_entry != arguments->end()
                                 ? std::get_if<bool>(&dark_entry->second)
                                 : nullptr;
          const auto color_entry = arguments->find(
              flutter::EncodableValue("backgroundColor"));
          const int64_t rgb = ReadInteger(*arguments, "backgroundColor");
          if (!dark || (color_entry != arguments->end() &&
                        (rgb < 0 || rgb > 0x00ffffff))) {
            result->Error("invalid_argument", "Expected playback theme colors.");
            return;
          }
          if (frame_view_ != id) {
            auto frame = std::make_unique<playback_window::PlaybackWindowFrame>(window);
            if (!frame->ready()) {
              result->Error("caption_unavailable", "Cannot configure the playback frame.");
              return;
            }
            playback_frame_ = std::move(frame);
            frame_view_ = id;
          }
          constexpr COLORREF kSystemCaptionColor = 0xffffffff;
          const COLORREF caption_color = color_entry == arguments->end()
              ? kSystemCaptionColor
              : RGB((rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff);
          playback_frame_->SetTheme(*dark, caption_color);
          result->Success();
        } else if (call.method_name() == "startDragging") {
          POINT cursor{};
          GetCursorPos(&cursor);
          ReleaseCapture();
          PostMessage(window, WM_NCLBUTTONDOWN, HTCAPTION,
                      MAKELPARAM(cursor.x, cursor.y));
          result->Success();
        } else if (call.method_name() == "toggleMaximized") {
          PostMessage(window, WM_SYSCOMMAND,
                      IsZoomed(window) ? SC_RESTORE : SC_MAXIMIZE, 0);
          result->Success();
        } else if (call.method_name() == "minimize") {
          PostMessage(window, WM_SYSCOMMAND, SC_MINIMIZE, 0);
          result->Success();
        } else if (call.method_name() == "restoreGeometry") {
          if (!geometry_.Restore(window, id, owner)) {
            result->Error("geometry_restore_failed", "Cannot restore playback bounds.");
            return;
          }
          if (const auto size = geometry_.InitialContentSize(window)) {
            result->Success(flutter::EncodableValue(flutter::EncodableList{
                flutter::EncodableValue(static_cast<double>(size->cx)),
                flutter::EncodableValue(static_cast<double>(size->cy))}));
          } else {
            result->Success();
          }
        } else if (call.method_name() == "captureGeometry" ||
                   call.method_name() == "saveGeometry") {
          std::optional<bool> maximized;
          const auto state = arguments->find(flutter::EncodableValue("maximized"));
          if (state != arguments->end()) {
            const auto* value = std::get_if<bool>(&state->second);
            if (!value) {
              result->Error("invalid_argument", "Expected a maximized state.");
              return;
            }
            maximized = *value;
          }
          const bool save = call.method_name() == "saveGeometry";
          const bool captured = save
              ? geometry_.SaveAndHide(window, id, owner, maximized)
              : geometry_.Capture(window, id, owner, maximized);
          if (save && frame_view_ == id) {
            playback_frame_.reset();
            frame_view_ = -1;
          }
          if (!captured) {
            result->Error("geometry_capture_failed", "Cannot read playback bounds.");
            return;
          }
          result->Success();
        } else if (call.method_name() == "activate") {
          // SW_RESTORE on a zoomed window discards the user's maximized state.
          playback_window::ActivateWindow(window, view);
          result->Success();
        } else if (call.method_name() == "setBackButton") {
          const auto enabled = arguments->find(flutter::EncodableValue("enabled"));
          const auto* value = enabled != arguments->end()
                                  ? std::get_if<bool>(&enabled->second)
                                  : nullptr;
          if (!value) {
            result->Error("invalid_argument", "Expected a Back enabled state.");
            return;
          }
          auto& caption = captions_[id];
          if (!caption) {
            caption = std::make_unique<CaptionBackButton>(window, [this, id] {
              channel_.InvokeMethod("back", std::make_unique<flutter::EncodableValue>(
                  flutter::EncodableMap{{flutter::EncodableValue("viewId"),
                                         flutter::EncodableValue(id)}}));
            });
          }
          if (!caption->IsReady() || !caption->SetEnabled(*value)) {
            if (!caption->Detach()) {
              caption->AbandonUntilWindowDestroyed();
              caption.release();
            }
            captions_.erase(id);
            result->Error("caption_unavailable", "Cannot install the caption Back button.");
            return;
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

DesktopWindowChannel::~DesktopWindowChannel() {
  channel_.SetMethodCallHandler(nullptr);
  for (auto& entry : captions_) {
    if (!entry.second->Detach()) {
      // A failed removal must not leave a callback pointing into this channel.
      // The live HWND retains this disabled context until WM_NCDESTROY.
      entry.second->AbandonUntilWindowDestroyed();
      entry.second.release();
    }
  }
  captions_.clear();
}
