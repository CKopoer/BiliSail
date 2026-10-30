// Exercise the pinned upstream D3D11 renderer with real shared GPU textures.
// No Flutter window, network media or account is required.
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <thread>

#include "d3d11_renderer.h"

namespace {
using Microsoft::WRL::ComPtr;
using namespace std::chrono_literals;

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

ComPtr<ID3D11Texture2D> OpenFrame(D3D11Renderer& renderer) {
  const auto handle = renderer.ConsumerAcquire();
  Require(handle != nullptr, "mailbox returned no completed texture");
  ComPtr<ID3D11Texture2D> texture;
  Require(SUCCEEDED(renderer.device()->OpenSharedResource(
              handle, IID_PPV_ARGS(&texture))),
          "shared texture could not be opened");
  return texture;
}

void CheckDimensions(D3D11Renderer& renderer, UINT width, UINT height) {
  const auto texture = OpenFrame(renderer);
  D3D11_TEXTURE2D_DESC desc{};
  texture->GetDesc(&desc);
  Require(desc.Width == width && desc.Height == height,
          "mailbox dimensions do not match output");
}

void SubmitGreenFrame(D3D11Renderer& renderer) {
  ComPtr<ID3D11Texture2D> target;
  Require(SUCCEEDED(renderer.swap_chain()->GetBuffer(0, IID_PPV_ARGS(&target))),
          "mpv render target unavailable");
  ComPtr<ID3D11RenderTargetView> view;
  Require(SUCCEEDED(renderer.device()->CreateRenderTargetView(
              target.Get(), nullptr, &view)),
          "render target view unavailable");
  ComPtr<ID3D11DeviceContext> context;
  renderer.device()->GetImmediateContext(&context);
  constexpr float green[]{0.0f, 1.0f, 0.0f, 1.0f};
  context->ClearRenderTargetView(view.Get(), green);
  renderer.ProducerCommit();
  // The test is the producer; real mpv submits its own command stream.
  context->Flush();
}

void CheckPixels(D3D11Renderer& renderer,
                 const ComPtr<ID3D11Texture2D>& retained = {}) {
  const auto texture = retained ? retained : OpenFrame(renderer);
  D3D11_TEXTURE2D_DESC desc{};
  texture->GetDesc(&desc);
  desc.Usage = D3D11_USAGE_STAGING;
  desc.BindFlags = 0;
  desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  desc.MiscFlags = 0;
  ComPtr<ID3D11Texture2D> staging;
  Require(SUCCEEDED(renderer.device()->CreateTexture2D(&desc, nullptr, &staging)),
          "readback texture unavailable");
  ComPtr<ID3D11DeviceContext> context;
  renderer.device()->GetImmediateContext(&context);
  context->CopyResource(staging.Get(), texture.Get());
  D3D11_MAPPED_SUBRESOURCE mapped{};
  Require(SUCCEEDED(context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped)),
          "shared frame readback failed");
  const auto* pixel = static_cast<const unsigned char*>(mapped.pData);
  const bool green = pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 &&
                     pixel[3] == 255;
  context->Unmap(staging.Get(), 0);
  Require(green, "consumer did not receive the completed producer frame");
}

void ExerciseRenderer() {
  D3D11Renderer renderer(320, 180);
  Require(renderer.ReadHandleSnapshot() == renderer.ConsumerAcquire(),
          "initial completed-frame handle is unstable");
  CheckDimensions(renderer, 320, 180);
  for (int frame = 0; frame < 12; ++frame) {
    SubmitGreenFrame(renderer);
    std::this_thread::sleep_for(5ms);
  }
  CheckPixels(renderer);
  // A paused video supplies only one redraw after a viewport change. It must
  // already be a completed frame, rather than an unpainted initial read slot.
  for (const auto width : {640, 256, 960, 320}) {
    const auto retained = OpenFrame(renderer);
    renderer.SetSize(width, width * 9 / 16);
    // A Flutter frame descriptor may outlive the resize that released these
    // slots. Its retained resource must remain usable until its release
    // callback.
    CheckPixels(renderer, retained);
    SubmitGreenFrame(renderer);
    CheckDimensions(renderer, width, width * 9 / 16);
    CheckPixels(renderer);
  }
  for (int frame = 0; frame < 12; ++frame) {
    SubmitGreenFrame(renderer);
    std::this_thread::sleep_for(5ms);
  }
  CheckPixels(renderer);
}
}  // namespace

int main() {
  try {
    for (int cycle = 0; cycle < 8; ++cycle) ExerciseRenderer();
    std::cout << "PASS: 8 D3D11 mailbox create/render/readback/resize/dispose cycles\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
