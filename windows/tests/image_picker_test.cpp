#include "../runner/image_picker.h"

#include <flutter/encodable_value.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <objbase.h>

#include <chrono>
#include <iostream>
#include <stdexcept>
#include <utility>

#include "../runner/image_picker_channel.h"

namespace {
void Check(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

void PumpUntil(const std::function<bool()>& done) {
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (!done()) {
    Check(std::chrono::steady_clock::now() < deadline,
          "Native picker test timed out");
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 5, QS_ALLINPUT);
  }
}

struct State {
  HWND owner = nullptr;
  DWORD thread = 0;
  DWORD release_thread = 0;
  APTTYPE apartment = APTTYPE_CURRENT;
  HRESULT show_status = S_OK;
  HRESULT read_status = S_OK;
  bool wait = false;
  std::atomic<bool> entered{false};
  std::atomic<bool> complete{false};
  std::atomic<bool> cancelled{false};
  std::vector<std::string> paths{u8"C:\\\u56fe\u7247\\first.png",
                                 "C:\\second.gif"};
};

class FakeDialog final : public image_picker::Dialog {
 public:
  explicit FakeDialog(State& state) : state_(state) {}
  ~FakeDialog() override { state_.release_thread = GetCurrentThreadId(); }
  HRESULT Show(HWND owner) override {
    state_.owner = owner;
    state_.thread = GetCurrentThreadId();
    APTTYPEQUALIFIER qualifier;
    Check(SUCCEEDED(CoGetApartmentType(&state_.apartment, &qualifier)),
          "COM missing");
    state_.entered.store(true);
    if (state_.wait) {
      // Exercise cross-thread modal owner messages, including during teardown.
      SendMessageW(owner, WM_NULL, 0, 0);
      while (!state_.cancelled.load() && !state_.complete.load()) {
        MSG message{};
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
          TranslateMessage(&message);
          DispatchMessageW(&message);
        }
        MsgWaitForMultipleObjects(0, nullptr, FALSE, 5, QS_ALLINPUT);
      }
    }
    return state_.cancelled.load() ? HRESULT_FROM_WIN32(ERROR_CANCELLED)
                                   : state_.show_status;
  }
  HRESULT ReadPaths(std::vector<std::string>& paths) override {
    paths = state_.paths;
    return state_.read_status;
  }
  void Cancel() noexcept override { state_.cancelled.store(true); }

 private:
  State& state_;
};

class Messenger final : public flutter::BinaryMessenger {
 public:
  using Value = flutter::EncodableValue;
  struct Reply {
    bool done = false;
    bool success = false;
    std::string code;
    Value value;
    DWORD thread = 0;
  };
  void Send(const std::string&, const uint8_t*, size_t,
            flutter::BinaryReply = nullptr) const override {}
  void SetMessageHandler(const std::string&,
                         flutter::BinaryMessageHandler handler) override {
    handler_ = std::move(handler);
  }
  void Call(const Value& arguments, Reply& reply,
            const std::string& method = "pickImages") {
    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    const auto data = codec.EncodeMethodCall(
        flutter::MethodCall<Value>(method, std::make_unique<Value>(arguments)));
    handler_(data->data(), data->size(),
             [&reply, &codec](const uint8_t* bytes, size_t size) {
               flutter::MethodResultFunctions<Value> result(
                   [&reply](const Value* value) {
                     reply.success = true;
                     if (value) reply.value = *value;
                   },
                   [&reply](const std::string& code, const std::string&,
                            const Value*) { reply.code = code; },
                   [&reply] { reply.code = "not_implemented"; });
               Check(
                   codec.DecodeAndProcessResponseEnvelope(bytes, size, &result),
                   "Invalid reply");
               reply.done = true;
               reply.thread = GetCurrentThreadId();
             });
  }
  bool registered() const { return static_cast<bool>(handler_); }

 private:
  flutter::BinaryMessageHandler handler_;
};

flutter::EncodableValue View(int64_t id) {
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("viewId"), flutter::EncodableValue(id)}});
}

void TestRequests(HWND main_window, HWND playback) {
  const auto resolver = [=](int64_t id) {
    return id == 100 ? playback : main_window;
  };
  Check(image_picker::ResolveOwner(resolver, 100) == playback,
        "Playback owner lost");
  Check(image_picker::ResolveOwner(resolver, 0) == main_window,
        "Main owner lost");
  Check(!image_picker::ResolveOwner({}, 100),
        "Missing resolver used main window");
  const HWND child =
      CreateWindowExW(0, L"STATIC", L"", WS_CHILD, 0, 0, 1, 1, playback,
                      nullptr, GetModuleHandleW(nullptr), nullptr);
  Check(image_picker::ResolveOwner([=](int64_t) { return child; }, 100) ==
            playback,
        "Flutter child view was not resolved to its top-level window");
  DestroyWindow(child);
  for (const HRESULT status :
       {S_OK, E_FAIL, HRESULT_FROM_WIN32(ERROR_CANCELLED)}) {
    State state;
    state.show_status = status;
    image_picker::Request request(
        playback, [&] { return std::make_unique<FakeDialog>(state); });
    PumpUntil([&] { return request.finished(); });
    Check(state.owner == playback, "Wrong modal owner");
    Check(
        state.thread != GetCurrentThreadId() && state.apartment == APTTYPE_STA,
        "Shell dialog must run on its own STA");
    Check(state.release_thread == state.thread,
          "COM object released on another thread");
    Check(request.selection().status == status, "Show error changed");
    Check(request.selection().paths ==
              (status == S_OK ? state.paths : std::vector<std::string>{}),
          "Cancellation/failure returned partial success");
  }
  {
    State state;
    state.read_status = E_ACCESSDENIED;
    image_picker::Request request(
        playback, [&] { return std::make_unique<FakeDialog>(state); });
    PumpUntil([&] { return request.finished(); });
    Check(request.selection().status == E_ACCESSDENIED &&
              request.selection().paths.empty(),
          "Read failure leaked paths");
  }
  {
    image_picker::Request request(
        playback, []() -> std::unique_ptr<image_picker::Dialog> {
          throw std::runtime_error("creation failed");
        });
    PumpUntil([&] { return request.finished(); });
    Check(FAILED(request.selection().status),
          "Factory failure was not contained");
  }
  {
    State state;
    state.wait = true;
    auto request = std::make_unique<image_picker::Request>(
        playback, [&] { return std::make_unique<FakeDialog>(state); });
    PumpUntil([&] { return state.entered.load(); });
    request.reset();
    Check(state.cancelled.load() && state.release_thread == state.thread,
          "Teardown did not cancel and join the dialog STA");
  }
}

void TestChannel(HWND main_window, HWND playback) {
  State state;
  state.wait = true;
  bool playback_open = true;
  Messenger messenger;
  {
    ImagePickerChannel channel(
        &messenger,
        [&](int64_t id) {
          return id == 100 ? (playback_open ? playback : nullptr)
                 : id == 0 ? main_window
                           : nullptr;
        },
        [&] { return std::make_unique<FakeDialog>(state); });
    for (const auto args :
         {flutter::EncodableValue(), flutter::EncodableValue("100")}) {
      Messenger::Reply reply;
      messenger.Call(args, reply);
      Check(reply.done && reply.code == "invalid_argument",
            "Invalid view accepted");
    }
    Messenger::Reply missing;
    messenger.Call(View(999), missing);
    Check(missing.code == "window_unavailable",
          "Missing view fell back to main");
    Messenger::Reply first, duplicate;
    messenger.Call(View(100), first);
    messenger.Call(View(0), duplicate);
    Check(!first.done && duplicate.code == "picker_busy",
          "Reentrant picker accepted");
    PumpUntil([&] { return state.entered.load(); });
    Check(state.owner == playback, "Channel resolved the implicit view");
    state.complete.store(true);
    PumpUntil([&] { return first.done; });
    Check(first.success &&
              std::get<flutter::EncodableList>(first.value).size() == 2,
          "Image paths missing");
    Check(first.thread == GetCurrentThreadId(),
          "Flutter reply escaped platform thread");
    state.wait = false;
    for (const HRESULT status :
         {HRESULT_FROM_WIN32(ERROR_CANCELLED), E_ACCESSDENIED}) {
      state.show_status = status;
      Messenger::Reply reply;
      messenger.Call(View(100), reply);
      PumpUntil([&] { return reply.done; });
      Check(status == E_ACCESSDENIED
                ? reply.code == "picker_failed"
                : reply.success &&
                      std::get<flutter::EncodableList>(reply.value).empty(),
            "Channel confused errors and cancellation");
    }
    state.show_status = S_OK;
    state.wait = true;
    state.entered.store(false);
    state.complete.store(false);
    Messenger::Reply closed;
    messenger.Call(View(100), closed);
    PumpUntil([&] { return state.entered.load(); });
    playback_open = false;
    PumpUntil([&] { return closed.done; });
    Check(closed.code == "window_unavailable" && state.cancelled.load(),
          "Closed view selection was not cancelled");
  }
  Check(!messenger.registered(), "Destroyed channel retained its callback");
  {
    State pending;
    pending.wait = true;
    Messenger::Reply reply;
    auto channel = std::make_unique<ImagePickerChannel>(
        &messenger, [=](int64_t) { return playback; },
        [&] { return std::make_unique<FakeDialog>(pending); });
    messenger.Call(View(100), reply);
    PumpUntil([&] { return pending.entered.load(); });
    channel.reset();
    Check(reply.done && reply.code == "window_unavailable" &&
              pending.cancelled.load() && !messenger.registered(),
          "Engine teardown retained a dialog, reply or messenger callback");
  }
}
}  // namespace

int main() {
  const HRESULT apartment = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const HWND main_window =
      CreateWindowExW(0, L"STATIC", L"", 0, 0, 0, 1, 1, nullptr, nullptr,
                      GetModuleHandleW(nullptr), nullptr);
  const HWND playback =
      CreateWindowExW(0, L"STATIC", L"", 0, 0, 0, 1, 1, nullptr, nullptr,
                      GetModuleHandleW(nullptr), nullptr);
  try {
    Check(main_window && playback, "Test windows unavailable");
    TestRequests(main_window, playback);
    TestChannel(main_window, playback);
    DestroyWindow(playback);
    DestroyWindow(main_window);
    if (SUCCEEDED(apartment)) CoUninitialize();
    std::cout << "Native image picker tests passed\n";
    return 0;
  } catch (const std::exception& error) {
    DestroyWindow(playback);
    DestroyWindow(main_window);
    if (SUCCEEDED(apartment)) CoUninitialize();
    std::cerr << error.what() << '\n';
    return 1;
  }
}
