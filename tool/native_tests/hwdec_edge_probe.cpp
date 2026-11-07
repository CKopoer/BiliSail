// Local-only pixel probe for libmpv's OpenGL/ANGLE hardware-decoder interop.
// It uses the application's pinned SDKs and a BGRA shared pbuffer, as the video
// plugin does. Explicit adapter selection and readback are confined to this
// test.
#define NOMINMAX
#include <Windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <EGL/eglext_angle.h>
#include <GLES2/gl2.h>
#include <mpv/client.h>
#include <mpv/render_gl.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
using Microsoft::WRL::ComPtr;

void Require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

class MpvApi {
public:
  MpvApi() : module_(LoadLibraryW(L"libmpv-2.dll")) {
    Require(module_ != nullptr, "Cannot load the pinned libmpv-2.dll");
  }
  ~MpvApi() { FreeLibrary(module_); }
  MpvApi(const MpvApi &) = delete;
  MpvApi &operator=(const MpvApi &) = delete;

  template <typename T> T Symbol(const char *name) const {
    const auto symbol = GetProcAddress(module_, name);
    Require(symbol != nullptr, "Required libmpv export is missing");
    return reinterpret_cast<T>(symbol);
  }

#define MPV_FUNCTION(member, symbol)                                           \
  const decltype(&symbol) member = Symbol<decltype(&symbol)>(#symbol)
private:
  HMODULE module_;

public:
  MPV_FUNCTION(create, mpv_create);
  MPV_FUNCTION(initialize, mpv_initialize);
  MPV_FUNCTION(option, mpv_set_option_string);
  MPV_FUNCTION(property, mpv_set_property_string);
  MPV_FUNCTION(read, mpv_get_property_string);
  MPV_FUNCTION(command, mpv_command);
  MPV_FUNCTION(event, mpv_wait_event);
  MPV_FUNCTION(logs, mpv_request_log_messages);
  MPV_FUNCTION(free, mpv_free);
  MPV_FUNCTION(destroy_uninitialized, mpv_destroy);
  MPV_FUNCTION(destroy, mpv_terminate_destroy);
  MPV_FUNCTION(render_create, mpv_render_context_create);
  MPV_FUNCTION(render_update, mpv_render_context_update);
  MPV_FUNCTION(render, mpv_render_context_render);
  MPV_FUNCTION(render_free, mpv_render_context_free);
#undef MPV_FUNCTION
};

std::string Read(const MpvApi &api, mpv_handle *client, const char *name) {
  char *const value = api.read(client, name);
  if (!value)
    return {};
  const std::string result(value);
  api.free(value);
  return result;
}

class AngleTarget {
public:
  AngleTarget() = default;
  AngleTarget(const AngleTarget &) = delete;
  AngleTarget &operator=(const AngleTarget &) = delete;
  ~AngleTarget() {
    if (display_ != EGL_NO_DISPLAY) {
      eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
      if (surface_ != EGL_NO_SURFACE)
        eglDestroySurface(display_, surface_);
      if (context_ != EGL_NO_CONTEXT)
        eglDestroyContext(display_, context_);
      // ANGLE can unload D3D11 when terminating the last display. Drop the
      // test's external COM reference while that module is still alive.
      texture_.Reset();
      eglTerminate(display_);
    }
  }

  void Initialize(UINT vendor, int width, int height) {
    ComPtr<IDXGIFactory1> factory;
    Require(SUCCEEDED(CreateDXGIFactory1(IID_PPV_ARGS(&factory))),
            "Cannot enumerate DXGI adapters");
    DXGI_ADAPTER_DESC1 selected{};
    bool found = false;
    for (UINT index = 0;; ++index) {
      ComPtr<IDXGIAdapter1> adapter;
      if (factory->EnumAdapters1(index, &adapter) == DXGI_ERROR_NOT_FOUND)
        break;
      DXGI_ADAPTER_DESC1 description{};
      Require(SUCCEEDED(adapter->GetDesc1(&description)),
              "Cannot read adapter");
      if (description.VendorId == vendor &&
          !(description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
        selected = description;
        found = true;
        break;
      }
    }
    Require(found, "Requested hardware adapter is unavailable");
    const auto platform_display =
        reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(
            eglGetProcAddress("eglGetPlatformDisplayEXT"));
    Require(platform_display != nullptr, "ANGLE platform extension is missing");
    const EGLint display_attributes[] = {
        EGL_PLATFORM_ANGLE_TYPE_ANGLE,
        EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE,
        EGL_PLATFORM_ANGLE_D3D_LUID_HIGH_ANGLE,
        selected.AdapterLuid.HighPart,
        EGL_PLATFORM_ANGLE_D3D_LUID_LOW_ANGLE,
        static_cast<EGLint>(selected.AdapterLuid.LowPart),
        EGL_PLATFORM_ANGLE_ENABLE_AUTOMATIC_TRIM_ANGLE,
        EGL_TRUE,
        EGL_NONE};
    display_ = platform_display(EGL_PLATFORM_ANGLE_ANGLE, EGL_DEFAULT_DISPLAY,
                                display_attributes);
    Require(display_ != EGL_NO_DISPLAY &&
                eglInitialize(display_, nullptr, nullptr),
            "Cannot initialize the requested ANGLE adapter");
    const EGLint config_attributes[] = {EGL_RED_SIZE,   8, EGL_GREEN_SIZE,   8,
                                        EGL_BLUE_SIZE,  8, EGL_ALPHA_SIZE,   8,
                                        EGL_DEPTH_SIZE, 8, EGL_STENCIL_SIZE, 8,
                                        EGL_NONE};
    EGLConfig config{};
    EGLint count{};
    Require(eglChooseConfig(display_, config_attributes, &config, 1, &count) &&
                count,
            "Cannot select the plugin-equivalent EGL configuration");
    const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 2,
                                         EGL_NONE};
    context_ =
        eglCreateContext(display_, config, EGL_NO_CONTEXT, context_attributes);
    Require(context_ != EGL_NO_CONTEXT, "Cannot create GLES 2 context");
    const auto query_display =
        reinterpret_cast<PFNEGLQUERYDISPLAYATTRIBEXTPROC>(
            eglGetProcAddress("eglQueryDisplayAttribEXT"));
    const auto query_device = reinterpret_cast<PFNEGLQUERYDEVICEATTRIBEXTPROC>(
        eglGetProcAddress("eglQueryDeviceAttribEXT"));
    Require(query_display && query_device,
            "Cannot inspect ANGLE's actual device");
    EGLAttrib egl_device{};
    EGLAttrib d3d_device{};
    Require(query_display(display_, EGL_DEVICE_EXT, &egl_device) &&
                query_device(reinterpret_cast<EGLDeviceEXT>(egl_device),
                             EGL_D3D11_DEVICE_ANGLE, &d3d_device),
            "Cannot read ANGLE's D3D11 device");
    ComPtr<ID3D11Device> device = reinterpret_cast<ID3D11Device *>(d3d_device);
    ComPtr<IDXGIDevice> dxgi_device;
    ComPtr<IDXGIAdapter> actual_adapter;
    DXGI_ADAPTER_DESC actual{};
    Require(SUCCEEDED(device.As(&dxgi_device)) &&
                SUCCEEDED(dxgi_device->GetAdapter(&actual_adapter)) &&
                SUCCEEDED(actual_adapter->GetDesc(&actual)),
            "Cannot verify ANGLE's adapter identity");
    Require(actual.AdapterLuid.HighPart == selected.AdapterLuid.HighPart &&
                actual.AdapterLuid.LowPart == selected.AdapterLuid.LowPart,
            "ANGLE silently selected a different adapter");
    std::cout << "adapter_vendor=" << actual.VendorId
              << " adapter_device=" << actual.DeviceId << '\n';
    D3D11_TEXTURE2D_DESC texture_description{};
    texture_description.Width = static_cast<UINT>(width);
    texture_description.Height = static_cast<UINT>(height);
    texture_description.MipLevels = 1;
    texture_description.ArraySize = 1;
    texture_description.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    texture_description.SampleDesc.Count = 1;
    texture_description.Usage = D3D11_USAGE_DEFAULT;
    texture_description.BindFlags =
        D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    texture_description.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
    Require(SUCCEEDED(device->CreateTexture2D(&texture_description, nullptr,
                                              &texture_)),
            "Cannot create the plugin-equivalent BGRA shared texture");
    ComPtr<IDXGIResource> shared;
    HANDLE handle{};
    Require(SUCCEEDED(texture_.As(&shared)) &&
                SUCCEEDED(shared->GetSharedHandle(&handle)),
            "Cannot obtain the BGRA shared handle");
    const EGLint surface_attributes[] = {EGL_WIDTH,
                                         width,
                                         EGL_HEIGHT,
                                         height,
                                         EGL_TEXTURE_TARGET,
                                         EGL_TEXTURE_2D,
                                         EGL_TEXTURE_FORMAT,
                                         EGL_TEXTURE_RGBA,
                                         EGL_NONE};
    surface_ = eglCreatePbufferFromClientBuffer(
        display_, EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE, handle, config,
        surface_attributes);
    Require(surface_ != EGL_NO_SURFACE &&
                eglMakeCurrent(display_, surface_, surface_, context_),
            "Cannot attach the BGRA pbuffer");
    std::cout << "gl_renderer=" << glGetString(GL_RENDERER) << '\n';
  }

private:
  EGLDisplay display_ = EGL_NO_DISPLAY;
  EGLSurface surface_ = EGL_NO_SURFACE;
  EGLContext context_ = EGL_NO_CONTEXT;
  ComPtr<ID3D11Texture2D> texture_;
};

void ReportEdge(const std::vector<uint8_t> &pixels, int width, const char *name,
                int x0, int y0, int x1, int y1) {
  int maximum = 0;
  std::uint64_t green_pixels = 0;
  std::uint64_t total = 0;
  std::uint64_t sums[3]{};
  for (int y = y0; y < y1; ++y) {
    for (int x = x0; x < x1; ++x) {
      const auto offset = (static_cast<size_t>(y) * width + x) * 4;
      const int excess = static_cast<int>(pixels[offset + 1]) -
                         std::max(pixels[offset], pixels[offset + 2]);
      maximum = std::max(maximum, excess);
      if (excess > 8)
        ++green_pixels;
      for (size_t channel = 0; channel < 3; ++channel)
        sums[channel] += pixels[offset + channel];
      ++total;
    }
  }
  std::cout << name << " rgb=" << static_cast<double>(sums[0]) / total << ','
            << static_cast<double>(sums[1]) / total << ','
            << static_cast<double>(sums[2]) / total << " max_green=" << maximum
            << " green_pixels=" << green_pixels << '/' << total << '\n';
}

int Dimension(const char *value) {
  const auto result = std::stoi(value);
  Require(result >= 32 && result <= 8192, "Output dimension must be 32..8192");
  return result;
}
} // namespace

int main(int argc, char **argv) {
  try {
    Require(argc >= 7, "Usage: probe local-file hwdec width height output.rgba "
                       "vendor-hex [option=value ...]");
    const int width = Dimension(argv[3]);
    const int height = Dimension(argv[4]);
    Require(static_cast<std::uint64_t>(width) * height <= 33554432,
            "Output exceeds the probe's 128 MiB readback limit");
    // Keep the probe's optional experiment surface small and fail before
    // creating GPU/native state for an unsupported command-line argument.
    for (int index = 7; index < argc; ++index) {
      const std::string argument(argv[index]);
      const auto equals = argument.find('=');
      Require(equals != std::string::npos, "Extra options must use name=value");
      const std::string name = argument.substr(0, equals);
      Require(name == "glsl-shaders" || name == "cscale" ||
                  name == "gpu-dumb-mode" || name == "d3d11va-zero-copy" ||
                  name == "video-rotate" || name == "video-crop",
              "Unsupported probe experiment option");
    }
    const auto vendor = static_cast<UINT>(std::stoul(argv[6], nullptr, 16));
    const MpvApi api;
    AngleTarget target;
    target.Initialize(vendor, width, height);
    bool initialized = false;
    const auto destroy_client = [&](mpv_handle *handle) {
      if (initialized)
        api.destroy(handle);
      else
        api.destroy_uninitialized(handle);
    };
    const std::unique_ptr<mpv_handle, decltype(destroy_client)> client(
        api.create(), destroy_client);
    Require(client != nullptr, "Cannot create libmpv");
    const auto option = [&](const char *name, const char *value) {
      Require(api.option(client.get(), name, value) >= 0,
              "libmpv rejected a probe option");
    };
    option("config", "no");
    option("terminal", "no");
    option("vo", "libmpv");
    option("hwdec", argv[2]);
    option("hwdec-codecs", "all");
    option("audio", "no");
    option("keep-open", "yes");
    option("idle", "yes");
    for (int index = 7; index < argc; ++index) {
      const std::string argument(argv[index]);
      const auto equals = argument.find('=');
      Require(equals != std::string::npos, "Extra options must use name=value");
      option(argument.substr(0, equals).c_str(),
             argument.substr(equals + 1).c_str());
    }
    Require(api.initialize(client.get()) >= 0, "Cannot initialize libmpv");
    initialized = true;
    api.logs(client.get(), "v");
    mpv_opengl_init_params gl_parameters{
        [](void *, const char *name) -> void * {
          return reinterpret_cast<void *>(eglGetProcAddress(name));
        },
        nullptr};
    mpv_render_param create_parameters[] = {
        {MPV_RENDER_PARAM_API_TYPE,
         const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_parameters},
        {MPV_RENDER_PARAM_INVALID, nullptr}};
    mpv_render_context *created{};
    Require(api.render_create(&created, client.get(), create_parameters) >= 0,
            "Cannot create the libmpv OpenGL renderer");
    const std::unique_ptr<mpv_render_context, decltype(api.render_free)>
        renderer(created, api.render_free);
    const char *command[] = {"loadfile", argv[1], nullptr};
    Require(api.command(client.get(), command) >= 0,
            "Cannot load the local fixture");
    mpv_opengl_fbo fbo{0, width, height, 0};
    mpv_render_param render_parameters[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
        {MPV_RENDER_PARAM_INVALID, nullptr}};
    const auto deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(12);
    bool captured = false;
    while (std::chrono::steady_clock::now() < deadline) {
      const mpv_event *event = api.event(client.get(), 0.01);
      if (event->event_id == MPV_EVENT_LOG_MESSAGE) {
        const auto *message = static_cast<mpv_event_log_message *>(event->data);
        std::cerr << '[' << message->prefix << "] " << message->text;
      }
      if (api.render_update(renderer.get()) & MPV_RENDER_UPDATE_FRAME) {
        Require(api.render(renderer.get(), render_parameters) >= 0,
                "Rendering failed");
      }
      const std::string position = Read(api, client.get(), "time-pos");
      if (!position.empty() && std::stod(position) >= 0.25) {
        Require(api.property(client.get(), "pause", "yes") >= 0,
                "Cannot pause the captured frame");
        Require(api.render(renderer.get(), render_parameters) >= 0,
                "Final rendering failed");
        glFinish();
        captured = true;
        break;
      }
    }
    Require(captured, "No decoded frame arrived before the deadline");
    const std::string decoder = Read(api, client.get(), "hwdec-current");
    Require(decoder == argv[2],
            "Actual hardware decoder differs from the requested mode");
    for (const char *property :
         {"mpv-version", "ffmpeg-version", "hwdec-current", "video-format",
          "video-params", "video-out-params"}) {
      std::cout << property << '=' << Read(api, client.get(), property) << '\n';
    }
    std::vector<uint8_t> pixels(static_cast<size_t>(width) * height * 4);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
    Require(glGetError() == GL_NO_ERROR, "Test-only GPU readback failed");
    std::ofstream output(argv[5], std::ios::binary);
    output.write(reinterpret_cast<const char *>(pixels.data()),
                 static_cast<std::streamsize>(pixels.size()));
    Require(output.good(), "Cannot save the captured pixels");
    ReportEdge(pixels, width, "gl_bottom", 16, 0, width - 16, 1);
    ReportEdge(pixels, width, "gl_top", 16, height - 1, width - 16, height);
    ReportEdge(pixels, width, "left", 0, 16, 1, height - 16);
    ReportEdge(pixels, width, "right", width - 1, 16, width, height - 16);
    ReportEdge(pixels, width, "center", width / 2 - 8, height / 2 - 8,
               width / 2 + 8, height / 2 + 8);
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
}
