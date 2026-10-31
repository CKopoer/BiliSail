#ifndef RUNNER_PLAYBACK_WINDOW_FIRST_SHOW_H_
#define RUNNER_PLAYBACK_WINDOW_FIRST_SHOW_H_

#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>

#include <cstdint>

namespace playback_window {

// DWM's first-show transition can temporarily clip our Flutter caption even
// when both the scene and final client rectangle already have the right size.
// Suppress only that transition, then restore animations after the outer SDK
// ShowWindow call has returned and DWM has presented its pending updates.
class FirstShowTransitions {
 public:
  FirstShowTransitions(HWND window, int64_t owner)
      : window_(window), owner_(static_cast<DWORD_PTR>(owner)) {}
  ~FirstShowTransitions() { Cancel(); }
  FirstShowTransitions(const FirstShowTransitions&) = delete;
  FirstShowTransitions& operator=(const FirstShowTransitions&) = delete;

  void Suppress() const {
    const BOOL disabled = TRUE;
    if (FAILED(DwmSetWindowAttribute(window_, DWMWA_TRANSITIONS_FORCEDISABLED,
                                    &disabled, sizeof(disabled)))) return;
    // Store the lease by value, never a pointer that a nested close can free.
    if (!SetWindowSubclass(window_, WindowProc, SubclassId(), owner_)) {
      SetEnabled(window_);
    }
  }

  bool pending() const {
    DWORD_PTR owner = 0;
    return IsWindow(window_) &&
        GetWindowSubclass(window_, WindowProc, SubclassId(), &owner) &&
        owner == owner_;
  }

  static void RestoreAfterFirstShow(HWND window) {
    DWORD_PTR owner = 0;
    if (!GetWindowSubclass(window, WindowProc, SubclassId(), &owner) ||
        owner == 0) return;
    const UINT message = RestoreMessage();
    if (message == 0 || !PostMessage(window, message, owner, 0)) {
      Detach(window, owner);
    }
  }

 private:
  static UINT_PTR SubclassId() {
    return reinterpret_cast<UINT_PTR>(&WindowProc);
  }

  static UINT RestoreMessage() {
    static const UINT message = RegisterWindowMessageW(
        L"BiliSail.Playback.RestoreFirstShowTransitions");
    return message;
  }

  static void SetEnabled(HWND window) {
    const BOOL disabled = FALSE;
    DwmSetWindowAttribute(window, DWMWA_TRANSITIONS_FORCEDISABLED,
                          &disabled, sizeof(disabled));
  }

  static void Detach(HWND window, DWORD_PTR expected_owner) {
    DWORD_PTR owner = 0;
    if (!IsWindow(window) ||
        !GetWindowSubclass(window, WindowProc, SubclassId(), &owner) ||
        owner != expected_owner) return;
    SetEnabled(window);
    if (!RemoveWindowSubclass(window, WindowProc, SubclassId())) {
      SetWindowSubclass(window, WindowProc, SubclassId(), 0);
    }
  }

  void Cancel() const { Detach(window_, owner_); }

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR subclass_id,
                                     DWORD_PTR owner) {
    if (message == WM_NCDESTROY) {
      RemoveWindowSubclass(window, WindowProc, subclass_id);
    } else if (owner != 0 && message == RestoreMessage()) {
      if (wparam == owner) {
        // This message runs outside the first-show window-procedure stack.
        // Flush the queued composition before allowing subsequent animations.
        DwmFlush();
        Detach(window, owner);
      }
      return 0;
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }

  HWND window_;  // Borrowed from the Flutter window controller.
  const DWORD_PTR owner_;
};

}  // namespace playback_window

#endif  // RUNNER_PLAYBACK_WINDOW_FIRST_SHOW_H_
