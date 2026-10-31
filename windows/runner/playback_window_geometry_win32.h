#ifndef RUNNER_PLAYBACK_WINDOW_GEOMETRY_WIN32_H_
#define RUNNER_PLAYBACK_WINDOW_GEOMETRY_WIN32_H_

#include <windows.h>
#include <commctrl.h>

#include <cmath>
#include <memory>
#include <optional>

#include "playback_window_geometry.h"
#include "playback_window_first_show.h"
#include "window_geometry_store.h"

namespace playback_window {

inline Bounds RectBounds(const RECT& rect) {
  return {static_cast<double>(rect.left), static_cast<double>(rect.top),
          static_cast<double>(rect.right) - rect.left,
          static_cast<double>(rect.bottom) - rect.top};
}

inline bool CaptureNormalBounds(
    HWND window, int64_t view, int64_t owner, GeometrySession& session,
    std::optional<bool> last_maximized = std::nullopt) {
  // Fullscreen removes the native caption and may replace WINDOWPLACEMENT.
  // Dart captures immediately before entering fullscreen; never save its frame.
  if ((GetWindowLongPtr(window, GWL_STYLE) & WS_CAPTION) != WS_CAPTION ||
      (GetWindowLongPtr(window, GWL_STYLE) & WS_THICKFRAME) == 0) {
    return true;
  }
  RECT rect{};
  if (!IsIconic(window) && !IsZoomed(window)) {
    if (!GetWindowRect(window, &rect)) return false;
    session.Capture(view, owner, RectBounds(rect));
    return true;
  }
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!GetWindowPlacement(window, &placement)) return false;
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (!GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                      &monitor)) return false;
  const bool tool_window =
      (GetWindowLongPtr(window, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0;
  // WINDOWPLACEMENT uses workspace coordinates for ordinary top-level windows.
  // Convert once, including negative monitor origins and left/top taskbars.
  const bool maximized = IsIconic(window)
      ? last_maximized.value_or(session.maximized())
      : IsZoomed(window) != FALSE;
  session.Capture(view, owner, PlacementToScreen(
      RectBounds(placement.rcNormalPosition), RectBounds(monitor.rcMonitor),
      RectBounds(monitor.rcWork), tool_window), maximized);
  return true;
}

inline bool RestoreNormalBounds(HWND window, const GeometrySession& session) {
  if (!session.normal()) return true;  // First window keeps the SDK default.
  const auto saved = *session.normal();
  const RECT previous{static_cast<LONG>(std::lround(saved.left)),
                      static_cast<LONG>(std::lround(saved.top)),
                      static_cast<LONG>(std::lround(saved.left + saved.width)),
                      static_cast<LONG>(std::lround(saved.top + saved.height))};
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (!GetMonitorInfo(MonitorFromRect(&previous, MONITOR_DEFAULTTONEAREST),
                      &monitor)) return true;
  const auto fitted = FitToWorkArea(saved, RectBounds(monitor.rcWork));
  if (!fitted) return true;
  return SetWindowPos(window, nullptr,
                      static_cast<int>(std::lround(fitted->left)),
                      static_cast<int>(std::lround(fitted->top)),
                      static_cast<int>(std::lround(fitted->width)),
                      static_cast<int>(std::lround(fitted->height)),
                      SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER) != FALSE;
}

// The SDK's initial content sizing uses the system caption's insets. Our
// custom caption has a larger client area inside the same outer rectangle.
// Keep the prepared outer size until first show so the SDK cannot add that
// caption height a second time. All later user resizing passes through.
class InitialWindowSize {
 public:
  explicit InitialWindowSize(HWND window) : window_(window) {}
  ~InitialWindowSize() { Cancel(); }
  InitialWindowSize(const InitialWindowSize&) = delete;
  InitialWindowSize& operator=(const InitialWindowSize&) = delete;

  bool Prepare() {
    if (IsWindowVisible(window_)) return true;
    RECT bounds{};
    if (!GetWindowRect(window_, &bounds)) return false;
    const auto width = static_cast<DWORD>(bounds.right - bounds.left);
    const auto height = static_cast<DWORD>(bounds.bottom - bounds.top);
    static_assert(sizeof(DWORD_PTR) == 8, "Playback windows require Windows x64.");
    const DWORD_PTR size = (static_cast<DWORD_PTR>(width) << 32) | height;
    // Store dimensions by value; a nested close can destroy the owning session
    // while DefSubclassProc is on the stack, without leaving an object pointer.
    return SetWindowSubclass(window_, WindowProc, SubclassId(), size) != FALSE;
  }

 private:
  static UINT_PTR SubclassId() {
    return reinterpret_cast<UINT_PTR>(&WindowProc);
  }

  void Cancel() {
    DWORD_PTR size = 0;
    if (IsWindow(window_) &&
        GetWindowSubclass(window_, WindowProc, SubclassId(), &size) &&
        !RemoveWindowSubclass(window_, WindowProc, SubclassId())) {
      SetWindowSubclass(window_, WindowProc, SubclassId(), 0);
    }
  }

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR subclass_id,
                                     DWORD_PTR size) {
    if (message == WM_NCDESTROY) {
      RemoveWindowSubclass(window, WindowProc, subclass_id);
    } else if (message == WM_WINDOWPOSCHANGING && size != 0) {
      auto& position = *reinterpret_cast<WINDOWPOS*>(lparam);
      if (IsWindowVisible(window) || IsZoomed(window) || IsIconic(window) ||
          (position.flags & SWP_SHOWWINDOW) != 0 ||
          (GetWindowLongPtr(window, GWL_STYLE) & WS_CAPTION) != WS_CAPTION) {
        RemoveWindowSubclass(window, WindowProc, subclass_id);
      } else if ((position.flags & SWP_NOSIZE) == 0) {
        position.cx = static_cast<int>(size >> 32);
        position.cy = static_cast<int>(size & 0xffffffff);
      }
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }

  HWND window_;
};

// Flutter 3.47.6 HostWindow captures SW_SHOWNORMAL at creation and executes it
// after the first rendered frame. Maximizing during prepare would show a blank
// window early, then that SDK callback would unmaximize it. Consume only the
// first native show while it is still hidden, then show it maximized after the
// SDK's normal placement completes. Later user Restore commands pass through.
class InitialShowMaximizer {
 public:
  InitialShowMaximizer(HWND window, int64_t owner)
      : window_(window), transitions_(window, owner) {}
  ~InitialShowMaximizer() { Cancel(); }
  InitialShowMaximizer(const InitialShowMaximizer&) = delete;
  InitialShowMaximizer& operator=(const InitialShowMaximizer&) = delete;

  bool Prepare(bool maximized) {
    if (!maximized) return true;
    if (IsWindowVisible(window_)) {
      ShowWindow(window_, SW_MAXIMIZE);
      return true;
    }
    transitions_.Suppress();
    return SetWindowSubclass(window_, WindowProc, SubclassId(), kArmed) != FALSE;
  }

  bool pending() const {
    DWORD_PTR pending = 0;
    return IsWindow(window_) &&
           GetWindowSubclass(window_, WindowProc, SubclassId(), &pending) &&
           pending != 0;
  }

 private:
  static constexpr DWORD_PTR kArmed = 1;
  static constexpr DWORD_PTR kSuppressed = 2;
  static constexpr DWORD_PTR kCompleting = 3;

  static UINT_PTR SubclassId() {
    return reinterpret_cast<UINT_PTR>(&WindowProc);
  }

  void Cancel() {
    if (!IsWindow(window_)) return;
    if (!RemoveWindowSubclass(window_, WindowProc, SubclassId())) {
      // No callback references this object. If native removal fails, leave an
      // inert callback rather than carrying an old owner's restore forward.
      if (pending()) {
        SetWindowSubclass(window_, WindowProc, SubclassId(), 0);
      }
    }
  }

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR subclass_id,
                                     DWORD_PTR pending) {
    if (message == WM_NCDESTROY) {
      RemoveWindowSubclass(window, WindowProc, subclass_id);
    } else if (message == WM_WINDOWPOSCHANGING && pending == kArmed) {
      auto& position = *reinterpret_cast<WINDOWPOS*>(lparam);
      if ((position.flags & SWP_SHOWWINDOW) != 0 && !IsWindowVisible(window) &&
          !IsIconic(window) &&
          (GetWindowLongPtr(window, GWL_STYLE) & WS_CAPTION) == WS_CAPTION) {
        SetWindowSubclass(window, WindowProc, subclass_id, kSuppressed);
        position.flags &= ~SWP_SHOWWINDOW;
        // Ensure a completion message even when the SDK's normal rectangle is
        // unchanged and suppressing visibility would otherwise be a no-op.
        position.flags |= SWP_FRAMECHANGED;
      }
    } else if (message == WM_WINDOWPOSCHANGED &&
               (pending == kSuppressed ||
                (pending == kArmed &&
                 (reinterpret_cast<const WINDOWPOS*>(lparam)->flags &
                  SWP_SHOWWINDOW) != 0))) {
      // WM_SIZE can synchronously call Dart. Keep the lease armed for capture,
      // prevent nested completion, and check cancellation after forwarding.
      SetWindowSubclass(window, WindowProc, subclass_id, kCompleting);
      const LRESULT result = DefSubclassProc(window, message, wparam, lparam);
      DWORD_PTR current = 0;
      if (!IsWindow(window) ||
          !GetWindowSubclass(window, WindowProc, subclass_id, &current) ||
          current != kCompleting) return result;
      SetWindowSubclass(window, WindowProc, subclass_id, 0);
      RemoveWindowSubclass(window, WindowProc, subclass_id);
      if (!IsIconic(window) &&
          (GetWindowLongPtr(window, GWL_STYLE) & WS_CAPTION) == WS_CAPTION) {
        ShowWindow(window, SW_MAXIMIZE);
      }
      FirstShowTransitions::RestoreAfterFirstShow(window);
      return result;
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }

  HWND window_;
  FirstShowTransitions transitions_;
};

// Own both the saved geometry and the first-show hook under the same view lease.
// Channel replies and asynchronous close/retire operations can cross new opens.
class WindowGeometrySession {
 public:
  explicit WindowGeometrySession(WindowGeometryStore store = WindowGeometryStore())
      : store_(std::move(store)) { store_.Load(geometry_); }
  ~WindowGeometrySession() { DetachTracker(); }
  WindowGeometrySession(const WindowGeometrySession&) = delete;
  WindowGeometrySession& operator=(const WindowGeometrySession&) = delete;

  bool Restore(HWND window, int64_t view, int64_t owner) {
    DetachTracker();
    const bool maximized = geometry_.maximized();
    initial_show_.reset();
    initial_size_.reset();
    if (!RestoreNormalBounds(window, geometry_)) return false;
    auto initial_size = std::make_unique<InitialWindowSize>(window);
    if (!initial_size->Prepare()) return false;
    auto initial_show = std::make_unique<InitialShowMaximizer>(window, owner);
    if (!initial_show->Prepare(maximized)) return false;
    geometry_.Begin(view, owner);
    initial_size_ = std::move(initial_size);
    initial_show_ = std::move(initial_show);
    if (store_.enabled()) {
      tracked_window_ = window;
      tracked_view_ = view;
      tracked_owner_ = owner;
      tracked_presented_ = false;
      if (!SetWindowSubclass(window, TrackWindow, TrackerId(),
                              reinterpret_cast<DWORD_PTR>(this))) return false;
    }
    return Capture(window, view, owner);
  }

  bool Owns(int64_t view, int64_t owner) const {
    return geometry_.Owns(view, owner);
  }

  // Render the first scene for the client area it will actually be shown in.
  // The HWND stays hidden at its normal bounds until the SDK's first frame,
  // but a remembered maximized window must not present a normal-size buffer.
  std::optional<SIZE> InitialContentSize(HWND window) const {
    if (!initial_show_ || !initial_show_->pending()) return std::nullopt;
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(monitor);
    if (!GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                        &monitor)) return std::nullopt;
    return SIZE{monitor.rcWork.right - monitor.rcWork.left,
                monitor.rcWork.bottom - monitor.rcWork.top};
  }

  bool Capture(HWND window, int64_t view, int64_t owner,
               std::optional<bool> last_maximized = std::nullopt) {
    if (!Owns(view, owner)) return true;
    // A close before the first frame must not sample its temporary normal size
    // and erase the maximized state remembered by the previous playback window.
    if (initial_show_ && initial_show_->pending()) return true;
    const bool captured =
        CaptureNormalBounds(window, view, owner, geometry_, last_maximized);
    // Preparation is allowed to update the session, but not persistent state.
    if (captured && IsWindowVisible(window)) Persist();
    return captured;
  }

  bool SaveAndHide(HWND window, int64_t view, int64_t owner,
                   std::optional<bool> last_maximized = std::nullopt) {
    if (!Owns(view, owner)) return true;
    const bool captured = Capture(window, view, owner, last_maximized);
    // Hide before frame hooks are detached or Flutter removes the native view.
    // This also prevents the system caption flashing during asynchronous close.
    ShowWindow(window, SW_HIDE);
    Retire(view, owner);
    return captured;
  }

  void Retire(int64_t view, int64_t owner) {
    if (!Owns(view, owner)) return;
    DetachTracker();
    initial_show_.reset();
    initial_size_.reset();
    geometry_.Retire(view, owner);
  }

  const GeometrySession& saved() const { return geometry_; }

 private:
  static UINT_PTR TrackerId() {
    return reinterpret_cast<UINT_PTR>(&TrackWindow);
  }

  void Persist() const {
    if (!store_.Save(geometry_)) {
      OutputDebugStringW(L"BiliSail: cannot save window geometry.\n");
    }
  }

  void DetachTracker() {
    if (!tracked_window_) return;
    KillTimer(tracked_window_, TrackerId());
    // Capture the final visible state before engine teardown can hide windows.
    if (IsWindowVisible(tracked_window_)) {
      Capture(tracked_window_, tracked_view_, tracked_owner_);
    }
    if (tracked_presented_) Persist();
    if (IsWindow(tracked_window_) &&
        !RemoveWindowSubclass(tracked_window_, TrackWindow, TrackerId())) {
      // A retiring owner must never leave a callback carrying its address.
      SetWindowSubclass(tracked_window_, TrackWindow, TrackerId(), 0);
    }
    tracked_window_ = nullptr;
  }

  static LRESULT CALLBACK TrackWindow(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
    if (data == 0) {
      if (message == WM_NCDESTROY) RemoveWindowSubclass(window, TrackWindow, id);
      return DefSubclassProc(window, message, wparam, lparam);
    }
    auto& session = *reinterpret_cast<WindowGeometrySession*>(data);
    if (message == WM_NCDESTROY) {
      if (session.tracked_presented_) session.Persist();
      KillTimer(window, id);
      RemoveWindowSubclass(window, TrackWindow, id);
      session.tracked_window_ = nullptr;
    } else if (message == WM_TIMER && wparam == id) {
      KillTimer(window, id);
      session.Capture(window, session.tracked_view_, session.tracked_owner_);
      return 0;
    } else if (message == WM_EXITSIZEMOVE || message == WM_CLOSE ||
               message == WM_DESTROY || message == WM_ENDSESSION) {
      session.Capture(window, session.tracked_view_, session.tracked_owner_);
    } else if (message == WM_WINDOWPOSCHANGED && IsWindowVisible(window)) {
      if (!session.initial_show_ || !session.initial_show_->pending()) {
        CaptureNormalBounds(window, session.tracked_view_, session.tracked_owner_,
                            session.geometry_);
        session.tracked_presented_ = true;
      }
      // Debounce live resizing; explicit close/fullscreen capture flushes now.
      SetTimer(window, id, 250, nullptr);
    }
    // Forwarding can synchronously retire/destroy the owner. Do not use it again.
    return DefSubclassProc(window, message, wparam, lparam);
  }

  WindowGeometryStore store_;
  GeometrySession geometry_;
  HWND tracked_window_ = nullptr;
  int64_t tracked_view_ = -1;
  int64_t tracked_owner_ = -1;
  bool tracked_presented_ = false;
  std::unique_ptr<InitialWindowSize> initial_size_;
  std::unique_ptr<InitialShowMaximizer> initial_show_;
};

inline void ActivateWindow(HWND window, HWND view) {
  // Preparation may receive a newer media activation before the first frame.
  // Keep that window hidden until the SDK's first-frame callback shows it.
  if (!IsWindowVisible(window)) return;
  ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window);
  SetFocus(view);
}

}  // namespace playback_window

#endif  // RUNNER_PLAYBACK_WINDOW_GEOMETRY_WIN32_H_
