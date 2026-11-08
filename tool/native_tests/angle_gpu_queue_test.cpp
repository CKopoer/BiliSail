// Exercise the patched production ANGLE implementation on a real D3D11 device.
// Readback is confined to this test's staging texture, never the player path.
#include "angle_surface_manager.h"

#include <array>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <thread>
#include <vector>

namespace {
void Require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

Microsoft::WRL::ComPtr<ID3D11Device> CurrentDevice() {
  const auto query_display = reinterpret_cast<PFNEGLQUERYDISPLAYATTRIBEXTPROC>(
      eglGetProcAddress("eglQueryDisplayAttribEXT"));
  const auto query_device = reinterpret_cast<PFNEGLQUERYDEVICEATTRIBEXTPROC>(
      eglGetProcAddress("eglQueryDeviceAttribEXT"));
  EGLAttrib device = 0;
  EGLAttrib d3d = 0;
  Require(query_display != nullptr && query_device != nullptr,
          "ANGLE device query is unavailable");
  Require(query_display(eglGetCurrentDisplay(), EGL_DEVICE_EXT, &device) ==
                  EGL_TRUE &&
              query_device(reinterpret_cast<EGLDeviceEXT>(device),
                           EGL_D3D11_DEVICE_ANGLE, &d3d) == EGL_TRUE,
          "Cannot inspect the current ANGLE D3D11 device");
  Microsoft::WRL::ComPtr<ID3D11Device> result =
      reinterpret_cast<ID3D11Device *>(d3d);
  return result;
}

void CheckPixels(ID3D11Device *device, HANDLE handle, int width, int height,
                 const std::array<uint8_t, 4> &expected) {
  Microsoft::WRL::ComPtr<ID3D11Texture2D> source;
  Require(SUCCEEDED(device->OpenSharedResource(handle, IID_PPV_ARGS(&source))),
          "Cannot open delivered texture");
  D3D11_TEXTURE2D_DESC descriptor{};
  source->GetDesc(&descriptor);
  Require(descriptor.Width == static_cast<UINT>(width) &&
              descriptor.Height == static_cast<UINT>(height),
          "Delivered texture has stale dimensions");
  descriptor.Usage = D3D11_USAGE_STAGING;
  descriptor.BindFlags = 0;
  descriptor.MiscFlags = 0;
  descriptor.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> staging;
  Require(SUCCEEDED(device->CreateTexture2D(&descriptor, nullptr, &staging)),
          "Cannot create test-only staging texture");
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context;
  device->GetImmediateContext(&context);
  context->CopyResource(staging.Get(), source.Get());
  D3D11_MAPPED_SUBRESOURCE mapped{};
  Require(SUCCEEDED(context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped)),
          "Cannot map test-only staging texture");
  bool valid = true;
  for (int y = 0; y < height; ++y) {
    const auto *row = static_cast<const uint8_t *>(mapped.pData) +
                      static_cast<size_t>(y) * mapped.RowPitch;
    for (int x = 0; x < width; ++x) {
      for (size_t channel = 0; channel < expected.size(); ++channel) {
        valid = valid &&
                row[static_cast<size_t>(x) * 4 + channel] == expected[channel];
      }
    }
  }
  context->Unmap(staging.Get(), 0);
  Require(valid, "Texture contains stale or torn pixels");
}
} // namespace

template <typename T>
auto HasPendingFrame(T& value, int) -> decltype(value.HasPendingFrame()) {
  return value.HasPendingFrame();
}
template <typename T>
bool HasPendingFrame(T&, long) { return false; }

HANDLE WaitForFrame(ANGLESurfaceManager& producer) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  HANDLE result = nullptr;
  do {
    result = producer.Read();
    if (!HasPendingFrame(producer, 0)) return result;
    std::this_thread::yield();
  } while (std::chrono::steady_clock::now() < deadline);
  throw std::runtime_error("GPU snapshot did not complete");
}

int main() {
  try {
    auto producer = std::make_unique<ANGLESurfaceManager>(64, 32);
    ANGLESurfaceManager consumer(64, 32);
    consumer.MakeCurrent(true);
    const auto device = CurrentDevice();
    consumer.MakeCurrent(false);
    std::vector<Microsoft::WRL::ComPtr<ID3D11Texture2D>> retained;
    for (int frame = 0; frame < 100; ++frame) {
      const bool red = frame % 2 == 0;
      producer->Draw([red] {
        glClearColor(red ? 1.0f : 0.0f, 0.0f, red ? 0.0f : 1.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
      });
      consumer.MakeCurrent(true);
      const auto handle = WaitForFrame(*producer);
      Require(handle != nullptr, "Completed snapshot is missing");
      // Flutter's release_callback is invoked before sampling. Retain imported
      // allocations across later renders to model that delayed GPU consumption.
      if (frame < 4) retained.push_back(producer->TextureForHandle(handle));
      CheckPixels(device.Get(), handle, 64, 32,
                  red ? std::array<uint8_t, 4>{0, 0, 255, 255}
                      : std::array<uint8_t, 4>{255, 0, 0, 255});
      consumer.MakeCurrent(false);
    }
    // No current consumer context must use the separate copied texture.
    producer->Draw([] {
      glClearColor(0, 1, 0, 1);
      glClear(GL_COLOR_BUFFER_BIT);
    });
    const auto copied = WaitForFrame(*producer);
    Require(copied == producer->handle(), "Unknown consumer bypassed copying");
    CheckPixels(device.Get(), copied, 64, 32, {0, 255, 0, 255});
    Require(producer->Read() == copied, "Unchanged frame changed its delivery");
    producer->SetSize(32, 16);
    producer->Draw([] {
      glClearColor(1, 1, 1, 1);
      glClear(GL_COLOR_BUFFER_BIT);
    });
    consumer.MakeCurrent(true);
    CheckPixels(device.Get(), WaitForFrame(*producer), 32, 16, {255, 255, 255, 255});
    consumer.MakeCurrent(false);
    producer.reset();
    // Every previously imported frame must survive 100 writes, resize and
    // producer destruction WITHOUT its pixels changing to a later frame.
    for (size_t i = 0; i < retained.size(); ++i) {
      Microsoft::WRL::ComPtr<IDXGIResource> resource;
      Require(SUCCEEDED(retained[i].As(&resource)), "Cannot retain import");
      HANDLE handle = nullptr;
      Require(SUCCEEDED(resource->GetSharedHandle(&handle)), "Lost import handle");
      CheckPixels(device.Get(), handle, 64, 32,
                  i % 2 == 0 ? std::array<uint8_t, 4>{0, 0, 255, 255}
                             : std::array<uint8_t, 4>{255, 0, 0, 255});
    }
    // Disposing a player cannot terminate Flutter's still-live EGL display.
    consumer.Draw([] {
      glClearColor(0, 1, 0, 1);
      glClear(GL_COLOR_BUFFER_BIT);
    });
    consumer.MakeCurrent(true);
    CheckPixels(device.Get(), WaitForFrame(consumer), 64, 32, {0, 255, 0, 255});
    consumer.MakeCurrent(false);
    std::cout << "PASS: 100 complete immutable GPU frames, delayed consumption, "
                 "resize and shared-display lifetime\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
}
