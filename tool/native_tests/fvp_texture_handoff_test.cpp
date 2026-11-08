// Exercise the actual fvp TexturePlayer replacement with a controlled renderer
// and registrar, using real D3D11 copies and a second-device consumer.
#include <flutter/texture_registrar.h>
#include "d3d11_texture_snapshot.h"
#include <d3d11_4.h>

#include <functional>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <vector>

namespace fvp {
using namespace std;
using Microsoft::WRL::ComPtr;
struct mdkPlayerAPI {};
struct D3D11RenderAPI { ID3D11Texture2D* rtv = nullptr; };

class Player {
 public:
  explicit Player(mdkPlayerAPI*) {}
  virtual ~Player() = default;
  void setRenderAPI(D3D11RenderAPI* api) {
    ComPtr<ID3D11Device> device;
    api->rtv->GetDevice(&device);
    device->GetImmediateContext(&context_);
    if (FAILED(device->CreateRenderTargetView(api->rtv, nullptr, &view_)))
      throw runtime_error("Cannot create fake MDK render target");
  }
  void setVideoSurfaceSize(int, int) {}
  void setRenderCallback(function<void(void*)> value) { render = std::move(value); }
  void renderVideo() {
    ++frames_;
    const float color[]{frames_ % 2 ? 1.0f : 0.0f, 0, frames_ % 2 ? 0.0f : 1.0f, 1};
    context_->ClearRenderTargetView(view_.Get(), color);
  }
  function<void(void*)> render;
 private:
  int frames_ = 0;
  ComPtr<ID3D11DeviceContext> context_;
  ComPtr<ID3D11RenderTargetView> view_;
};

#include "texture_player.inc"
}  // namespace fvp

class Registrar : public flutter::TextureRegistrar {
 public:
  int64_t RegisterTexture(flutter::TextureVariant* value) override {
    texture = value;
    return 1;
  }
  bool MarkTextureFrameAvailable(int64_t) override { return true; }
  void UnregisterTexture(int64_t, std::function<void()> callback) override {
    if (callback) callback();
  }
  bool UnregisterTexture(int64_t) override { return true; }
  flutter::TextureVariant* texture = nullptr;
};

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

void PendingCopyKeepsTheLatestPausedRevision(ID3D11Device* producer,
    ID3D11Device* consumer, ID3D11Texture2D* target) {
  using Microsoft::WRL::ComPtr;
  ComPtr<ID3D11Device5> producer5, consumer5;
  ComPtr<ID3D11DeviceContext> producer_context, consumer_context;
  producer->GetImmediateContext(&producer_context);
  consumer->GetImmediateContext(&consumer_context);
  ComPtr<ID3D11DeviceContext4> producer4, consumer4;
  if (FAILED(producer->QueryInterface(IID_PPV_ARGS(&producer5))) ||
      FAILED(consumer->QueryInterface(IID_PPV_ARGS(&consumer5))) ||
      FAILED(producer_context.As(&producer4)) || FAILED(consumer_context.As(&consumer4))) {
    std::cout << "SKIP: D3D11 shared fences unavailable for pending-copy test\n";
    return;
  }
  ComPtr<ID3D11Fence> producer_fence, consumer_fence;
  Require(SUCCEEDED(producer5->CreateFence(0, D3D11_FENCE_FLAG_SHARED,
                    IID_PPV_ARGS(&producer_fence))), "Cannot create test GPU gate");
  HANDLE shared = nullptr;
  Require(SUCCEEDED(producer_fence->CreateSharedHandle(nullptr, GENERIC_ALL,
                    nullptr, &shared)), "Cannot share test GPU gate");
  const auto opened = consumer5->OpenSharedFence(shared, IID_PPV_ARGS(&consumer_fence));
  CloseHandle(shared);
  Require(SUCCEEDED(opened), "Cannot open test GPU gate");
  // Always unblock the GPU queue, including a failed assertion.
  struct ReleaseGate {
    ID3D11DeviceContext4* context;
    ID3D11Fence* fence;
    ~ReleaseGate() { context->Signal(fence, 1); context->Flush(); }
  } release{consumer4.Get(), consumer_fence.Get()};

  media_kit::D3D11TextureSnapshot snapshot;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  auto frame = snapshot.Capture(target, 1);
  while (snapshot.pending() && std::chrono::steady_clock::now() < deadline)
    frame = snapshot.Capture(target, 1);
  Require(frame && frame->revision == 1, "Initial snapshot did not complete");
  Require(SUCCEEDED(producer4->Wait(producer_fence.Get(), 1)), "Cannot delay test GPU copy");
  frame = snapshot.Capture(target, 2);
  Require(snapshot.pending() && frame->revision == 1,
          "Pending GPU copy exposed unfinished pixels");
  for (int retry = 0; retry < 3; ++retry) {
    frame = snapshot.Capture(target, 3);
    Require(snapshot.pending() && frame->revision == 1,
            "Blocked copy overwrote the last complete frame");
  }
  Require(SUCCEEDED(consumer4->Signal(consumer_fence.Get(), 1)), "Cannot release test GPU gate");
  consumer4->Flush();
  do {
    frame = snapshot.Capture(target, 3);
    if (!snapshot.pending()) {
      Require(frame && frame->revision == 3,
              "Old pending copy swallowed the latest paused/resize revision");
      std::cout << "PASS: bounded pending copy, complete-frame fallback and latest paused revision\n";
      return;
    }
  } while (std::chrono::steady_clock::now() < deadline);
  throw std::runtime_error("Latest paused snapshot did not complete");
}

int main() {
  using Microsoft::WRL::ComPtr;
  try {
    ComPtr<ID3D11Device> producer, consumer;
    ComPtr<ID3D11DeviceContext> context;
    Require(SUCCEEDED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE,
        nullptr, 0, nullptr, 0, D3D11_SDK_VERSION, &producer, nullptr, nullptr)),
        "Cannot create producer device");
    Require(SUCCEEDED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE,
        nullptr, 0, nullptr, 0, D3D11_SDK_VERSION, &consumer, nullptr, &context)),
        "Cannot create independent consumer device");
    D3D11_TEXTURE2D_DESC desc{};
    desc.Width = 128;
    desc.Height = 64;
    desc.MipLevels = desc.ArraySize = desc.SampleDesc.Count = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    ComPtr<ID3D11Texture2D> target;
    Require(SUCCEEDED(producer->CreateTexture2D(&desc, nullptr, &target)),
            "Cannot create producer render target");
    Registrar registrar;
    std::vector<ComPtr<ID3D11Texture2D>> imported;
    {
      fvp::TexturePlayer player(0, target, &registrar);
      const auto& callback = std::get<flutter::GpuSurfaceTexture>(*registrar.texture);
      Require(!callback.ObtainDescriptor(128, 64), "Unrendered pixels were published");
      for (int frame = 0; frame < 20; ++frame) {
        player.render(nullptr);
        const FlutterDesktopGpuSurfaceDescriptor* descriptor = nullptr;
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
        do {
          descriptor = callback.ObtainDescriptor(128, 64);
          // The first copy may be pending; later callbacks can repeat the last
          // complete frame. Wait for a new handle without leaking import leases.
          if (descriptor && !imported.empty()) {
            ComPtr<IDXGIResource> old;
            imported.back().As(&old);
            HANDLE old_handle = nullptr;
            old->GetSharedHandle(&old_handle);
            if (old_handle == descriptor->handle) {
              descriptor->release_callback(descriptor->release_context);
              descriptor = nullptr;
            }
          }
          if (descriptor) break;
          std::this_thread::yield();
        } while (std::chrono::steady_clock::now() < deadline);
        Require(descriptor != nullptr, "Completed MDK snapshot did not arrive");
        ComPtr<ID3D11Texture2D> image;
        Require(SUCCEEDED(consumer->OpenSharedResource(descriptor->handle,
                        IID_PPV_ARGS(&image))), "Cannot import MDK snapshot");
        descriptor->release_callback(descriptor->release_context);
        Require(descriptor->visible_width == 128, "Descriptor died with its lease");
        imported.push_back(std::move(image));
      }
    }
    // Delayed sampling, AFTER all new frames and the TexturePlayer's teardown.
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    ComPtr<ID3D11Texture2D> staging;
    Require(SUCCEEDED(consumer->CreateTexture2D(&desc, nullptr, &staging)),
            "Cannot create test-only readback");
    for (size_t frame = 0; frame < imported.size(); ++frame) {
      context->CopyResource(staging.Get(), imported[frame].Get());
      D3D11_MAPPED_SUBRESOURCE mapped{};
      Require(SUCCEEDED(context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped)),
              "Cannot map test-only readback");
      bool complete = true;
      for (UINT y = 0; y < desc.Height; ++y) {
        const auto* row = static_cast<const uint8_t*>(mapped.pData) + y * mapped.RowPitch;
        for (UINT x = 0; x < desc.Width; ++x) {
          complete &= row[x * 4] == (frame % 2 ? 255 : 0) &&
                      row[x * 4 + 2] == (frame % 2 ? 0 : 255);
        }
      }
      context->Unmap(staging.Get(), 0);
      Require(complete, "MDK snapshot was overwritten or published incomplete");
    }
    PendingCopyKeepsTheLatestPausedRevision(producer.Get(), consumer.Get(), target.Get());
    std::cout << "PASS: fvp first-frame filtering, 20 immutable cross-device frames, "
                 "early descriptor release and delayed sampling after disposal\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
}
