#include "shell_app_icon.h"

#include <appmodel.h>
#include <propkey.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <wrl/client.h>

#include <array>
#include <cstdint>
#include <cwctype>
#include <memory>
#include <system_error>
#include <vector>

namespace shell_app_icon {
namespace {
using Microsoft::WRL::ComPtr;
constexpr wchar_t kShortcut[] = L"BiliSail\\BiliSail.lnk";

HRESULT SetString(IPropertyStore* store, REFPROPERTYKEY key,
                  const std::wstring& value) {
  PROPVARIANT property{};
  const HRESULT initialized =
      InitPropVariantFromString(value.c_str(), &property);
  if (FAILED(initialized)) return initialized;
  const HRESULT result = store->SetValue(key, property);
  PropVariantClear(&property);
  return result;
}

struct TaskMemDeleter {
  void operator()(wchar_t* value) const { CoTaskMemFree(value); }
};

HRESULT Programs(REFKNOWNFOLDERID id, std::filesystem::path& path) {
  wchar_t* buffer = nullptr;
  const HRESULT result =
      SHGetKnownFolderPath(id, KF_FLAG_DEFAULT, nullptr, &buffer);
  const std::unique_ptr<wchar_t, TaskMemDeleter> owned(buffer);
  if (SUCCEEDED(result)) path = buffer;
  return result;
}

HRESULT LoadShortcut(const std::filesystem::path& path,
                     ComPtr<IShellLinkW>& link, ComPtr<IPersistFile>& file) {
  ComPtr<IShellLinkW> source;
  ComPtr<IPersistFile> source_file;
  HRESULT result = CoCreateInstance(
      CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&source));
  if (SUCCEEDED(result)) result = source.As(&source_file);
  if (SUCCEEDED(result)) result = source_file->Load(path.c_str(), STGM_READ);
  // A read-only Shell link also has a read-only property store. Clone through
  // its standard persistence interface instead of opening the common link for
  // writing or reconstructing (and losing) its arguments and other properties.
  ComPtr<IPersistStream> source_stream, destination_stream;
  ComPtr<IStream> stream;
  if (SUCCEEDED(result)) result = source.As(&source_stream);
  if (SUCCEEDED(result)) result = CreateStreamOnHGlobal(nullptr, TRUE, &stream);
  if (SUCCEEDED(result)) result = source_stream->Save(stream.Get(), FALSE);
  if (SUCCEEDED(result)) result = stream->Seek({}, STREAM_SEEK_SET, nullptr);
  if (SUCCEEDED(result))
    result = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&link));
  if (SUCCEEDED(result)) result = link.As(&destination_stream);
  if (SUCCEEDED(result)) result = destination_stream->Load(stream.Get());
  if (SUCCEEDED(result)) result = link.As(&file);
  return result;
}

bool SameExecutable(IShellLinkW* link, const std::wstring& executable) {
  std::array<wchar_t, 32768> target{};
  if (FAILED(link->GetPath(target.data(), static_cast<int>(target.size()),
                           nullptr, SLGP_RAWPATH)))
    return false;
  std::error_code error;
  return std::filesystem::equivalent(target.data(), executable, error) &&
         !error;
}
bool HasSelection(IShellLinkW* link, IPropertyStore* store,
                  const Identity& identity, int resource) {
  std::array<wchar_t, 32768> icon{};
  int index = 0;
  if (FAILED(link->GetIconLocation(icon.data(), static_cast<int>(icon.size()),
                                   &index)) ||
      index != -resource || identity.executable != icon.data()) {
    return false;
  }
  PROPVARIANT value{};
  const HRESULT result = store->GetValue(PKEY_AppUserModel_ID, &value);
  const bool matches = SUCCEEDED(result) && value.vt == VT_LPWSTR &&
                       value.pwszVal && identity.app_id == value.pwszVal;
  PropVariantClear(&value);
  return matches;
}
}  // namespace

HRESULT CurrentIdentity(Identity& identity) {
  std::array<wchar_t, 32768> executable{};
  const DWORD length = GetModuleFileNameW(
      nullptr, executable.data(), static_cast<DWORD>(executable.size()));
  if (!length || length == executable.size()) {
    return HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER);
  }
  identity.executable.assign(executable.data(), length);
  UINT32 size = 0;
  const LONG status = GetCurrentApplicationUserModelId(&size, nullptr);
  if (status == APPMODEL_ERROR_NO_APPLICATION) {
    // Install/build directories can coexist. Keep an identity stable across
    // icon changes and in-place upgrades without merging unrelated copies.
    std::uint64_t hash = 14695981039346656037ull;
    for (const wchar_t letter : identity.executable) {
      hash ^= static_cast<std::uint64_t>(towlower(letter));
      hash *= 1099511628211ull;
    }
    identity.app_id = L"BiliSail.Desktop.Install" + std::to_wstring(hash);
    identity.packaged = false;
    return S_OK;
  }
  if (status != ERROR_INSUFFICIENT_BUFFER) return HRESULT_FROM_WIN32(status);
  std::vector<wchar_t> app_id(size);
  const LONG read = GetCurrentApplicationUserModelId(&size, app_id.data());
  if (read != ERROR_SUCCESS) return HRESULT_FROM_WIN32(read);
  identity.app_id = app_id.data();
  identity.packaged = true;
  return S_OK;
}

HRESULT ApplyToWindow(HWND window, const Identity& identity, int resource) {
  ComPtr<IPropertyStore> store;
  HRESULT result = SHGetPropertyStoreForWindow(window, IID_PPV_ARGS(&store));
  if (FAILED(result)) return result;
  const std::wstring icon =
      identity.executable + L",-" + std::to_wstring(resource);
  result = SetString(store.Get(), PKEY_AppUserModel_RelaunchIconResource, icon);
  if (FAILED(result)) return result;
  if (!identity.packaged) {
    result = SetString(store.Get(), PKEY_AppUserModel_RelaunchCommand,
                       L"\"" + identity.executable + L"\"");
    if (SUCCEEDED(result)) {
      result =
          SetString(store.Get(), PKEY_AppUserModel_RelaunchDisplayNameResource,
                    L"BiliSail");
    }
    if (FAILED(result)) return result;
  }
  // Documented refresh point: set the ID after the relaunch properties, even
  // when it hasn't changed. Never change identity just to invalidate an icon.
  return SetString(store.Get(), PKEY_AppUserModel_ID, identity.app_id);
}

HRESULT UpdateStartMenu(const Identity& identity, int resource,
                        const std::filesystem::path& user_programs,
                        const std::filesystem::path& common_programs) {
  if (identity.packaged) return S_FALSE;
  const auto destination = user_programs / kShortcut;
  const auto common = common_programs / kShortcut;
  std::error_code error;
  const bool user_exists = std::filesystem::exists(destination, error);
  if (error) return HRESULT_FROM_WIN32(error.value());
  const auto source = user_exists ? destination : common;
  if (!std::filesystem::exists(source, error)) {
    return error ? HRESULT_FROM_WIN32(error.value()) : S_FALSE;
  }
  ComPtr<IShellLinkW> link;
  ComPtr<IPersistFile> file;
  HRESULT result = LoadShortcut(source, link, file);
  if (FAILED(result)) return result;
  // A development build must not retarget an installed application's entry.
  if (!SameExecutable(link.Get(), identity.executable)) return S_FALSE;
  ComPtr<IPropertyStore> store;
  result = link.As(&store);
  if (FAILED(result)) return result;
  // Launch restoration should not rewrite the same link or churn Shell caches.
  if (user_exists &&
      HasSelection(link.Get(), store.Get(), identity, resource)) {
    return S_OK;
  }
  result = link->SetIconLocation(identity.executable.c_str(), -resource);
  if (SUCCEEDED(result))
    result = SetString(store.Get(), PKEY_AppUserModel_ID, identity.app_id);
  if (SUCCEEDED(result)) result = store->Commit();
  if (FAILED(result)) return result;
  std::filesystem::create_directories(destination.parent_path(), error);
  if (error) return HRESULT_FROM_WIN32(error.value());
  // Publish a complete Shell link. An interrupted or failed save must not
  // truncate an existing Start menu entry.
  const auto temporary =
      std::filesystem::path(destination.wstring() + L"." +
                            std::to_wstring(GetCurrentProcessId()) + L".tmp");
  result = file->Save(temporary.c_str(), FALSE);
  if (SUCCEEDED(result) &&
      !MoveFileExW(temporary.c_str(), destination.c_str(),
                   MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    result = HRESULT_FROM_WIN32(GetLastError());
  }
  std::filesystem::remove(temporary, error);
  if (FAILED(result)) return result;
  SHChangeNotify(user_exists ? SHCNE_UPDATEITEM : SHCNE_CREATE,
                 SHCNF_PATHW | SHCNF_FLUSHNOWAIT, destination.c_str(), nullptr);
  return S_OK;
}

HRESULT UpdateStartMenu(const Identity& identity, int resource) {
  if (identity.packaged) return S_FALSE;
  std::filesystem::path user, common;
  HRESULT result = Programs(FOLDERID_Programs, user);
  if (SUCCEEDED(result)) result = Programs(FOLDERID_CommonPrograms, common);
  return FAILED(result) ? result
                        : UpdateStartMenu(identity, resource, user, common);
}
}  // namespace shell_app_icon
