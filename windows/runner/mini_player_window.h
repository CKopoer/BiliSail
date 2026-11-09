#ifndef RUNNER_MINI_PLAYER_WINDOW_H_
#define RUNNER_MINI_PLAYER_WINDOW_H_

#include <windows.h>
#include <commctrl.h>

#include "playback_window_geometry_win32.h"

namespace playback_window {

// The original HWND and Flutter view keep their player and input ownership.
// A separate role prevents compact bounds from replacing the normal window.
class MiniPlayerWindow {
 public:
  explicit MiniPlayerWindow(HWND window,
      WindowGeometryStore store = WindowGeometryStore(L"miniPlayer"))
      : window_(window), store_(std::move(store)) {
    store_.Load(geometry_);
    geometry_.Begin(1, 1);
  }
  ~MiniPlayerWindow() { Retire(); }
  MiniPlayerWindow(const MiniPlayerWindow&) = delete;
  MiniPlayerWindow& operator=(const MiniPlayerWindow&) = delete;

  bool Enter() {
    if (active_) return true;
    placement_.length = sizeof(placement_);
    if (!GetWindowPlacement(window_, &placement_)) return false;
    style_ = GetWindowLongPtr(window_, GWL_STYLE);
    topmost_ = (GetWindowLongPtr(window_, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
    if (!SetPropW(window_, L"BiliSail.MiniPlayer", reinterpret_cast<HANDLE>(1))) return false;
    active_ = true;
    SetPropW(window_, L"BiliSail.MiniPlayer.Store", &store_);
    if (!SetWindowSubclass(window_, WindowProc, SubclassId(), 0)) {
      RemovePropW(window_, L"BiliSail.MiniPlayer");
      RemovePropW(window_, L"BiliSail.MiniPlayer.Store");
      active_ = false;
      return false;
    }
    ShowWindow(window_, SW_RESTORE);
    SetWindowLongPtr(window_, GWL_STYLE, style_ & ~(WS_CAPTION | WS_MAXIMIZE));
    if (!geometry_.normal()) {
      MONITORINFO monitor{};
      monitor.cbSize = sizeof(monitor);
      if (GetMonitorInfo(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST), &monitor)) {
        const double scale = GetDpiForWindow(window_) / 96.0;
        const double width = 400 * scale;
        const double height = 225 * scale;
        geometry_.Load({monitor.rcWork.right - width - 20 * scale,
                        monitor.rcWork.top + 20 * scale, width, height}, false);
      }
    }
    const bool restored = RestoreNormalBounds(window_, geometry_);
    const bool pinned = SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED) != FALSE;
    if (!restored || !pinned) { Restore(); return false; }
    return true;
  }

  void Save() {
    if (!active_ || !IsWindow(window_) || IsIconic(window_)) return;
    SaveWindow(window_);
  }

  static void SaveWindow(HWND window) {
    RECT rect{};
    if (GetWindowRect(window, &rect)) {
      GeometrySession geometry;
      geometry.Load(RectBounds(rect), false);
      const auto* store = static_cast<WindowGeometryStore*>(GetPropW(window, L"BiliSail.MiniPlayer.Store"));
      if (store) store->Save(geometry);
    }
  }

  void Restore() {
    if (!active_) return;
    Save();
    active_ = false;
    if (!IsWindow(window_)) return;
    RemoveWindowSubclass(window_, WindowProc, SubclassId());
    RemovePropW(window_, L"BiliSail.MiniPlayer.Store");
    // Zoom/minimize bits are owned by ShowWindow. Reinstating WS_MAXIMIZE
    // before SetWindowPlacement makes SDK/plugin hosts treat the compact
    // rectangle as an already-maximized window and skip its real expansion.
    SetWindowLongPtr(window_, GWL_STYLE, style_ & ~(WS_MAXIMIZE | WS_MINIMIZE));
    SetWindowPlacement(window_, &placement_);
    if (placement_.showCmd == SW_SHOWMAXIMIZED) ShowWindow(window_, SW_MAXIMIZE);
    SetWindowPos(window_, topmost_ ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    RemovePropW(window_, L"BiliSail.MiniPlayer");
  }

  // A closing view must never resize/zoom back to its ordinary presentation.
  void Retire() {
    if (!active_) return;
    Save();
    active_ = false;
    if (!IsWindow(window_)) return;
    RemoveWindowSubclass(window_, WindowProc, SubclassId());
    RemovePropW(window_, L"BiliSail.MiniPlayer.Store");
    RemovePropW(window_, L"BiliSail.MiniPlayer");
  }

 private:
  static UINT_PTR SubclassId() { return reinterpret_cast<UINT_PTR>(&WindowProc); }
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                    LPARAM lparam, UINT_PTR id, DWORD_PTR) {
    const LRESULT result = DefSubclassProc(window, message, wparam, lparam);
    if (message == WM_GETMINMAXINFO) {
      auto& limits = *reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = GetDpiForWindow(window);
      limits.ptMinTrackSize = {MulDiv(240, dpi, 96), MulDiv(135, dpi, 96)};
    } else if (message == WM_EXITSIZEMOVE || message == WM_CLOSE) {
      if (!IsIconic(window)) SaveWindow(window);
    } else if (message == WM_NCDESTROY) {
      RemoveWindowSubclass(window, WindowProc, id);
    }
    return result;
  }

  HWND window_;
  WINDOWPLACEMENT placement_{};
  LONG_PTR style_ = 0;
  bool topmost_ = false;
  bool active_ = false;
  GeometrySession geometry_;
  WindowGeometryStore store_;
};

}  // namespace playback_window
#endif  // RUNNER_MINI_PLAYER_WINDOW_H_
