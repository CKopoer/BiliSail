#include "hdr_video.h"

#include <commctrl.h>
#include <dcomp.h>
#include <dwmapi.h>
#include <dxgi1_6.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <mpv/client.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <cstring>
#include <map>
#include <utility>

namespace {
using Microsoft::WRL::ComPtr;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

int64_t Integer(const Value* value) {
  if (!value) return 0;
  if (const auto* number = std::get_if<int32_t>(value)) return *number;
  if (const auto* number = std::get_if<int64_t>(value)) return *number;
  return 0;
}

int64_t Field(const Map* args, const char* name) {
  if (!args) return 0;
  const auto it = args->find(Value(name));
  return it == args->end() ? 0 : Integer(&it->second);
}

bool HdrEnabled(HWND view, ComPtr<IDXGIFactory1>& factory) {
  const auto monitor = MonitorFromWindow(view, MONITOR_DEFAULTTONEAREST);
  if (!factory || !factory->IsCurrent()) {
    factory.Reset();
    if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) return false;
  }
  for (UINT a = 0;; ++a) {
    ComPtr<IDXGIAdapter1> adapter;
    if (factory->EnumAdapters1(a, &adapter) != S_OK) break;
    for (UINT o = 0;; ++o) {
      ComPtr<IDXGIOutput> output;
      if (adapter->EnumOutputs(o, &output) != S_OK) break;
      ComPtr<IDXGIOutput6> advanced;
      DXGI_OUTPUT_DESC1 desc{};
      if (SUCCEEDED(output.As(&advanced)) &&
          SUCCEEDED(advanced->GetDesc1(&desc)) && desc.Monitor == monitor)
        return desc.ColorSpace == DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020;
    }
  }
  return false;
}

// Flutter and its child HWND draw into the same SDR redirection bitmap. A
// composition target on either HWND covers translucent Flutter controls.
// Keep the HDR planes immediately behind the host and let DWM blend them.
struct ViewLayers {
  HWND view{};
  HWND host{};
  HWND underlay{};
  bool transparent = false;
  int visible_planes = 0;
  ComPtr<IVirtualDesktopManager> desktops;
  ComPtr<IDCompositionDevice> device;
  ComPtr<IDCompositionTarget> target;
  ComPtr<IDCompositionVisual> root;

  bool Initialize(HWND child) {
    view = child;
    host = GetAncestor(child, GA_ROOT);
    if (!host) return false;
    underlay =
        CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
                            WS_EX_NOREDIRECTIONBITMAP | WS_EX_TRANSPARENT,
                        L"STATIC", L"BiliSail HDR video", WS_POPUP, 0, 0, 0, 0,
                        nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    if (!underlay ||
        !SetWindowSubclass(host, HostMessage, reinterpret_cast<UINT_PTR>(this),
                           reinterpret_cast<DWORD_PTR>(this)))
      return false;
    CoCreateInstance(CLSID_VirtualDesktopManager, nullptr, CLSCTX_ALL,
                     IID_PPV_ARGS(&desktops));
    SyncDesktop();
    DWM_BLURBEHIND glass{};
    glass.dwFlags = DWM_BB_ENABLE | DWM_BB_BLURREGION;
    glass.hRgnBlur = CreateRectRgn(0, 0, -1, -1);
    glass.fEnable = TRUE;
    auto hr = DwmEnableBlurBehindWindow(host, &glass);
    DeleteObject(glass.hRgnBlur);
    if (FAILED(hr)) return false;
    transparent = true;
    return SUCCEEDED(
               DCompositionCreateDevice(nullptr, IID_PPV_ARGS(&device))) &&
           SUCCEEDED(device->CreateTargetForHwnd(underlay, FALSE, &target)) &&
           SUCCEEDED(device->CreateVisual(&root)) &&
           SUCCEEDED(target->SetRoot(root.Get())) &&
           SUCCEEDED(device->Commit());
  }
  void SyncDesktop() const {
    GUID parent_desktop{}, video_desktop{};
    if (desktops && host &&
        SUCCEEDED(desktops->GetWindowDesktopId(host, &parent_desktop)) &&
        SUCCEEDED(desktops->GetWindowDesktopId(underlay, &video_desktop)) &&
        !IsEqualGUID(parent_desktop, video_desktop)) {
      desktops->MoveWindowToDesktop(underlay, parent_desktop);
    }
  }
  void SyncWindow() const {
    if (!IsWindow(host) || !underlay) return;
    DWORD cloaked = 0;
    DwmGetWindowAttribute(host, DWMWA_CLOAKED, &cloaked, sizeof(cloaked));
    if (!visible_planes || !IsWindowVisible(host) || IsIconic(host) ||
        cloaked) {
      if (IsWindowVisible(underlay)) ShowWindow(underlay, SW_HIDE);
      return;
    }
    RECT dst{}, previous{};
    GetClientRect(host, &dst);
    MapWindowPoints(host, nullptr, reinterpret_cast<POINT*>(&dst), 2);
    GetWindowRect(underlay, &previous);
    if (!EqualRect(&dst, &previous) || !IsWindowVisible(underlay) ||
        GetWindow(host, GW_HWNDNEXT) != underlay) {
      SetWindowPos(underlay, host, dst.left, dst.top, dst.right - dst.left,
                   dst.bottom - dst.top, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }
  }
  static LRESULT CALLBACK HostMessage(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam, UINT_PTR id,
                                      DWORD_PTR data) {
    auto* self = reinterpret_cast<ViewLayers*>(data);
    // Run before the host procedure: it can dispose the channel and this
    // subclass when closing a detached playback window.
    if (message == WM_NCDESTROY) {
      RemoveWindowSubclass(window, HostMessage, id);
      self->host = nullptr;
      ShowWindow(self->underlay, SW_HIDE);
    } else if (message == WM_WINDOWPOSCHANGED || message == WM_SIZE ||
               message == WM_ACTIVATE || message == WM_DISPLAYCHANGE) {
      self->SyncWindow();
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }
  ~ViewLayers() {
    if (target) target->SetRoot(nullptr);
    if (device) device->Commit();
    if (IsWindow(host)) {
      RemoveWindowSubclass(host, HostMessage, reinterpret_cast<UINT_PTR>(this));
      if (transparent) {
        DWM_BLURBEHIND glass{};
        glass.dwFlags = DWM_BB_ENABLE;
        DwmEnableBlurBehindWindow(host, &glass);
      }
    }
    if (underlay) DestroyWindow(underlay);
  }
};

struct Video {
  struct Bounds {
    int x, y, w, h;
  };
  // A fullscreen route can be attached before the inline route is removed.
  std::map<int64_t, Bounds> placements;
  std::shared_ptr<ViewLayers> layers;
  ComPtr<IDCompositionVisual> plane;
  UINT width{}, height{};
  bool shown = false;
  bool Bind(mpv_handle* player) {
    const HMODULE module = GetModuleHandleW(L"libmpv-2.dll");
    const auto symbol =
        module ? GetProcAddress(module, "mpv_get_property") : nullptr;
    decltype(&mpv_get_property) get_property = nullptr;
    static_assert(sizeof(get_property) == sizeof(symbol));
    std::memcpy(&get_property, &symbol, sizeof(symbol));
    int64_t address = 0;
    if (!player || !get_property ||
        get_property(player, "display-swapchain", MPV_FORMAT_INT64, &address) <
            0)
      return false;
    auto* pointer = reinterpret_cast<IUnknown*>(address);
    ComPtr<IDXGISwapChain3> chain;
    DXGI_SWAP_CHAIN_DESC1 desc{};
    UINT support{};
    constexpr auto pq = DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020;
    if (!pointer || FAILED(pointer->QueryInterface(IID_PPV_ARGS(&chain))) ||
        FAILED(chain->GetDesc1(&desc)) ||
        desc.Format != DXGI_FORMAT_R10G10B10A2_UNORM ||
        FAILED(chain->CheckColorSpaceSupport(pq, &support)) ||
        !(support & DXGI_SWAP_CHAIN_COLOR_SPACE_SUPPORT_FLAG_PRESENT) ||
        FAILED(chain->SetColorSpace1(pq)))
      return false;
    width = desc.Width;
    height = desc.Height;
    return width && height && SUCCEEDED(layers->device->CreateVisual(&plane)) &&
           SUCCEEDED(plane->SetContent(chain.Get()));
  }
  void Hide() {
    if (shown) {
      layers->root->RemoveVisual(plane.Get());
      --layers->visible_planes;
      shown = false;
    }
  }
  bool UpdatePlacement() {
    if (!plane) return false;
    if (placements.empty()) {
      Hide();
    } else {
      const auto [x, y, w, h] = placements.rbegin()->second;
      POINT origin{x, y};
      MapWindowPoints(layers->view, layers->host, &origin, 1);
      const D2D_MATRIX_3X2_F transform{static_cast<float>(w) / width,
                                       0,
                                       0,
                                       static_cast<float>(h) / height,
                                       static_cast<float>(origin.x),
                                       static_cast<float>(origin.y)};
      if (FAILED(plane->SetTransform(transform))) return false;
      if (!shown) {
        if (FAILED(layers->root->AddVisual(plane.Get(), TRUE, nullptr)))
          return false;
        shown = true;
        ++layers->visible_planes;
      }
    }
    layers->SyncWindow();
    return SUCCEEDED(layers->device->Commit());
  }
  ~Video() {
    Hide();
    if (layers) {
      layers->SyncWindow();
      layers->device->Commit();
    }
  }
};
}  // namespace

struct HdrVideoChannel::State {
  flutter::MethodChannel<Value> channel;
  std::map<int64_t, Video> videos;
  ComPtr<IDXGIFactory1> factory;
  int64_t next_id = 0;
  State(flutter::BinaryMessenger* messenger,
        std::function<HWND(int64_t)> resolve)
      : channel(messenger, "bilisail/hdr_video",
                &flutter::StandardMethodCodec::GetInstance()) {
    channel.SetMethodCallHandler([this, resolve = std::move(resolve)](
                                     const auto& call, auto result) {
      const auto* args =
          call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      const auto& method = call.method_name();
      if (method == "supported") {
        const HWND view = resolve(Field(args, "view"));
        for (const auto& entry : videos) {
          if (entry.second.layers->view == view) {
            entry.second.layers->SyncDesktop();
            entry.second.layers->SyncWindow();
            break;
          }
        }
        if (view && HdrEnabled(view, factory))
          result->Success(Value("pq"));
        else
          result->Success();
        return;
      }
      if (method == "create") {
        const HWND view = resolve(Field(args, "view"));
        if (!view || !HdrEnabled(view, factory)) {
          result->Success();
          return;
        }
        std::shared_ptr<ViewLayers> layers;
        for (const auto& entry : videos) {
          if (entry.second.layers->view == view) {
            layers = entry.second.layers;
            break;
          }
        }
        if (!layers) {
          layers = std::make_shared<ViewLayers>();
          if (!layers->Initialize(view)) {
            result->Success();
            return;
          }
        }
        const auto id = ++next_id;
        videos[id].layers = std::move(layers);
        result->Success(Value(id));
        return;
      }
      const auto id = args ? Field(args, "id") : Integer(call.arguments());
      auto video = videos.find(id);
      if (method == "bind") {
        result->Success(Value(video != videos.end() &&
                              video->second.Bind(reinterpret_cast<mpv_handle*>(
                                  Field(args, "player")))));
      } else if (method == "place") {
        if (video != videos.end()) {
          video->second.placements[Field(args, "owner")] = {
              static_cast<int>(Field(args, "x")),
              static_cast<int>(Field(args, "y")),
              static_cast<int>(Field(args, "width")),
              static_cast<int>(Field(args, "height"))};
          video->second.UpdatePlacement();
        }
        result->Success();
      } else if (method == "hide") {
        if (video != videos.end()) {
          video->second.placements.erase(Field(args, "owner"));
          video->second.UpdatePlacement();
        }
        result->Success();
      } else if (method == "release") {
        if (video != videos.end()) videos.erase(video);
        result->Success();
      } else
        result->NotImplemented();
    });
  }
  ~State() { channel.SetMethodCallHandler(nullptr); }
};
HdrVideoChannel::HdrVideoChannel(flutter::BinaryMessenger* messenger,
                                 std::function<HWND(int64_t)> resolve)
    : state_(std::make_unique<State>(messenger, std::move(resolve))) {}
HdrVideoChannel::~HdrVideoChannel() = default;
