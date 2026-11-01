// BiliSail GPU delivery for PiliPlus media_kit_video fd8421d. See LICENSE and README.md.
// Draw and copy share ANGLE's D3D11 immediate context whenever available.
namespace {
ID3D11Device *BiliSailAngleDevice(EGLDisplay display) {
  static const auto query_display =
      reinterpret_cast<PFNEGLQUERYDISPLAYATTRIBEXTPROC>(
          eglGetProcAddress("eglQueryDisplayAttribEXT"));
  static const auto query_device =
      reinterpret_cast<PFNEGLQUERYDEVICEATTRIBEXTPROC>(
          eglGetProcAddress("eglQueryDeviceAttribEXT"));
  EGLAttrib device = 0;
  EGLAttrib d3d_device = 0;
  if (display == EGL_NO_DISPLAY || query_display == nullptr ||
      query_device == nullptr ||
      query_display(display, EGL_DEVICE_EXT, &device) != EGL_TRUE ||
      query_device(reinterpret_cast<EGLDeviceEXT>(device),
                   EGL_D3D11_DEVICE_ANGLE, &d3d_device) != EGL_TRUE) {
    return nullptr;
  }
  return reinterpret_cast<ID3D11Device *>(d3d_device);
}

class BiliSailMutexLock {
public:
  explicit BiliSailMutexLock(HANDLE mutex) : mutex_(mutex) {
    const auto result = WaitForSingleObject(mutex_, INFINITE);
    if (result != WAIT_OBJECT_0 && result != WAIT_ABANDONED) {
      throw std::runtime_error("Unable to lock video GPU commands.");
    }
  }
  ~BiliSailMutexLock() { ReleaseMutex(mutex_); }
  BiliSailMutexLock(const BiliSailMutexLock &) = delete;
  BiliSailMutexLock &operator=(const BiliSailMutexLock &) = delete;

private:
  HANDLE mutex_;
};

class BiliSailCurrentGlScope {
public:
  explicit BiliSailCurrentGlScope(ANGLESurfaceManager &surface)
      : surface_(surface) {
    surface_.MakeCurrent(true);
  }
  ~BiliSailCurrentGlScope() { surface_.MakeCurrent(false); }
  BiliSailCurrentGlScope(const BiliSailCurrentGlScope &) = delete;
  BiliSailCurrentGlScope &operator=(const BiliSailCurrentGlScope &) = delete;

private:
  ANGLESurfaceManager &surface_;
};
} // namespace

bool ANGLESurfaceManager::UseAngleDevice() {
  auto *device = BiliSailAngleDevice(display_);
  if (device == nullptr)
    return false;
  Microsoft::WRL::ComPtr<ID3D10Multithread> multithread;
  if (FAILED(device->QueryInterface(IID_PPV_ARGS(&multithread))))
    return false;
  multithread->SetMultithreadProtected(TRUE);
  device->AddRef();
  d3d_11_device_ = device;
  device->GetImmediateContext(&d3d_11_device_context_);
  uses_angle_device_ = true;
  return true;
}

void ANGLESurfaceManager::Draw(std::function<void()> callback) {
  const BiliSailMutexLock lock(mutex_);
  const BiliSailCurrentGlScope current(*this);
  callback();
  SwapBuffers();
  ++draw_revision_;
  has_frame_ = true;
}

HANDLE ANGLESurfaceManager::Read() {
  const BiliSailMutexLock lock(mutex_);
  // The callback runs with Flutter's current GL context. Direct delivery is
  // valid only on the very same D3D11 device, not merely the same GPU adapter.
  // Producer glFlush submits the render before this consumer's sample. Both
  // accesses then use one ordered immediate-context command stream; the driver
  // tracks the shared resource's read/write hazards without a CPU GPU wait.
  const bool direct =
      uses_angle_device_ &&
      BiliSailAngleDevice(eglGetCurrentDisplay()) == d3d_11_device_;
  if (!last_direct_.has_value() || *last_direct_ != direct) {
    std::cout << "media_kit: GPU delivery: "
              << (direct ? "same-device" : "copied") << std::endl;
    last_direct_ = direct;
  }
  if (direct)
    return internal_handle_;
  // Keep a separate consumer texture for different devices and legacy ANGLE.
  // Repeated requests for an unchanged frame do not resubmit the same copy.
  if (d3d_11_device_context_ != nullptr && copied_revision_ != draw_revision_) {
    d3d_11_device_context_->CopyResource(d3d_11_texture_2D_.Get(),
                                         internal_d3d_11_texture_2D_.Get());
    d3d_11_device_context_->Flush();
    copied_revision_ = draw_revision_;
  }
  return handle_;
}

void ANGLESurfaceManager::SwapBuffers() {
  if (uses_angle_device_) {
    // GL rendering and the fallback CopyResource now use the same device and
    // immediate context. Submit in order instead of waiting for GPU completion.
    glFlush();
  } else {
    // A legacy producer on another device still needs the original barrier.
    glFinish();
  }
}
