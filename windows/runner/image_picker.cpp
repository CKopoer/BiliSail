#include "image_picker.h"

#include <commctrl.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <stdexcept>

namespace image_picker {
namespace {
const UINT kCancel = RegisterWindowMessageW(L"BiliSail.ImagePicker.Cancel");
constexpr HRESULT kCancelled = HRESULT_FROM_WIN32(ERROR_CANCELLED);
using Microsoft::WRL::ComPtr;

class Apartment final {
 public:
  Apartment()
      : status_(CoInitializeEx(
            nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE)) {}
  ~Apartment() {
    if (SUCCEEDED(status_)) CoUninitialize();
  }
  HRESULT status() const noexcept { return status_; }
  Apartment(const Apartment&) = delete;
  Apartment& operator=(const Apartment&) = delete;

 private:
  const HRESULT status_;
};

struct TaskMemoryDeleter {
  void operator()(wchar_t* value) const noexcept { CoTaskMemFree(value); }
};

class ShellDialog final : public Dialog {
 public:
  HRESULT Show(HWND owner) override {
    auto status =
        CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(&dialog_));
    if (FAILED(status)) return status;
    FILEOPENDIALOGOPTIONS options{};
    status = dialog_->GetOptions(&options);
    if (FAILED(status)) return status;
    status = dialog_->SetOptions(options | FOS_ALLOWMULTISELECT |
                                 FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST |
                                 FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR |
                                 FOS_DONTADDTORECENT | FOS_STRICTFILETYPES);
    if (FAILED(status)) return status;
    const COMDLG_FILTERSPEC filter{L"\u56fe\u7247 (JPG, PNG, GIF)",
                                   L"*.jpg;*.jpeg;*.png;*.gif"};
    status = dialog_->SetFileTypes(1, &filter);
    if (FAILED(status)) return status;
    status = dialog_->SetTitle(L"\u9009\u62e9\u56fe\u7247");
    return FAILED(status) ? status : dialog_->Show(owner);
  }

  HRESULT ReadPaths(std::vector<std::string>& paths) override {
    ComPtr<IShellItemArray> items;
    auto status = dialog_->GetResults(&items);
    if (FAILED(status)) return status;
    DWORD count = 0;
    status = items->GetCount(&count);
    if (FAILED(status)) return status;
    // Dynamic drafts have the largest attachment budget. Do not accumulate an
    // unbounded Shell selection before Dart validates the remaining slots.
    if (count == 0) return E_FAIL;
    if (count > 18) return HRESULT_FROM_WIN32(ERROR_BUFFER_OVERFLOW);
    for (DWORD index = 0; index < count; ++index) {
      ComPtr<IShellItem> item;
      status = items->GetItemAt(index, &item);
      if (FAILED(status)) return status;
      wchar_t* raw_path = nullptr;
      status = item->GetDisplayName(SIGDN_FILESYSPATH, &raw_path);
      const std::unique_ptr<wchar_t, TaskMemoryDeleter> path(raw_path);
      if (FAILED(status)) return status;
      if (!path || !*path) return E_FAIL;
      const int length =
          WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path.get(), -1,
                              nullptr, 0, nullptr, nullptr);
      if (length <= 1) return E_FAIL;
      std::string value(static_cast<size_t>(length), '\0');
      if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path.get(), -1,
                              value.data(), length, nullptr, nullptr) != length)
        return E_FAIL;
      value.pop_back();
      paths.push_back(std::move(value));
    }
    return S_OK;
  }

  void Cancel() noexcept override {
    // IFileDialog::Close is intended for dialog event callbacks. This request
    // receives cancellation through its own window proc, so close the dialog
    // HWND instead; do not call a COM dialog from the platform/owner thread.
    ComPtr<IOleWindow> native_window;
    HWND window = nullptr;
    if (dialog_ && SUCCEEDED(dialog_.As(&native_window)) &&
        SUCCEEDED(native_window->GetWindow(&window)) && IsWindow(window)) {
      PostMessageW(window, WM_CLOSE, 0, 0);
    }
  }

 private:
  ComPtr<IFileOpenDialog> dialog_;
};
}  // namespace

std::unique_ptr<Dialog> CreateImageDialog() {
  return std::make_unique<ShellDialog>();
}

HWND ResolveOwner(const std::function<HWND(int64_t)>& resolve_view,
                  int64_t view_id) {
  const HWND view = resolve_view ? resolve_view(view_id) : nullptr;
  if (!view || !IsWindow(view)) return nullptr;
  const HWND owner = GetAncestor(view, GA_ROOT);
  return owner && IsWindow(owner) ? owner : nullptr;
}

Request::Request(HWND owner, Factory factory)
    : done_(CreateEventW(nullptr, TRUE, FALSE, nullptr)) {
  if (!done_) throw std::runtime_error("Could not create image picker event");
  try {
    worker_ = std::thread([this, owner, factory = std::move(factory)] {
      Run(owner, factory);
      finished_.store(true);
      SetEvent(done_);
    });
  } catch (...) {
    CloseHandle(done_);
    throw;
  }
}

Request::~Request() {
  Cancel();
  // Show(owner) can synchronously send messages to the owner thread. Dispatch
  // sent messages while joining, without running queued Flutter timer/tasks.
  // The engine and owner still exist during the channel's teardown.
  while (MsgWaitForMultipleObjects(1, &done_, FALSE, INFINITE,
                                   QS_SENDMESSAGE) == WAIT_OBJECT_0 + 1) {
    MSG message{};
    PeekMessageW(&message, nullptr, 0, 0, PM_NOREMOVE);
  }
  worker_.join();
  CloseHandle(done_);
}

void Request::Cancel() noexcept {
  cancelled_.store(true);
  const HWND control = control_.load();
  if (control) PostMessageW(control, kCancel, 0, 0);
}

void Request::Run(HWND owner, const Factory& factory) noexcept {
  const Apartment apartment;
  selection_.status = apartment.status();
  if (FAILED(selection_.status)) return;
  const HWND control =
      CreateWindowExW(0, L"STATIC", L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
                      GetModuleHandleW(nullptr), nullptr);
  if (!control) {
    selection_.status = E_FAIL;
    return;
  }
  if (!SetWindowSubclass(control, ControlProc, 1,
                         reinterpret_cast<DWORD_PTR>(this))) {
    DestroyWindow(control);
    selection_.status = E_FAIL;
    return;
  }
  control_.store(control);
  try {
    if (cancelled_.load()) {
      selection_.status = kCancelled;
    } else if (!IsWindow(owner)) {
      selection_.status = HRESULT_FROM_WIN32(ERROR_INVALID_WINDOW_HANDLE);
    } else {
      dialog_ = factory();
      selection_.status = dialog_ ? dialog_->Show(owner) : E_FAIL;
    }
    if (selection_.status == S_OK) {
      selection_.status = dialog_->ReadPaths(selection_.paths);
    }
  } catch (...) {
    // Do not let Shell/COM adapter exceptions unwind out of a worker thread.
    selection_.status = E_FAIL;
  }
  if (cancelled_.load()) selection_.status = kCancelled;
  if (selection_.status != S_OK) selection_.paths.clear();
  dialog_.reset();
  control_.store(nullptr);
  RemoveWindowSubclass(control, ControlProc, 1);
  DestroyWindow(control);
}

LRESULT CALLBACK Request::ControlProc(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam, UINT_PTR,
                                      DWORD_PTR reference) {
  auto* self = reinterpret_cast<Request*>(reference);
  if (message == kCancel) {
    // Cancellation can arrive while COM creates the dialog, before Show starts
    // its modal loop. Retry on this STA until that loop has actually opened.
    SetTimer(window, 1, 30, nullptr);
    if (self->dialog_) self->dialog_->Cancel();
    return 0;
  }
  if (message == WM_TIMER && wparam == 1) {
    if (self->dialog_) self->dialog_->Cancel();
    return 0;
  }
  return DefSubclassProc(window, message, wparam, lparam);
}
}  // namespace image_picker
