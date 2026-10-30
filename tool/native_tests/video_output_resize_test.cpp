// Exercise the production resize and descriptor callbacks with real D3D11
// resources and a controlled Flutter registrar. No Flutter process is needed.
#include <flutter/texture_registrar.h>

#include <atomic>
#include <functional>
#include <iostream>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <unordered_map>

#include "d3d11_renderer.h"

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// Resize's render-context branch is covered by the Flutter integration test.
void mpv_render_context_render(void*, void*) {}
void mpv_render_context_report_swap(void*) {}

struct Registrar {
  Registrar* texture_registrar() { return this; }
  int64_t RegisterTexture(flutter::TextureVariant* value) {
    variant = value;
    return ++registrations;
  }
  int64_t registrations = 0;
  flutter::TextureVariant* variant = nullptr;
};

class VideoOutput {
 public:
  VideoOutput(Registrar& registrar, bool hardware) : registrar_(&registrar) {
    if (hardware) {
      d3d11_renderer_ = std::make_unique<D3D11Renderer>(320, 180);
    } else {
      pixel_buffer_ = std::make_unique<uint8_t[]>(640 * 360 * 4);
    }
  }
  void Resize(int64_t width, int64_t height);

  std::mutex textures_mutex_;
  std::unique_ptr<D3D11Renderer> d3d11_renderer_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> last_video_texture_;
  HANDLE last_video_handle_ = nullptr;
  FlutterDesktopPixelBuffer last_pixel_buffer_{};
  std::unique_ptr<uint8_t[]> pixel_buffer_;
  std::unordered_map<int64_t, std::unique_ptr<FlutterDesktopPixelBuffer>>
      pixel_buffer_textures_;
  std::unordered_map<int64_t,
                     std::unique_ptr<FlutterDesktopGpuSurfaceDescriptor>>
      textures_;
  std::unordered_map<int64_t, std::unique_ptr<flutter::TextureVariant>>
      texture_variants_;
  void* render_context_ = nullptr;
  int64_t texture_id_ = 0;
  Registrar* registrar_;
  std::atomic<bool> destroyed_{false};
  std::function<void(int64_t, int64_t, int64_t)> texture_update_callback_ =
      [](int64_t, int64_t, int64_t) {};
};

#include "video_output_resize.inc"

void SubmitFrame(D3D11Renderer& renderer) {
  Microsoft::WRL::ComPtr<ID3D11Texture2D> target;
  Require(SUCCEEDED(renderer.swap_chain()->GetBuffer(0, IID_PPV_ARGS(&target))),
          "render target unavailable");
  Microsoft::WRL::ComPtr<ID3D11RenderTargetView> view;
  Require(SUCCEEDED(renderer.device()->CreateRenderTargetView(target.Get(),
                                                              nullptr, &view)),
          "render target view unavailable");
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context;
  renderer.device()->GetImmediateContext(&context);
  constexpr float green[]{0, 1, 0, 1};
  context->ClearRenderTargetView(view.Get(), green);
  renderer.ProducerCommit();
}

void HardwareDescriptorsSurviveReleaseAndResize() {
  Registrar registrar;
  VideoOutput output(registrar, true);
  output.Resize(320, 180);
  const auto& callback =
      std::get<flutter::GpuSurfaceTexture>(*registrar.variant);
  SubmitFrame(*output.d3d11_renderer_);
  const auto* descriptor = callback.ObtainDescriptor(320, 180);
  Require(descriptor && descriptor->handle, "no completed GPU descriptor");
  for (const auto width : {640, 256, 960, 320}) {
    const auto old_width = descriptor->visible_width;
    // Mirrors Flutter's ExternalTextureD3d: release the resource lease before
    // reading visible dimensions from the returned descriptor.
    descriptor->release_callback(descriptor->release_context);
    Require(descriptor->visible_width == old_width,
            "resource release invalidated the descriptor");
    output.Resize(width, width * 9 / 16);
    Require(descriptor->visible_width == old_width,
            "producer resize invalidated in-flight callback metadata");
    const auto* fallback = callback.ObtainDescriptor(width, width * 9 / 16);
    Require(
        fallback && fallback->visible_width == old_width,
        "resize exposed an unpainted mailbox instead of the previous frame");
    fallback->release_callback(fallback->release_context);
    SubmitFrame(*output.d3d11_renderer_);
    descriptor = callback.ObtainDescriptor(width, width * 9 / 16);
    Require(
        descriptor && descriptor->visible_width == static_cast<size_t>(width),
        "completed resize was not published");
    Require(registrar.registrations == 1 && output.texture_id_ == 1,
            "resize replaced the registered Flutter texture");
  }
  descriptor->release_callback(descriptor->release_context);
}

void SoftwareDescriptorsSurviveResize() {
  Registrar registrar;
  VideoOutput output(registrar, false);
  output.Resize(320, 180);
  const auto& callback =
      std::get<flutter::PixelBufferTexture>(*registrar.variant);
  const auto* descriptor = callback.CopyPixelBuffer(320, 180);
  Require(descriptor && descriptor->width == 320, "no software descriptor");
  output.Resize(640, 360);
  Require(descriptor->width == 320,
          "software resize invalidated in-flight callback metadata");
  descriptor = callback.CopyPixelBuffer(640, 360);
  Require(descriptor && descriptor->width == 640,
          "software resize not published");
  Require(registrar.registrations == 1, "software resize replaced texture ID");
}

int main() {
  try {
    HardwareDescriptorsSurviveReleaseAndResize();
    SoftwareDescriptorsSurviveResize();
    std::cout << "PASS: stable texture IDs, descriptor lifetime and resize "
                 "fallback\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
