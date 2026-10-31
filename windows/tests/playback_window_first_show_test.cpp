#include "../runner/playback_window_geometry_win32.h"
#include "../runner/playback_window_frame.h"

#include <iostream>
#include <stdexcept>
#include <string>

namespace {
void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// Exercise real ShowWindow/WM_WINDOWPOSCHANGED without displaying test windows
// on the user's input desktop or starting the production Flutter application.
class IsolatedDesktop {
 public:
  IsolatedDesktop()
      : previous_(GetThreadDesktop(GetCurrentThreadId())),
        desktop_(CreateDesktopW(
            (L"BiliSailGeometryTest-" + std::to_wstring(GetCurrentProcessId()))
                .c_str(),
            nullptr, nullptr, 0,
            DESKTOP_CREATEWINDOW | DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS,
            nullptr)) {
    if (!desktop_) throw std::runtime_error("Cannot create isolated test desktop.");
    if (!SetThreadDesktop(desktop_)) {
      CloseDesktop(desktop_);
      throw std::runtime_error("Cannot select isolated test desktop.");
    }
  }
  ~IsolatedDesktop() {
    SetThreadDesktop(previous_);
    CloseDesktop(desktop_);
  }
  IsolatedDesktop(const IsolatedDesktop&) = delete;
  IsolatedDesktop& operator=(const IsolatedDesktop&) = delete;

 private:
  HDESK previous_;  // Borrowed from the test thread.
  HDESK desktop_;
};

class TestWindow {
 public:
  TestWindow()
      : window_(CreateWindowExW(0, L"BiliSailGeometryTestWindow", L"Geometry test",
                                WS_OVERLAPPEDWINDOW, 80, 90, 900, 700, nullptr,
                                nullptr, GetModuleHandle(nullptr), nullptr)) {
    Require(window_ != nullptr, "Cannot create native test window.");
  }
  ~TestWindow() { DestroyWindow(window_); }
  TestWindow(const TestWindow&) = delete;
  TestWindow& operator=(const TestWindow&) = delete;
  HWND get() const { return window_; }

 private:
  HWND window_;
};

class FirstVisiblePresentation {
 public:
  explicit FirstVisiblePresentation(HWND window) : window_(window) {
    Require(SetWindowSubclass(window_, WindowProc, SubclassId(),
                               reinterpret_cast<DWORD_PTR>(this)) != FALSE,
            "Cannot observe the first visible presentation.");
  }
  ~FirstVisiblePresentation() {
    RemoveWindowSubclass(window_, WindowProc, SubclassId());
  }
  FirstVisiblePresentation(const FirstVisiblePresentation&) = delete;
  FirstVisiblePresentation& operator=(const FirstVisiblePresentation&) = delete;

  bool saw_visible_normal() const { return saw_visible_normal_; }
  bool saw_visible_maximized() const { return saw_visible_maximized_; }

 private:
  static UINT_PTR SubclassId() {
    return reinterpret_cast<UINT_PTR>(&WindowProc);
  }
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR, DWORD_PTR data) {
    if (message == WM_WINDOWPOSCHANGED && IsWindowVisible(window)) {
      auto& probe = *reinterpret_cast<FirstVisiblePresentation*>(data);
      if (IsZoomed(window)) {
        probe.saw_visible_maximized_ = true;
      } else {
        probe.saw_visible_normal_ = true;
      }
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }
  HWND window_;
  bool saw_visible_normal_ = false;
  bool saw_visible_maximized_ = false;
};

// Model a Dart/native listener retiring the lease during first-show delivery.
class CancelDuringFirstShow {
 public:
  CancelDuringFirstShow(HWND window,
                       playback_window::WindowGeometrySession& session)
      : window_(window), session_(session) {
    Require(SetWindowSubclass(window_, WindowProc, SubclassId(),
                               reinterpret_cast<DWORD_PTR>(this)) != FALSE,
            "Cannot install reentrant cancellation probe.");
  }
  ~CancelDuringFirstShow() {
    RemoveWindowSubclass(window_, WindowProc, SubclassId());
  }
  CancelDuringFirstShow(const CancelDuringFirstShow&) = delete;
  CancelDuringFirstShow& operator=(const CancelDuringFirstShow&) = delete;

  void Arm() { armed_ = true; }
  bool fired() const { return fired_; }

 private:
  static UINT_PTR SubclassId() {
    return reinterpret_cast<UINT_PTR>(&WindowProc);
  }
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR, DWORD_PTR data) {
    auto& probe = *reinterpret_cast<CancelDuringFirstShow*>(data);
    if (probe.armed_ && message == WM_WINDOWPOSCHANGED) {
      probe.armed_ = false;
      probe.fired_ = true;
      probe.session_.Retire(80, 80);
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }
  HWND window_;
  playback_window::WindowGeometrySession& session_;
  bool armed_ = false;
  bool fired_ = false;
};

void RequireBounds(HWND window, const playback_window::Bounds& expected) {
  RECT rectangle{};
  Require(GetWindowRect(window, &rectangle) != FALSE, "Cannot read normal bounds.");
  const auto actual = playback_window::RectBounds(rectangle);
  Require(std::abs(actual.left - expected.left) <= 1 &&
              std::abs(actual.top - expected.top) <= 1 &&
              std::abs(actual.width - expected.width) <= 1 &&
              std::abs(actual.height - expected.height) <= 1,
          "User Restore lost the remembered normal rectangle.");
}

void RunFrameTests() {
  const TestWindow test;
  const HWND window = test.get();
  RECT original{}, frame{};
  Require(GetClientRect(window, &original) != FALSE, "Cannot read original client.");
  Require(GetWindowRect(window, &frame) != FALSE, "Cannot read original frame.");
  const UINT dpi = GetDpiForWindow(window);
  {
    const playback_window::PlaybackWindowFrame caption(window);
    Require(caption.ready(), "Cannot install playback frame.");
    const LONG_PTR original_style = GetWindowLongPtr(window, GWL_STYLE);
    for (const bool dark : {true, false}) {
      const COLORREF expected_color = dark ? RGB(21, 31, 41) : RGB(245, 247, 251);
      caption.SetTheme(dark, expected_color);
      // Keep dark-mode opt-in when the playback window loses focus.
      SendMessage(window, WM_NCACTIVATE, FALSE, 0);
      BOOL actual_dark = FALSE;
      Require(SUCCEEDED(DwmGetWindowAttribute(window, 20, &actual_dark,
                                               sizeof(actual_dark))) &&
                  (actual_dark != FALSE) == dark,
              "Native frame did not follow app brightness.");
      // DWMWA_CAPTION_COLOR is documented for DwmSetWindowAttribute only;
      // reading it is not a supported way to verify the caption color.
      Require(GetWindowLongPtr(window, GWL_STYLE) == original_style,
              "Applying the frame theme changed native resize styles.");
      RequireBounds(window, playback_window::RectBounds(frame));
    }
    RECT client{};
    Require(GetClientRect(window, &client) != FALSE, "Cannot read custom client.");
    Require(client.bottom - original.bottom ==
                GetSystemMetricsForDpi(SM_CYCAPTION, dpi) +
                    GetSystemMetricsForDpi(SM_CYFRAME, dpi) +
                    GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi),
            "Custom frame left space above the Flutter caption.");
    RequireBounds(window, playback_window::RectBounds(frame));
    POINT origin{};
    ClientToScreen(window, &origin);
    Require(origin.y == frame.top, "Client does not reach the top window edge.");
    for (const auto& hit : {std::pair<LONG, LRESULT>{frame.left + 1, HTTOPLEFT},
                           {frame.left + 100, HTTOP},
                           {frame.right - 1, HTTOPRIGHT}}) {
      Require(SendMessage(window, WM_NCHITTEST, 0,
                          MAKELPARAM(hit.first, frame.top + 1)) == hit.second,
              "Client caption lost top-edge resize hit testing.");
    }
    Require(SendMessage(window, WM_NCHITTEST, 0,
                        MAKELPARAM(frame.right - 30, origin.y + 22)) == HTCLIENT,
            "Native caption buttons overlap Flutter controls.");
    ShowWindow(window, SW_MAXIMIZE);
    origin = {};
    ClientToScreen(window, &origin);
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(monitor);
    Require(GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                            &monitor) != FALSE, "Cannot read maximized work area.");
    Require(origin.y == monitor.rcWork.top,
            "Maximized client clipped the Flutter caption.");
    ShowWindow(window, SW_RESTORE);
    const LONG_PTR style = GetWindowLongPtr(window, GWL_STYLE);
    SetWindowLongPtr(window, GWL_STYLE, style & ~WS_OVERLAPPEDWINDOW);
    SetWindowPos(window, nullptr, 0, 0, 900, 700,
                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    Require(GetClientRect(window, &client) != FALSE &&
                client.right == 900 && client.bottom == 700,
            "Custom caption left a border in fullscreen.");
    SetWindowLongPtr(window, GWL_STYLE, style);
    SetWindowPos(window, nullptr, frame.left, frame.top,
                 frame.right - frame.left, frame.bottom - frame.top,
                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  }
  RECT restored{};
  Require(GetClientRect(window, &restored) != FALSE &&
              restored.right == original.right && restored.bottom == original.bottom,
          "Detaching the custom frame did not restore the native caption.");
}

void RunInitialSizeTests() {
  playback_window::WindowGeometrySession session;
  const TestWindow first;
  const HWND window = first.get();
  const playback_window::PlaybackWindowFrame caption(window);
  Require(session.Restore(window, 90, 90), "Initial size preparation failed.");
  const auto prepared = *session.saved().normal();
  // Reproduce the SDK adding standard caption insets during content sizing.
  SetWindowPos(window, nullptr, 0, 0,
               static_cast<int>(prepared.width),
               static_cast<int>(prepared.height) + 31,
               SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOZORDER);
  RequireBounds(window, prepared);
  ShowWindow(window, SW_SHOWNORMAL);
  RequireBounds(window, prepared);
  SetWindowPos(window, nullptr, 0, 0,
               static_cast<int>(prepared.width) + 80,
               static_cast<int>(prepared.height) + 60,
               SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOZORDER);
  Require(session.Capture(window, 90, 90), "User resize capture failed.");
  const auto resized = *session.saved().normal();
  Require(resized.width == prepared.width + 80 &&
              resized.height == prepared.height + 60,
          "Initial sizing hook blocked a later user resize.");
  session.Retire(90, 90);

  const TestWindow cancelled;
  Require(session.Restore(cancelled.get(), 91, 91), "Cancelled size restore failed.");
  session.Retire(91, 91);
  SetWindowPos(cancelled.get(), nullptr, 0, 0, 700, 500,
               SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOZORDER);
  RECT bounds{};
  GetWindowRect(cancelled.get(), &bounds);
  Require(bounds.right - bounds.left == 700 && bounds.bottom - bounds.top == 500,
          "Retired owner retained its initial size constraint.");
}

void RunTests() {
  {
    playback_window::WindowGeometrySession closing;
    const TestWindow old, current;
    Require(closing.Restore(old.get(), 91, 91), "Close preparation failed.");
    ShowWindow(old.get(), SW_SHOWNORMAL);
    ShowWindow(old.get(), SW_MAXIMIZE);
    Require(closing.SaveAndHide(old.get(), 91, 91), "Save and hide failed.");
    Require(!IsWindowVisible(old.get()), "Closing window stayed visible.");
    Require(closing.saved().maximized(), "Hiding erased maximized memory.");
    Require(closing.Restore(current.get(), 92, 92), "Rapid reopen failed.");
    ShowWindow(current.get(), SW_SHOWNORMAL);
    Require(IsZoomed(current.get()) != FALSE, "Rapid reopen lost maximization.");
    Require(closing.SaveAndHide(current.get(), 91, 91), "Stale close failed.");
    Require(IsWindowVisible(current.get()) != FALSE && closing.Owns(92, 92),
            "Stale save hid or retired the new window.");
    Require(closing.SaveAndHide(current.get(), 92, 92), "New close failed.");
    Require(!IsWindowVisible(current.get()), "Reopened window stayed visible.");
  }
  // Reproduce the original implementation and the pinned SDK's first-frame
  // callback. The second call finishes unmaximized despite the earlier zoom.
  {
    const TestWindow old_flow;
    ShowWindow(old_flow.get(), SW_MAXIMIZE);
    Require(IsZoomed(old_flow.get()) != FALSE, "Original maximize did not run.");
    ShowWindow(old_flow.get(), SW_SHOWNORMAL);
    Require(!IsZoomed(old_flow.get()), "SDK first show did not reproduce restore.");
  }

  playback_window::WindowGeometrySession session;
  playback_window::Bounds normal{};
  {
    const TestWindow first;
    Require(session.Restore(first.get(), 1, 1), "Initial geometry failed.");
    ShowWindow(first.get(), SW_SHOWNORMAL);
    Require(!IsZoomed(first.get()), "First window should keep its normal default.");
    Require(SetWindowPos(first.get(), nullptr, 120, 140, 780, 540,
                         SWP_NOZORDER | SWP_NOACTIVATE) != FALSE,
            "Cannot set a user normal rectangle.");
    Require(session.Capture(first.get(), 1, 1), "Cannot capture normal size.");
    normal = *session.saved().normal();
    ShowWindow(first.get(), SW_MAXIMIZE);
    Require(session.Capture(first.get(), 1, 1), "Cannot capture maximized state.");
    Require(session.saved().maximized(), "Maximized memory was not recorded.");
    session.Retire(1, 1);
  }

  {
    const TestWindow reopened;
    const playback_window::PlaybackWindowFrame caption(reopened.get());
    Require(session.Restore(reopened.get(), 2, 2), "Reopen restore failed.");
    const auto initial_content = session.InitialContentSize(reopened.get());
    Require(initial_content.has_value(), "Maximized first scene has no target size.");
    Require(!IsWindowVisible(reopened.get()), "Prepare showed a blank window.");
    playback_window::ActivateWindow(reopened.get(), reopened.get());
    Require(!IsWindowVisible(reopened.get()), "Early activation consumed first show.");
    const FirstVisiblePresentation first_show(reopened.get());
    // This is the engine's actual SW_SHOWNORMAL. Assert only after the whole
    // Win32 call returns, so remaining native processing cannot undo the fix.
    ShowWindow(reopened.get(), SW_SHOWNORMAL);
    Require(IsZoomed(reopened.get()) != FALSE, "SDK first show undid maximization.");
    Require(!first_show.saw_visible_normal() && first_show.saw_visible_maximized(),
            "Maximized reopen first exposed an ordinary window.");
    RECT client{};
    Require(GetClientRect(reopened.get(), &client) != FALSE &&
                client.right == initial_content->cx &&
                client.bottom == initial_content->cy,
            "First scene size differs from the maximized custom client area.");
    Require(!session.InitialContentSize(reopened.get()),
            "First scene override survived first show.");
    Require(session.Capture(reopened.get(), 2, 2), "Reopen capture failed.");
    playback_window::ActivateWindow(reopened.get(), reopened.get());
    Require(IsZoomed(reopened.get()) != FALSE, "Activation undid maximization.");
    ShowWindow(reopened.get(), SW_MINIMIZE);
    Require(session.Capture(reopened.get(), 2, 2, true), "Minimized capture failed.");
    Require(session.saved().maximized(), "Minimize erased preceding maximization.");
    playback_window::ActivateWindow(reopened.get(), reopened.get());
    Require(IsZoomed(reopened.get()) != FALSE, "Minimized activation lost zoom.");
    ShowWindow(reopened.get(), SW_RESTORE);
    Require(!IsZoomed(reopened.get()), "One-shot hook blocked user Restore.");
    RequireBounds(reopened.get(), normal);
    Require(session.Capture(reopened.get(), 2, 2), "Restored capture failed.");
    Require(!session.saved().maximized(), "User Restore did not replace zoom memory.");
    session.Retire(2, 2);
  }

  {
    const TestWindow ordinary;
    Require(session.Restore(ordinary.get(), 3, 3), "Normal reopen failed.");
    Require(!session.InitialContentSize(ordinary.get()),
            "Normal reopen requested a maximized first scene.");
    ShowWindow(ordinary.get(), SW_SHOWNORMAL);
    Require(!IsZoomed(ordinary.get()), "Normal reopen ignored user's Restore.");
    RequireBounds(ordinary.get(), normal);
    ShowWindow(ordinary.get(), SW_MAXIMIZE);
    Require(session.Capture(ordinary.get(), 3, 3), "Cannot re-maximize memory.");
    session.Retire(3, 3);
  }

  {
    const TestWindow before_frame;
    Require(session.Restore(before_frame.get(), 4, 4), "Pending restore failed.");
    Require(session.Capture(before_frame.get(), 4, 4, false), "Pending close capture failed.");
    Require(session.saved().maximized(), "Close before first frame erased zoom.");
    session.Retire(4, 4);
    Require(!session.InitialContentSize(before_frame.get()),
            "Retired window retained its first scene size.");
    ShowWindow(before_frame.get(), SW_SHOWNORMAL);
    Require(!IsZoomed(before_frame.get()), "Retired owner retained first-show hook.");
  }

  {
    const TestWindow cancelled;
    CancelDuringFirstShow cancel(cancelled.get(), session);
    Require(session.Restore(cancelled.get(), 80, 80), "Reentrant prepare failed.");
    cancel.Arm();
    ShowWindow(cancelled.get(), SW_SHOWNORMAL);
    Require(cancel.fired(), "Reentrant cancellation was not delivered.");
    Require(!IsWindowVisible(cancelled.get()), "Retired first show became visible.");
    Require(!session.Owns(80, 80), "Reentrant cancellation retained the old lease.");
    Require(session.saved().maximized(), "Reentrant cancellation erased zoom.");
  }

  {
    const TestWindow stale, latest;
    Require(session.Restore(stale.get(), 5, 5), "Stale prepare failed.");
    Require(session.Restore(latest.get(), 6, 6), "Latest prepare failed.");
    Require(session.Capture(stale.get(), 5, 5, false), "Stale capture was not ignored.");
    session.Retire(5, 5);
    Require(session.Owns(6, 6), "Stale retire removed latest geometry owner.");
    ShowWindow(stale.get(), SW_SHOWNORMAL);
    Require(!IsZoomed(stale.get()), "New owner did not cancel old first-show hook.");
    ShowWindow(latest.get(), SW_SHOWNORMAL);
    Require(IsZoomed(latest.get()) != FALSE, "Stale close cancelled latest maximize.");
    session.Retire(6, 6);
  }

  {
    const TestWindow fullscreen;
    Require(session.Restore(fullscreen.get(), 7, 7), "Fullscreen prepare failed.");
    const LONG_PTR style = GetWindowLongPtr(fullscreen.get(), GWL_STYLE);
    SetWindowLongPtr(fullscreen.get(), GWL_STYLE, style & ~WS_CAPTION);
    ShowWindow(fullscreen.get(), SW_SHOWNORMAL);
    Require(!IsZoomed(fullscreen.get()), "First-show hook maximized a fullscreen frame.");
    Require(session.Capture(fullscreen.get(), 7, 7, false), "Fullscreen capture failed.");
    Require(session.saved().maximized(), "Fullscreen erased ordinary zoom memory.");
    session.Retire(7, 7);
  }
}
}  // namespace

int main() {
  try {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    const IsolatedDesktop desktop;
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = DefWindowProcW;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.lpszClassName = L"BiliSailGeometryTestWindow";
    Require(RegisterClassW(&window_class) != 0, "Cannot register test window class.");
    RunTests();
    RunFrameTests();
    RunInitialSizeTests();
    UnregisterClassW(window_class.lpszClassName, window_class.hInstance);
    std::cout << "PASS native first show and caption: SDK restore reproduction, directly visible maximized reopen, user Restore, normal bounds, minimize, pending close, reentrant cancellation, stale owner, fullscreen, custom client frame, app brightness and detach\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL native first show: " << error.what() << '\n';
    return 1;
  }
}
