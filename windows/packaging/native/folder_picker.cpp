#include <windows.h>
#include <commctrl.h>
#include <msiquery.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <BootstrapperApplicationTypes.h>
#include <BAFunctions.h>

#include <filesystem>
#include <memory>
#include <new>
#include <string>
#include <system_error>

namespace {
using Microsoft::WRL::ComPtr;

class ComApartment final {
 public:
  ComApartment() noexcept
      : result_(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED |
                                           COINIT_DISABLE_OLE1DDE)) {}
  ~ComApartment() { if (SUCCEEDED(result_)) CoUninitialize(); }
  ComApartment(const ComApartment&) = delete;
  ComApartment& operator=(const ComApartment&) = delete;
  HRESULT result() const noexcept { return result_; }

 private:
  const HRESULT result_;
};

struct TaskMemoryDeleter {
  void operator()(wchar_t* value) const noexcept { CoTaskMemFree(value); }
};

std::filesystem::path ExistingParent(std::filesystem::path path) {
  while (!path.empty()) {
    std::error_code error;
    if (std::filesystem::is_directory(path, error)) return path;
    const auto parent = path.parent_path();
    if (parent == path) break;
    path = parent;
  }
  return {};
}

HRESULT ChooseFolder(HWND owner, const std::wstring& current,
                     std::wstring& selected) {
  const ComApartment apartment;
  if (FAILED(apartment.result())) return apartment.result();
  ComPtr<IFileOpenDialog> dialog;
  auto result = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
  if (FAILED(result)) return result;
  FILEOPENDIALOGOPTIONS options{};
  result = dialog->GetOptions(&options);
  if (FAILED(result)) return result;
  result = dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM |
                             FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR |
                             FOS_DONTADDTORECENT);
  if (FAILED(result)) return result;
  result = dialog->SetTitle(L"选择 BiliSail 哔帆的安装文件夹");
  if (FAILED(result)) return result;
  result = dialog->SetOkButtonLabel(L"选择此文件夹");
  if (FAILED(result)) return result;
  const auto initial = ExistingParent(current);
  if (!initial.empty()) {
    ComPtr<IShellItem> folder;
    result = SHCreateItemFromParsingName(initial.c_str(), nullptr,
                                        IID_PPV_ARGS(&folder));
    if (FAILED(result)) return result;
    result = dialog->SetFolder(folder.Get());
    if (FAILED(result)) return result;
  }
  result = dialog->Show(owner);
  if (FAILED(result)) return result;
  ComPtr<IShellItem> folder;
  result = dialog->GetResult(&folder);
  if (FAILED(result)) return result;
  wchar_t* raw_path = nullptr;
  result = folder->GetDisplayName(SIGDN_FILESYSPATH, &raw_path);
  const std::unique_ptr<wchar_t, TaskMemoryDeleter> path(raw_path);
  if (FAILED(result)) return result;
  selected = path.get();
  return S_OK;
}

void ShowPickerError(HWND owner) noexcept {
  MessageBoxW(owner, L"无法打开文件夹选择器。请重试，或直接输入安装路径。",
              L"BiliSail 哔帆", MB_OK | MB_ICONERROR);
}

std::wstring WindowText(HWND window) {
  const auto length = GetWindowTextLengthW(window);
  std::wstring text(static_cast<size_t>(length) + 1, L'\0');
  const auto copied = GetWindowTextW(window, text.data(), length + 1);
  text.resize(static_cast<size_t>(copied));
  return text;
}

struct PickerState { HWND folder_edit = nullptr; };
// WiX's destroy ABI has no context parameter; this owns the one BA instance.
std::unique_ptr<PickerState> picker_state;

HRESULT WINAPI OnBAFunction(BA_FUNCTIONS_MESSAGE message, const LPVOID arguments,
                           LPVOID results, LPVOID context) noexcept {
  try {
    if (!context || !arguments || !results) return E_INVALIDARG;
    auto& state = *static_cast<PickerState*>(context);
    if (message == BA_FUNCTIONS_MESSAGE_ONTHEMELOADED) return S_OK;
    if (message == BA_FUNCTIONS_MESSAGE_ONTHEMECONTROLLOADED) {
      const auto& loaded = *static_cast<const BA_FUNCTIONS_ONTHEMECONTROLLOADED_ARGS*>(arguments);
      if (loaded.wzName && std::wstring(loaded.wzName) == L"InstallFolder") {
        state.folder_edit = loaded.hWnd;
      }
      return S_OK;
    }
    if (message != BA_FUNCTIONS_MESSAGE_ONTHEMECONTROLWMCOMMAND) return E_NOTIMPL;
    const auto& command = *static_cast<const BA_FUNCTIONS_ONTHEMECONTROLWMCOMMAND_ARGS*>(arguments);
    if (!command.wzName || std::wstring(command.wzName) != L"BiliSailBrowseButton" ||
        HIWORD(command.wParam) != BN_CLICKED) return E_NOTIMPL;
    auto& handled = *static_cast<BA_FUNCTIONS_ONTHEMECONTROLWMCOMMAND_RESULTS*>(results);
    handled.fProcessed = TRUE;
    handled.lResult = 0;
    const auto owner = GetAncestor(command.hWnd, GA_ROOT);
    if (!IsWindow(state.folder_edit)) { ShowPickerError(owner); return S_OK; }
    std::wstring selected;
    const auto result = ChooseFolder(owner, WindowText(state.folder_edit), selected);
    if (SUCCEEDED(result)) {
      // Only edit the page draft: WiX saves it on Save and discards it on Back.
      SetWindowTextW(state.folder_edit, selected.c_str());
    } else if (result != HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
      ShowPickerError(owner);
    }
    return S_OK;
  } catch (const std::bad_alloc&) {
    return E_OUTOFMEMORY;
  }
}

std::wstring MsiProperty(MSIHANDLE install, const wchar_t* name) {
  DWORD length = 0;
  wchar_t empty = L'\0';
  auto result = MsiGetPropertyW(install, name, &empty, &length);
  if (result != ERROR_MORE_DATA && result != ERROR_SUCCESS) return {};
  std::wstring value(static_cast<size_t>(length) + 1, L'\0');
  ++length;
  result = MsiGetPropertyW(install, name, value.data(), &length);
  if (result != ERROR_SUCCESS) return {};
  value.resize(length);
  return value;
}
}  // namespace

extern "C" __declspec(dllexport) HRESULT WINAPI BAFunctionsCreate(
    const BA_FUNCTIONS_CREATE_ARGS* arguments,
    BA_FUNCTIONS_CREATE_RESULTS* results) noexcept {
  if (!arguments || !results || arguments->cbSize < sizeof(*arguments) ||
      results->cbSize < sizeof(*results) || picker_state) return E_INVALIDARG;
  try {
    picker_state = std::make_unique<PickerState>();
    results->pfnBAFunctionsProc = OnBAFunction;
    results->pvBAFunctionsProcContext = picker_state.get();
    return S_OK;
  } catch (const std::bad_alloc&) { return E_OUTOFMEMORY; }
}

extern "C" __declspec(dllexport) void WINAPI BAFunctionsDestroy(
    const BA_FUNCTIONS_DESTROY_ARGS*, BA_FUNCTIONS_DESTROY_RESULTS*) noexcept {
  picker_state.reset();
}

extern "C" __declspec(dllexport) UINT WINAPI ChooseInstallFolder(
    MSIHANDLE install) noexcept {
  try {
    MsiSetPropertyW(install, L"BILISAIL_FOLDER_PICKED", L"0");
    std::wstring selected;
    const auto owner = GetActiveWindow();
    const auto result = ChooseFolder(owner, MsiProperty(install, L"INSTALLFOLDER"), selected);
    if (SUCCEEDED(result)) {
      if (MsiSetPropertyW(install, L"INSTALLFOLDER", selected.c_str()) != ERROR_SUCCESS)
        return ERROR_INSTALL_FAILURE;
      return MsiSetPropertyW(install, L"BILISAIL_FOLDER_PICKED", L"1");
    }
    if (result != HRESULT_FROM_WIN32(ERROR_CANCELLED)) ShowPickerError(owner);
    return ERROR_SUCCESS;
  } catch (const std::bad_alloc&) { return ERROR_OUTOFMEMORY; }
}
