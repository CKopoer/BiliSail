#ifndef RUNNER_IMAGE_PICKER_H_
#define RUNNER_IMAGE_PICKER_H_

#include <windows.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace image_picker {

struct Selection {
  HRESULT status = E_FAIL;
  std::vector<std::string> paths;
};

// Created, used and released on the request's STA, including cancellation.
class Dialog {
 public:
  virtual ~Dialog() = default;
  virtual HRESULT Show(HWND owner) = 0;
  virtual HRESULT ReadPaths(std::vector<std::string>& paths) = 0;
  virtual void Cancel() noexcept = 0;
};

std::unique_ptr<Dialog> CreateImageDialog();
HWND ResolveOwner(const std::function<HWND(int64_t)>& resolve_view,
                  int64_t view_id);

class Request final {
 public:
  using Factory = std::function<std::unique_ptr<Dialog>()>;
  explicit Request(HWND owner, Factory factory = CreateImageDialog);
  ~Request();
  Request(const Request&) = delete;
  Request& operator=(const Request&) = delete;

  void Cancel() noexcept;
  bool finished() const noexcept { return finished_.load(); }
  // Read only after finished(); the worker no longer touches the selection.
  const Selection& selection() const noexcept { return selection_; }

 private:
  void Run(HWND owner, const Factory& factory) noexcept;
  static LRESULT CALLBACK ControlProc(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam, UINT_PTR subclass_id,
                                      DWORD_PTR reference);
  std::atomic<bool> cancelled_{false};
  std::atomic<bool> finished_{false};
  std::atomic<HWND> control_{nullptr};
  HANDLE done_ = nullptr;
  std::thread worker_;
  // Only accessed by the worker, via its native message loop.
  std::unique_ptr<Dialog> dialog_;
  Selection selection_;
};

}  // namespace image_picker

#endif  // RUNNER_IMAGE_PICKER_H_
