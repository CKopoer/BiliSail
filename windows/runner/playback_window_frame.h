#ifndef RUNNER_PLAYBACK_WINDOW_FRAME_H_
#define RUNNER_PLAYBACK_WINDOW_FRAME_H_

#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <dwmapi.h>

namespace playback_window {

// Flutter paints the caption up to the window's top edge. Keep native styles
// and supply resize hit tests for the top band now covered by the client area.
class PlaybackWindowFrame {
 public:
  explicit PlaybackWindowFrame(HWND window) : window_(window) {
    attached_ = SetWindowSubclass(window_, WindowProc, SubclassId(), 0) != FALSE;
    if (attached_) Refresh();
  }
  ~PlaybackWindowFrame() {
    if (!attached_ || !IsWindow(window_)) return;
    // The callback carries no object pointer, so even a failed removal is safe.
    if (RemoveWindowSubclass(window_, WindowProc, SubclassId())) Refresh();
  }
  PlaybackWindowFrame(const PlaybackWindowFrame&) = delete;
  PlaybackWindowFrame& operator=(const PlaybackWindowFrame&) = delete;

  bool ready() const { return attached_; }

  void SetTheme(bool dark, COLORREF caption_color) const {
    const BOOL enable_dark_mode = dark ? TRUE : FALSE;
    // SDK-managed secondary HWNDs do not pass through Win32Window::UpdateTheme.
    // These numeric attributes also compile with the Windows 10 SDK. Caption
    // color is optional on older Windows; immersive dark mode remains usable.
    constexpr DWORD kImmersiveDarkMode = 20;
    constexpr DWORD kCaptionColor = 35;
    DwmSetWindowAttribute(window_, kImmersiveDarkMode, &enable_dark_mode,
                          sizeof(enable_dark_mode));
    DwmSetWindowAttribute(window_, kCaptionColor, &caption_color,
                          sizeof(caption_color));
    RedrawWindow(window_, nullptr, nullptr, RDW_INVALIDATE | RDW_FRAME);
  }

 private:
  static UINT_PTR SubclassId() {
    return reinterpret_cast<UINT_PTR>(&WindowProc);
  }

  void Refresh() const {
    SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER |
                     SWP_FRAMECHANGED);
  }

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR subclass_id,
                                     DWORD_PTR) {
    if (message == WM_NCCALCSIZE) {
      auto* const rect = wparam
          ? &reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam)->rgrc[0]
          : reinterpret_cast<RECT*>(lparam);
      const LONG top = rect->top;
      // The SDK host forwards messages to shared plugin delegates. In
      // window_manager, hidden-caption insets use the main window's zoom state,
      // which can expand an ordinary playback client beyond its own frame.
      // This subclass owns the playback frame: obtain system insets directly
      // instead of applying another window's custom-caption policy first.
      const LRESULT result = DefWindowProcW(window, message, wparam, lparam);
      // Fullscreen removes the caption and resize frame; its system client
      // already fills the window and must also bypass the main-window policy.
      if ((GetWindowLongPtr(window, GWL_STYLE) & WS_CAPTION) != WS_CAPTION) {
        return result;
      }
      // A maximized HWND extends its resize border beyond the work area. Keep
      // that inset only when zoomed so the Flutter caption is not clipped.
      const UINT dpi = GetDpiForWindow(window);
      const int inset = IsZoomed(window)
          ? GetSystemMetricsForDpi(SM_CYFRAME, dpi) +
                GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi)
          : 0;
      rect->top = top + inset;
      return result;
    }
    if (message == WM_NCHITTEST && !IsZoomed(window) &&
        (GetWindowLongPtr(window, GWL_STYLE) & WS_OVERLAPPEDWINDOW) ==
            WS_OVERLAPPEDWINDOW) {
      RECT bounds{};
      if (GetWindowRect(window, &bounds)) {
        const UINT dpi = GetDpiForWindow(window);
        const int border_y = GetSystemMetricsForDpi(SM_CYFRAME, dpi) +
            GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
        const int x = GET_X_LPARAM(lparam);
        const int y = GET_Y_LPARAM(lparam);
        if (x >= bounds.left && x < bounds.right &&
            y >= bounds.top && y < bounds.top + border_y) {
          const int border_x = GetSystemMetricsForDpi(SM_CXFRAME, dpi) +
              GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
          if (x < bounds.left + border_x) return HTTOPLEFT;
          if (x >= bounds.right - border_x) return HTTOPRIGHT;
          return HTTOP;
        }
      }
    }
    if (message == WM_NCDESTROY) {
      RemoveWindowSubclass(window, WindowProc, subclass_id);
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }

  HWND window_;  // Borrowed from the Flutter window controller.
  bool attached_ = false;
};

}  // namespace playback_window

#endif  // RUNNER_PLAYBACK_WINDOW_FRAME_H_
