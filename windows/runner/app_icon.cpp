#include "app_icon.h"

#include <flutter/standard_method_codec.h>

#include <string>

#include "resource.h"

AppIconChannel::AppIconChannel(flutter::BinaryMessenger* messenger)
    : channel_(messenger, "bilisail/app_icon",
               &flutter::StandardMethodCodec::GetInstance()) {
  channel_.SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "setIcon") {
      result->NotImplemented();
      return;
    }
    const auto* args = call.arguments()
        ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
    const auto entry = args ? args->find(flutter::EncodableValue("icon"))
                            : flutter::EncodableMap::const_iterator{};
    const auto* name = args && entry != args->end()
        ? std::get_if<std::string>(&entry->second) : nullptr;
    if (!name || (*name != "bilisail" && *name != "bilibili")) {
      result->Error("invalid_icon", "Unknown application icon.");
      return;
    }
    const int resource = *name == "bilibili" ? IDI_BILIBILI_ICON : IDI_APP_ICON;
    const HICON large_icon = Load(resource, GetSystemMetrics(SM_CXICON),
                                  GetSystemMetrics(SM_CYICON));
    const HICON small_icon = Load(resource, GetSystemMetrics(SM_CXSMICON),
                                  GetSystemMetrics(SM_CYSMICON));
    if (!large_icon || !small_icon) {
      result->Error("icon_load_failed", "Cannot load the application icon.");
      return;
    }
    HRESULT shell_result = shell_app_icon::CurrentIdentity(identity_);
    if (SUCCEEDED(shell_result)) {
      shell_result = shell_app_icon::UpdateStartMenu(identity_, resource);
    }
    if (FAILED(shell_result)) {
      result->Error("shell_icon_failed", "Cannot update the Start menu icon.");
      return;
    }
    resource_id_ = resource;
    apply_result_ = S_OK;
    EnumWindows([](HWND window, LPARAM data) -> BOOL {
      DWORD process = 0;
      GetWindowThreadProcessId(window, &process);
      if (process == GetCurrentProcessId()) {
        auto* self = reinterpret_cast<AppIconChannel*>(data);
        const HRESULT applied = self->ApplyTo(window);
        if (FAILED(applied)) self->apply_result_ = applied;
      }
      return TRUE;
    }, reinterpret_cast<LPARAM>(this));
    if (FAILED(apply_result_)) {
      result->Error("taskbar_icon_failed", "Cannot update the taskbar icon.");
      return;
    }
    result->Success();
  });
}

AppIconChannel::~AppIconChannel() {
  channel_.SetMethodCallHandler(nullptr);
  // HWNDs may outlive the engine channels during shutdown. Stop borrowing our
  // cached handles before their RAII owners release them.
  EnumWindows([](HWND window, LPARAM) -> BOOL {
    DWORD process = 0;
    GetWindowThreadProcessId(window, &process);
    if (process == GetCurrentProcessId()) {
      const HICON fallback = LoadIcon(GetModuleHandle(nullptr),
                                       MAKEINTRESOURCE(IDI_APP_ICON));
      SendMessage(window, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(fallback));
      SendMessage(window, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(fallback));
    }
    return TRUE;
  }, 0);
}

HICON AppIconChannel::Load(int resource, int width, int height) {
  const auto key = std::make_tuple(resource, width, height);
  const auto found = icons_.find(key);
  if (found != icons_.end()) return found->second.get();
  // LR_SHARED can return a cached resource of the wrong size. Cache owned
  // handles by pixel dimensions so large and small/DPI variants stay distinct.
  Icon icon(reinterpret_cast<HICON>(LoadImage(
      GetModuleHandle(nullptr), MAKEINTRESOURCE(resource), IMAGE_ICON,
      width, height, LR_DEFAULTCOLOR)));
  if (!icon) return nullptr;
  return icons_.emplace(key, std::move(icon)).first->second.get();
}

HRESULT AppIconChannel::ApplyTo(HWND window) {
  if (!resource_id_) return S_FALSE;
  const UINT dpi = GetDpiForWindow(window);
  const HICON large_icon = Load(resource_id_, GetSystemMetricsForDpi(SM_CXICON, dpi),
                                GetSystemMetricsForDpi(SM_CYICON, dpi));
  const HICON small_icon = Load(resource_id_, GetSystemMetricsForDpi(SM_CXSMICON, dpi),
                                GetSystemMetricsForDpi(SM_CYSMICON, dpi));
  if (!large_icon || !small_icon) return HRESULT_FROM_WIN32(ERROR_RESOURCE_NOT_FOUND);
  SendMessage(window, WM_SETICON, ICON_BIG,
              reinterpret_cast<LPARAM>(large_icon));
  SendMessage(window, WM_SETICON, ICON_SMALL,
              reinterpret_cast<LPARAM>(small_icon));
  return shell_app_icon::ApplyToWindow(window, identity_, resource_id_);
}
