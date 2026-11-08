// Exercise the production resize and descriptor callbacks with real ANGLE/D3D11
// resources and a controlled Flutter registrar. No Flutter process is needed.
#include <flutter/texture_registrar.h>

#include <atomic>
#include <algorithm>
#include <chrono>
#include <functional>
#include <iostream>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <thread>
#include <unordered_map>

#include "angle_surface_manager.h"
#include <GLES2/gl2.h>
#include <client.h>
#include <render.h>
#include <render_gl.h>

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// Resize's render-context branch is covered by the Flutter integration test.
int mpv_render_context_render(mpv_render_context*, mpv_render_param*) { return 0; }

struct Registrar {
  Registrar* texture_registrar() { return this; }
  int64_t RegisterTexture(flutter::TextureVariant* value) {
    variant = value;
    return ++registrations;
  }
  void MarkTextureFrameAvailable(int64_t) {}
  int64_t registrations = 0;
  flutter::TextureVariant* variant = nullptr;
};

class VideoOutput {
 public:
  VideoOutput(Registrar& registrar, bool hardware) : registrar_(&registrar) {
    if (hardware) {
      surface_manager_ = std::make_unique<ANGLESurfaceManager>(320, 180);
    } else {
      pixel_buffer_ = std::make_unique<uint8_t[]>(640 * 360 * 4);
    }
  }
  void Resize(int64_t width, int64_t height);

  std::mutex textures_mutex_;
  std::unique_ptr<ANGLESurfaceManager> surface_manager_;
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
  mpv_render_context* render_context_ = nullptr;
  int64_t texture_id_ = 0;
  Registrar* registrar_;
  std::atomic<bool> destroyed_{false};
  std::function<void(int64_t, int64_t, int64_t)> texture_update_callback_ =
      [](int64_t, int64_t, int64_t) {};
};

#include "video_output_resize.inc"

void SubmitFrame(ANGLESurfaceManager& renderer) {
  renderer.Draw([] {
    glClearColor(0, 1, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
  });
}

const FlutterDesktopGpuSurfaceDescriptor* WaitDescriptor(
    const flutter::GpuSurfaceTexture& callback, size_t width, size_t height) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  do {
    const auto* descriptor = callback.ObtainDescriptor(width, height);
    if (descriptor && descriptor->visible_width == width) return descriptor;
    if (descriptor) descriptor->release_callback(descriptor->release_context);
    std::this_thread::yield();
  } while (std::chrono::steady_clock::now() < deadline);
  throw std::runtime_error("GPU descriptor did not complete");
}

void HardwareDescriptorsSurviveReleaseAndResize() {
  Registrar registrar;
  VideoOutput output(registrar, true);
  output.Resize(320, 180);
  const auto& callback =
      std::get<flutter::GpuSurfaceTexture>(*registrar.variant);
  SubmitFrame(*output.surface_manager_);
  const auto* descriptor = WaitDescriptor(callback, 320, 180);
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
    SubmitFrame(*output.surface_manager_);
    descriptor = WaitDescriptor(callback, width, width * 9 / 16);
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
  const auto* snapshot = descriptor->buffer;
  output.pixel_buffer_[0] = 123;
  Require(snapshot[0] == 0, "software producer modified a delivered frame");
  descriptor->release_callback(descriptor->release_context);
  output.Resize(640, 360);
  Require(descriptor->width == 320,
          "software resize invalidated in-flight callback metadata");
  descriptor = callback.CopyPixelBuffer(640, 360);
  Require(descriptor && descriptor->width == 640,
          "software resize not published");
  Require(registrar.registrations == 1, "software resize replaced texture ID");
  descriptor->release_callback(descriptor->release_context);
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
