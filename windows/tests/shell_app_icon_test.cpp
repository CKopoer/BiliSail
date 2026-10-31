#include "../runner/shell_app_icon.h"

#include <propkey.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <wrl/client.h>

#include <array>
#include <fstream>
#include <iostream>
#include <stdexcept>

namespace {
using Microsoft::WRL::ComPtr;
namespace fs = std::filesystem;

void Check(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

ComPtr<IShellLinkW> Link(const fs::path& path) {
  ComPtr<IShellLinkW> link;
  Check(SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr,
                                   CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link))),
        "create Shell link");
  if (fs::exists(path)) {
    ComPtr<IPersistFile> file;
    Check(SUCCEEDED(link.As(&file)) &&
              SUCCEEDED(file->Load(path.c_str(), STGM_READ)),
          "load Shell link");
  }
  return link;
}

void Create(const fs::path& path, const fs::path& target) {
  fs::create_directories(path.parent_path());
  const auto link = Link(path);
  Check(
      SUCCEEDED(link->SetPath(target.c_str())) &&
          SUCCEEDED(link->SetArguments(L"--preserve-this-argument")) &&
          SUCCEEDED(link->SetDescription(L"Preserve this description")) &&
          SUCCEEDED(link->SetWorkingDirectory(target.parent_path().c_str())) &&
          SUCCEEDED(link->SetIconLocation(target.c_str(), -101)),
      "configure link");
  ComPtr<IPersistFile> file;
  Check(SUCCEEDED(link.As(&file)) && SUCCEEDED(file->Save(path.c_str(), TRUE)),
        "save link");
}

std::wstring Property(IPropertyStore* store, REFPROPERTYKEY key) {
  PROPVARIANT value{};
  Check(SUCCEEDED(store->GetValue(key, &value)), "read property");
  const std::wstring result = value.vt == VT_LPWSTR ? value.pwszVal : L"";
  PropVariantClear(&value);
  return result;
}

void CheckLink(const fs::path& path, const shell_app_icon::Identity& identity,
               int icon) {
  const auto link = Link(path);
  std::array<wchar_t, 32768> buffer{};
  int resource = 0;
  Check(SUCCEEDED(link->GetIconLocation(
            buffer.data(), static_cast<int>(buffer.size()), &resource)) &&
            resource == -icon && buffer.data() == identity.executable,
        "shortcut icon resource");
  Check(SUCCEEDED(link->GetArguments(buffer.data(),
                                     static_cast<int>(buffer.size()))) &&
            std::wstring(buffer.data()) == L"--preserve-this-argument",
        "arguments preserved");
  Check(SUCCEEDED(link->GetDescription(buffer.data(),
                                       static_cast<int>(buffer.size()))) &&
            std::wstring(buffer.data()) == L"Preserve this description",
        "description preserved");
  ComPtr<IPropertyStore> store;
  Check(SUCCEEDED(link.As(&store)) &&
            Property(store.Get(), PKEY_AppUserModel_ID) == identity.app_id,
        "shortcut AppUserModelID");
}

void TestShortcuts(const fs::path& root) {
  const auto user = root / L"user";
  const auto common = root / L"common";
  const auto relative = fs::path(L"BiliSail/BiliSail.lnk");
  const auto exe = root / L"application.exe";
  std::ofstream(exe).put('x');
  shell_app_icon::Identity identity{exe.wstring(), L"BiliSail.IconRegression",
                                    false};
  Check(shell_app_icon::UpdateStartMenu(identity, 102, user, common) == S_FALSE,
        "absent entries are not created");
  Create(common / relative, exe);
  Check(SetFileAttributesW((common / relative).c_str(),
                           FILE_ATTRIBUTE_READONLY) != FALSE,
        "common shortcut is read-only");
  const HRESULT copied =
      shell_app_icon::UpdateStartMenu(identity, 102, user, common);
  if (FAILED(copied))
    std::cerr << "override HRESULT: " << std::hex << copied << '\n';
  Check(SUCCEEDED(copied), "machine shortcut gets a per-user override");
  CheckLink(user / relative, identity, 102);
  const auto modified = fs::last_write_time(user / relative);
  Check(
      SUCCEEDED(shell_app_icon::UpdateStartMenu(identity, 102, user, common)) &&
          fs::last_write_time(user / relative) == modified,
      "restoring the same selection does not rewrite the link");
  const auto machine = Link(common / relative);
  std::array<wchar_t, 32768> buffer{};
  int resource = 0;
  Check(SUCCEEDED(machine->GetIconLocation(
            buffer.data(), static_cast<int>(buffer.size()), &resource)) &&
            resource == -101,
        "machine shortcut stays unchanged");
  Check(SUCCEEDED(shell_app_icon::UpdateStartMenu(identity, 101, user, common)),
        "restore default");
  CheckLink(user / relative, identity, 101);
  // A locked destination must retain the old link and report a real failure.
  const HANDLE locked =
      CreateFileW((user / relative).c_str(), GENERIC_READ, FILE_SHARE_READ,
                  nullptr, OPEN_EXISTING, 0, nullptr);
  Check(locked != INVALID_HANDLE_VALUE, "lock destination");
  const HRESULT failed =
      shell_app_icon::UpdateStartMenu(identity, 102, user, common);
  CloseHandle(locked);
  Check(FAILED(failed), "locked shortcut failure propagated");
  CheckLink(user / relative, identity, 101);
  for (const auto& entry :
       fs::directory_iterator((user / relative).parent_path())) {
    Check(entry.path().extension() != L".tmp",
          "failed save cleans temporary link");
  }
  identity.executable = (root / L"another-build.exe").wstring();
  std::ofstream(identity.executable).put('x');
  Check(shell_app_icon::UpdateStartMenu(identity, 102, user, common) == S_FALSE,
        "another installation's shortcut is untouched");
  identity.packaged = true;
  Check(shell_app_icon::UpdateStartMenu(identity, 102, user, common) == S_FALSE,
        "MSIX does not create a duplicate entry");
  std::cout << "Start menu: existing/machine/user/default/locked/foreign/MSIX "
               "passed\n";
}

void TestWindow() {
  shell_app_icon::Identity identity;
  Check(SUCCEEDED(shell_app_icon::CurrentIdentity(identity)) &&
            !identity.app_id.empty(),
        "resolve executable identity");
  const HWND window =
      CreateWindowExW(0, L"STATIC", L"Icon regression", WS_OVERLAPPED, 0, 0,
                      200, 100, nullptr, nullptr, nullptr, nullptr);
  Check(window != nullptr, "create test window");
  for (const int icon : {102, 101, 102}) {
    Check(SUCCEEDED(shell_app_icon::ApplyToWindow(window, identity, icon)),
          "apply taskbar properties");
    ComPtr<IPropertyStore> store;
    Check(SUCCEEDED(SHGetPropertyStoreForWindow(window, IID_PPV_ARGS(&store))),
          "window store");
    Check(Property(store.Get(), PKEY_AppUserModel_ID) == identity.app_id,
          "stable group identity");
    Check(Property(store.Get(), PKEY_AppUserModel_RelaunchIconResource) ==
              identity.executable + L",-" + std::to_wstring(icon),
          "taskbar icon selection");
    Check(Property(store.Get(), PKEY_AppUserModel_RelaunchCommand) ==
              L"\"" + identity.executable + L"\"",
          "quoted relaunch command");
  }
  DestroyWindow(window);
  std::cout
      << "Taskbar: real window property store and repeated switches passed\n";
}
}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 2;
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(initialized)) return 3;
  int result = 0;
  try {
    TestShortcuts(fs::path(argv[1]));
    TestWindow();
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    result = 1;
  }
  CoUninitialize();
  return result;
}
