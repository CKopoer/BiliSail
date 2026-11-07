#include "../runner/playback_window_geometry_win32.h"
#include "../runner/playback_window_frame.h"
#include "../runner/mini_player_window.h"

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

// Model the SDK host forwarding frame messages to a shared plugin delegate.
// window_manager 0.5.2 uses the main window's zoom state in WM_NCCALCSIZE,
// even when this message belongs to a different, ordinary playback window.
class SdkWindowHost {
 public:
  SdkWindowHost(HWND window, bool main_maximized)
      : window_(window), main_maximized_(main_maximized) {
    child_ = CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE,
                             0, 0, 1, 1, window_, nullptr,
                             GetModuleHandle(nullptr), nullptr);
    Require(child_ != nullptr, "Cannot create SDK view child.");
    Require(SetWindowSubclass(window_, WindowProc, SubclassId(),
                               reinterpret_cast<DWORD_PTR>(this)) != FALSE,
            "Cannot install SDK host fixture.");
  }
  ~SdkWindowHost() {
    RemoveWindowSubclass(window_, WindowProc, SubclassId());
    DestroyWindow(child_);
  }
  SdkWindowHost(const SdkWindowHost&) = delete;
  SdkWindowHost& operator=(const SdkWindowHost&) = delete;

  HWND child() const { return child_; }
  int frame_delegate_calls() const { return frame_delegate_calls_; }

 private:
  static UINT_PTR SubclassId() {
    return reinterpret_cast<UINT_PTR>(&WindowProc);
  }
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR, DWORD_PTR data) {
    auto& host = *reinterpret_cast<SdkWindowHost*>(data);
    if (message == WM_NCCALCSIZE && wparam) {
      ++host.frame_delegate_calls_;
      if (host.main_maximized_) {
        auto& client = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam)->rgrc[0];
        MONITORINFO monitor{};
        monitor.cbSize = sizeof(monitor);
        if (!GetMonitorInfo(MonitorFromRect(&client, MONITOR_DEFAULTTONEAREST),
                             &monitor)) {
          return DefSubclassProc(window, message, wparam, lparam);
        }
        const LONG offset = client.left - monitor.rcWork.left;
        client.left -= offset;
        client.right += offset;
        return 0;
      }
    } else if (message == WM_SIZE) {
      RECT client{};
      GetClientRect(window, &client);
      MoveWindow(host.child_, client.left, client.top,
                  client.right - client.left, client.bottom - client.top, TRUE);
      return 0;
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }

  HWND window_;
  HWND child_ = nullptr;
  const bool main_maximized_;
  int frame_delegate_calls_ = 0;
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

void DrainWindowMessages(HWND window) {
  MSG message{};
  while (PeekMessage(&message, window, 0, 0, PM_REMOVE)) {
    TranslateMessage(&message);
    DispatchMessage(&message);
  }
}

void RunTransitionTests() {
  const TestWindow test;
  const HWND window = test.get();
  playback_window::FirstShowTransitions transitions(window, 100);
  Require(!transitions.pending(), "Ordinary creation suppressed animations.");
  transitions.Suppress();
  Require(transitions.pending(), "Cannot suppress the initial DWM transition.");
  playback_window::FirstShowTransitions::RestoreAfterFirstShow(window);
  Require(transitions.pending(), "Animations resumed inside the first-show stack.");
  DrainWindowMessages(window);
  Require(!transitions.pending(), "Animations remained disabled after composition.");

  auto old = std::make_unique<playback_window::FirstShowTransitions>(window, 101);
  old->Suppress();
  playback_window::FirstShowTransitions::RestoreAfterFirstShow(window);
  old.reset();
  playback_window::FirstShowTransitions current(window, 102);
  current.Suppress();
  DrainWindowMessages(window);
  Require(current.pending(), "A stale restore message changed the new lease.");
  playback_window::FirstShowTransitions::RestoreAfterFirstShow(window);
  DrainWindowMessages(window);
  Require(!current.pending(), "The current lease did not restore animations.");

  {
    playback_window::FirstShowTransitions cancelled(window, 103);
    cancelled.Suppress();
    Require(cancelled.pending(), "Cancellation fixture did not suppress animations.");
  }
  playback_window::FirstShowTransitions unprepared(window, 104);
  Require(!unprepared.pending(), "Cancelled first show retained a transition hook.");
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

void RunRestoredNormalSizeTests() {
  for (const int width : {460, 1100}) {
    playback_window::WindowGeometrySession session;
    playback_window::Bounds saved{};
    {
      const TestWindow original;
      const playback_window::PlaybackWindowFrame caption(original.get());
      Require(session.Restore(original.get(), 100, 100),
              "Cannot prepare original normal window.");
      ShowWindow(original.get(), SW_SHOWNORMAL);
      Require(SetWindowPos(original.get(), nullptr, 120, 140, width, 740,
                           SWP_NOZORDER | SWP_NOACTIVATE) != FALSE,
              "Cannot resize original normal window.");
      Require(session.SaveAndHide(original.get(), 100, 100),
              "Cannot save original normal window.");
      saved = *session.saved().normal();
    }
    for (int64_t owner = 101; owner <= 102; ++owner) {
      const TestWindow reopened;
      const HWND window = reopened.get();
      const playback_window::PlaybackWindowFrame caption(window);
      RECT default_client{};
      Require(GetClientRect(window, &default_client) != FALSE,
              "Cannot read default client size.");
      Require(session.Restore(window, owner, owner),
              "Cannot restore normal window.");
      RequireBounds(window, saved);
      Require(!IsWindowVisible(window), "Normal preparation showed the window.");
      RECT restored_client{};
      Require(GetClientRect(window, &restored_client) != FALSE,
              "Cannot read restored client size.");
      Require(restored_client.right != default_client.right,
              "Test did not change the default client width.");
      const auto initial_content = session.InitialContentSize(window);
      Require(initial_content.has_value(),
              "Restored normal window has no initial client size.");
      Require(initial_content->cx == restored_client.right &&
                  initial_content->cy == restored_client.bottom,
              "Normal first scene uses stale metrics or outer bounds.");
      // The SDK sizes to the first Flutter scene before showing the window.
      // Its standard caption insets must not change our saved outer bounds.
      SetWindowPos(window, nullptr, 0, 0,
                   static_cast<int>(saved.width),
                   static_cast<int>(saved.height) + 31,
                   SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOZORDER);
      ShowWindow(window, SW_SHOWNORMAL);
      RequireBounds(window, saved);
      Require(!IsZoomed(window), "Normal reopen became maximized.");
      Require(!session.InitialContentSize(window),
              "Normal first-scene size survived first show.");
      Require(session.SaveAndHide(window, owner, owner),
              "Cannot save reopened normal window.");
      Require(!session.InitialContentSize(window),
              "Retired normal window retained its first-scene size.");
    }
  }
}

void RunSharedFrameDelegateTests() {
  for (const bool main_maximized : {true, false}) {
    playback_window::WindowGeometrySession session;
    playback_window::Bounds saved{};
    {
      const TestWindow original;
      const playback_window::PlaybackWindowFrame caption(original.get());
      Require(session.Restore(original.get(), 201, 201), "Cannot prepare seed window.");
      ShowWindow(original.get(), SW_SHOWNORMAL);
      SetWindowPos(original.get(), nullptr, 240, 140, 460, 740,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      Require(session.SaveAndHide(original.get(), 201, 201), "Cannot save seed window.");
      saved = *session.saved().normal();
    }
    for (int64_t owner = 202; owner <= 203; ++owner) {
      const TestWindow reopened;
      const HWND window = reopened.get();
      RECT default_frame{}, default_client{};
      GetWindowRect(window, &default_frame);
      GetClientRect(window, &default_client);
      const LONG side_insets = default_frame.right - default_frame.left -
                              default_client.right;
      const SdkWindowHost host(window, main_maximized);
      const playback_window::PlaybackWindowFrame caption(window);
      Require(session.Restore(window, owner, owner), "Cannot restore hosted window.");
      for (const bool show : {false, true}) {
        if (show) ShowWindow(window, SW_SHOWNORMAL);
        RequireBounds(window, saved);
        RECT client{}, child{};
        GetClientRect(window, &client);
        GetClientRect(host.child(), &child);
        Require(client.right == static_cast<LONG>(saved.width) - side_insets,
                "Main-window delegate corrupted the playback client width.");
        Require(child.right == client.right && child.bottom == client.bottom,
                "SDK child does not fill the playback client area.");
        POINT origin{};
        MapWindowPoints(host.child(), window, &origin, 1);
        Require(origin.x == 0 && origin.y == 0,
                "SDK child is displaced outside the playback window.");
      }
      const LONG_PTR style = GetWindowLongPtr(window, GWL_STYLE);
      SetWindowLongPtr(window, GWL_STYLE, style & ~WS_OVERLAPPEDWINDOW);
      SetWindowPos(window, nullptr, 0, 0, 900, 700,
                   SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
      RECT fullscreen{}, fullscreen_child{};
      GetClientRect(window, &fullscreen);
      GetClientRect(host.child(), &fullscreen_child);
      Require(fullscreen.right == 900 && fullscreen.bottom == 700 &&
                  fullscreen_child.right == 900 && fullscreen_child.bottom == 700,
              "Main-window delegate corrupted fullscreen playback bounds.");
      SetWindowLongPtr(window, GWL_STYLE, style);
      SetWindowPos(window, nullptr, static_cast<int>(saved.left),
                   static_cast<int>(saved.top), static_cast<int>(saved.width),
                   static_cast<int>(saved.height),
                   SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
      Require(host.frame_delegate_calls() == 0,
              "Playback frame reached the main-window plugin delegate.");
      Require(session.SaveAndHide(window, owner, owner), "Cannot close hosted window.");
    }
  }
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
    const auto initial_content = session.InitialContentSize(ordinary.get());
    RECT client{};
    Require(initial_content && GetClientRect(ordinary.get(), &client) &&
                initial_content->cx == client.right &&
                initial_content->cy == client.bottom,
            "Normal reopen did not request its actual client size.");
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

class TestRegistry {
 public:
  TestRegistry() : key_(L"Software\\BiliSail\\GeometryTests\\" +
      std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64())) {}
  ~TestRegistry() { RegDeleteTreeW(HKEY_CURRENT_USER, key_.c_str()); }
  const std::wstring& key() const { return key_; }
 private:
  std::wstring key_;
};

void RunPersistenceTests() {
  const TestRegistry registry;
  const auto store = [&](const wchar_t* role) {
    return playback_window::WindowGeometryStore(role, registry.key());
  };
  {
    playback_window::WindowGeometrySession automatic(store(L"automatic"));
    const TestWindow window;
    Require(automatic.Restore(window.get(), 20, 20), "Cannot prepare automatic tracking.");
    ShowWindow(window.get(), SW_SHOWNORMAL);
    SetWindowPos(window.get(), nullptr, 100, 100, 820, 610,
                 SWP_NOZORDER | SWP_NOACTIVATE);
    Sleep(300);
    DrainWindowMessages(window.get());
    playback_window::GeometrySession record;
    store(L"automatic").Load(record);
    Require(record.normal() && record.normal()->width == 820,
            "Resize timer did not persist native geometry.");
    // Destruction must flush another move before the next debounce fires.
    SetWindowPos(window.get(), nullptr, 100, 100, 840, 610,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  }
  playback_window::GeometrySession destroyed;
  store(L"automatic").Load(destroyed);
  Require(destroyed.normal() && destroyed.normal()->width == 840,
          "Native destruction lost pending geometry.");
  playback_window::Bounds normal{};
  {
    playback_window::WindowGeometrySession main(store(L"main"));
    const TestWindow window;
    Require(main.Restore(window.get(), 0, 1), "Cannot prepare persistent main.");
    ShowWindow(window.get(), SW_SHOWNORMAL);
    Require(SetWindowPos(window.get(), nullptr, 120, 130, 860, 620,
                          SWP_NOZORDER | SWP_NOACTIVATE) != FALSE, "Cannot resize main.");
    RECT frame{};
    GetWindowRect(window.get(), &frame);
    normal = playback_window::RectBounds(frame);
    ShowWindow(window.get(), SW_MAXIMIZE);
    // No message pump/timer flush between maximize and minimize: keep zoom.
    ShowWindow(window.get(), SW_MINIMIZE);
    Require(main.SaveAndHide(window.get(), 0, 1), "Cannot save minimized main.");
  }
  {
    playback_window::WindowGeometrySession playback(store(L"playback"));
    Require(!playback.saved().normal(), "Main geometry leaked into playback role.");
    const TestWindow window;
    Require(playback.Restore(window.get(), 10, 10), "Cannot prepare playback.");
    ShowWindow(window.get(), SW_SHOWNORMAL);
    Require(playback.SaveAndHide(window.get(), 10, 10), "Cannot save playback.");
  }
  {
    playback_window::WindowGeometrySession next(store(L"main"));
    Require(next.saved().normal() && next.saved().maximized(),
            "Fresh engine lost persisted zoom state.");
    const TestWindow window;
    Require(next.Restore(window.get(), 0, 2), "Cannot restore persistent main.");
    ShowWindow(window.get(), SW_SHOWNORMAL);
    Require(IsZoomed(window.get()) != FALSE, "Relaunch did not restore maximized.");
    ShowWindow(window.get(), SW_RESTORE);
    RequireBounds(window.get(), normal);
    const auto style = GetWindowLongPtr(window.get(), GWL_STYLE);
    // Main-window fullscreen can retain WS_CAPTION while removing THICKFRAME.
    SetWindowLongPtr(window.get(), GWL_STYLE, style & ~WS_THICKFRAME);
    SetWindowPos(window.get(), nullptr, 0, 0, 1800, 1000, SWP_NOZORDER | SWP_NOACTIVATE);
    Require(next.Capture(window.get(), 0, 2), "Cannot capture fullscreen.");
    Require(next.saved().normal()->width == normal.width && !next.saved().maximized(),
            "Fullscreen overwrote normal rectangle or zoom.");
    Require(next.SaveAndHide(window.get(), 0, 2), "Cannot close fullscreen main.");
  }
  {
    playback_window::WindowGeometrySession next(store(L"main"));
    Require(next.saved().normal()->width == normal.width && !next.saved().maximized(),
            "User restore was not persisted.");
    const TestWindow pending;
    Require(next.Restore(pending.get(), 0, 3), "Cannot prepare cancelled main.");
    next.Retire(0, 3);
    playback_window::GeometrySession record;
    store(L"main").Load(record);
    Require(record.normal()->width == normal.width, "Hidden preparation changed disk state.");
  }
  // Verify actual process restart, reading the record through the production store.
  wchar_t executable[MAX_PATH]{};
  Require(GetModuleFileNameW(nullptr, executable, MAX_PATH) != 0, "Cannot find test exe.");
  std::wstring command = L"\"" + std::wstring(executable) + L"\" \"" + registry.key() + L"\"";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  Require(CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE,
                          CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process) != FALSE,
          "Cannot launch fresh process verification.");
  CloseHandle(process.hThread);
  const DWORD waited = WaitForSingleObject(process.hProcess, 10000);
  DWORD exit_code = 1;
  GetExitCodeProcess(process.hProcess, &exit_code);
  CloseHandle(process.hProcess);
  Require(waited == WAIT_OBJECT_0 && exit_code == 0, "Cross-process geometry restore failed.");

  const DWORD corrupt = 42;
  Require(RegSetKeyValueW(HKEY_CURRENT_USER, registry.key().c_str(), L"main",
                          REG_BINARY, &corrupt, sizeof(corrupt)) == ERROR_SUCCESS,
          "Cannot inject corrupt record.");
  playback_window::WindowGeometrySession invalid(store(L"main"));
  Require(!invalid.saved().normal(), "Corrupt geometry did not fall back to defaults.");
  playback_window::WindowGeometrySession untouched(store(L"playback"));
  Require(untouched.saved().normal().has_value(), "Corruption changed the other role.");
}
}  // namespace

void RunMiniPlayerTests() {
  const std::wstring key = L"Software\\BiliSail\\MiniPlayerTest-" + std::to_wstring(GetCurrentProcessId());
  const playback_window::WindowGeometryStore store(L"miniPlayer", key);
  const TestWindow window;
  ShowWindow(window.get(), SW_SHOWNORMAL);
  RECT normal{};
  GetWindowRect(window.get(), &normal);
  playback_window::GeometrySession normal_geometry;
  normal_geometry.Begin(1, 1);
  Require(playback_window::CaptureNormalBounds(window.get(), 1, 1, normal_geometry), "Cannot capture normal window.");
  {
    playback_window::MiniPlayerWindow mini(window.get(), store);
    Require(mini.Enter(), "Cannot enter mini player.");
    Require((GetWindowLongPtr(window.get(), GWL_EXSTYLE) & WS_EX_TOPMOST) != 0, "Mini player was not pinned.");
    Require((GetWindowLongPtr(window.get(), GWL_STYLE) & WS_CAPTION) == 0, "Mini player retained the caption.");
    SetWindowPos(window.get(), nullptr, 110, 120, 360, 203, SWP_NOZORDER | SWP_NOACTIVATE);
    Require(playback_window::CaptureNormalBounds(window.get(), 1, 1, normal_geometry), "Cannot capture during mini player.");
    Require(normal_geometry.normal()->width == normal.right - normal.left, "Mini player overwrote ordinary bounds.");
    SendMessage(window.get(), WM_EXITSIZEMOVE, 0, 0);
    mini.Restore();
  }
  RequireBounds(window.get(), playback_window::RectBounds(normal));
  Require((GetWindowLongPtr(window.get(), GWL_EXSTYLE) & WS_EX_TOPMOST) == 0, "Mini player changed normal pin state.");
  {
    playback_window::MiniPlayerWindow reopened(window.get(), store);
    Require(reopened.Enter(), "Cannot reopen mini player.");
    RECT bounds{};
    GetWindowRect(window.get(), &bounds);
    Require(bounds.left == 110 && bounds.top == 120 && bounds.right - bounds.left == 360 && bounds.bottom - bounds.top == 203,
            "Mini player did not restore its separate geometry.");
    MINMAXINFO limits{};
    SendMessage(window.get(), WM_GETMINMAXINFO, 0, reinterpret_cast<LPARAM>(&limits));
    Require(limits.ptMinTrackSize.x >= 240 && limits.ptMinTrackSize.y >= 135, "Mini player lost resize minimum.");
  }
  ShowWindow(window.get(), SW_MAXIMIZE);
  {
    playback_window::MiniPlayerWindow zoomed(window.get(), store);
    Require(zoomed.Enter(), "Cannot enter mini player from maximized window.");
    zoomed.Restore();
    Require(IsZoomed(window.get()) != FALSE, "Mini player lost normal maximize state.");
  }
  RegDeleteTreeW(HKEY_CURRENT_USER, key.c_str());
}

int wmain(int argc, wchar_t* argv[]) {
  try {
    if (argc == 2) {
      playback_window::GeometrySession main, playback;
      playback_window::WindowGeometryStore(L"main", argv[1]).Load(main);
      playback_window::WindowGeometryStore(L"playback", argv[1]).Load(playback);
      Require(main.normal() && !main.maximized() && playback.normal(),
              "Fresh process did not read both role records.");
      Require(main.normal()->width == 860 && playback.normal()->width == 900,
              "Fresh process did not preserve independent sizes.");
      return 0;
    }
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    const IsolatedDesktop desktop;
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = DefWindowProcW;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.lpszClassName = L"BiliSailGeometryTestWindow";
    Require(RegisterClassW(&window_class) != 0, "Cannot register test window class.");
    RunTests();
    RunTransitionTests();
    RunFrameTests();
    RunSharedFrameDelegateTests();
    RunRestoredNormalSizeTests();
    RunInitialSizeTests();
    RunPersistenceTests();
    RunMiniPlayerTests();
    UnregisterClassW(window_class.lpszClassName, window_class.hInstance);
    std::cout << "PASS native first show, caption and persistence: SDK restore reproduction, directly visible maximized reopen, user Restore, normal bounds, narrow/wide first scene on repeated reopen, main-window delegate isolation and SDK child bounds, minimize, pending close, reentrant cancellation, stale owner, fullscreen, custom client frame, app brightness, detach, independent roles, cross-process restore and corrupt records\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL native first show: " << error.what() << '\n';
    return 1;
  }
}
