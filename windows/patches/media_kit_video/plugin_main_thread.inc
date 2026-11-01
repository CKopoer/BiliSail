// BiliSail platform-thread delivery for the pinned MIT media-kit video plugin.
// A message-only HWND survives implicit-view replacement and works for every
// engine without replacing another plugin's WndProc or keeping a global owner.
void MediaKitVideoPlugin::InitializeMainThreadTasks() {
  static const ATOM registered = [] {
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = MainThreadWindowProc;
    window_class.hInstance = ::GetModuleHandle(nullptr);
    window_class.lpszClassName = L"BiliSail.MediaKitPlatformTasks";
    return ::RegisterClassW(&window_class);
  }();
  if (!registered) throw std::runtime_error("Cannot register video task window");
  platform_thread_ = ::GetCurrentThreadId();
  task_window_ = ::CreateWindowExW(0, L"BiliSail.MediaKitPlatformTasks", L"", 0,
                                  0, 0, 0, 0, HWND_MESSAGE, nullptr,
                                  ::GetModuleHandle(nullptr), this);
  if (!task_window_) throw std::runtime_error("Cannot create video task window");
}

LRESULT CALLBACK MediaKitVideoPlugin::MainThreadWindowProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* creation = reinterpret_cast<CREATESTRUCTW*>(lparam);
    ::SetWindowLongPtrW(window, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(creation->lpCreateParams));
  }
  auto* owner = reinterpret_cast<MediaKitVideoPlugin*>(
      ::GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == kMainThreadTaskMessage && owner) {
    std::queue<std::function<void()>> pending;
    {
      std::lock_guard<std::mutex> lock(owner->main_thread_tasks_mutex_);
      pending.swap(owner->main_thread_tasks_);
    }
    while (!pending.empty()) {
      auto task = std::move(pending.front());
      pending.pop();
      task();
    }
    return 0;
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

void MediaKitVideoPlugin::RunOnMainThread(std::function<void()> task) {
  if (::GetCurrentThreadId() == platform_thread_) {
    task();
    return;
  }
  {
    std::lock_guard<std::mutex> lock(main_thread_tasks_mutex_);
    main_thread_tasks_.push(std::move(task));
  }
  ::PostMessageW(task_window_, kMainThreadTaskMessage, 0, 0);
}
