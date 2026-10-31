#ifndef RUNNER_SHELL_APP_ICON_H_
#define RUNNER_SHELL_APP_ICON_H_

#include <windows.h>

#include <filesystem>
#include <string>

namespace shell_app_icon {

struct Identity {
  std::wstring executable;
  std::wstring app_id;
  bool packaged = false;
};

HRESULT CurrentIdentity(Identity& identity);
HRESULT ApplyToWindow(HWND window, const Identity& identity, int resource);

// Updates only BiliSail's existing Start menu entry for this executable. A
// machine-wide entry is copied to the matching per-user location, so changing
// a personal preference never needs elevation or affects another user.
HRESULT UpdateStartMenu(const Identity& identity, int resource,
                        const std::filesystem::path& user_programs,
                        const std::filesystem::path& common_programs);
HRESULT UpdateStartMenu(const Identity& identity, int resource);

}  // namespace shell_app_icon

#endif  // RUNNER_SHELL_APP_ICON_H_
