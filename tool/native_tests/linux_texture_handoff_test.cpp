// The exact production populate/copy method bodies are included below. Fake
// command queues deliberately delay GPU reads and writes across EGL contexts.
#include <array>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <functional>
#include <iostream>
#include <limits>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <unordered_map>
#include <vector>

using guint8 = uint8_t;
using guint32 = uint32_t;
using gint32 = int32_t;
using gint64 = int64_t;
using guintptr = uintptr_t;
using gsize = size_t;
using gboolean = bool;
using EGLContext = int;
using EGLDisplay = int;
using EGLSurface = int;
using EGLImageKHR = uintptr_t;
using EGLClientBuffer = void*;
using EGLint = int;
using GMutex = std::mutex;
struct GError {};
constexpr bool TRUE = true, FALSE = false;
constexpr int G_MAXINT32 = std::numeric_limits<int32_t>::max();
constexpr int GL_TEXTURE_2D = 1, GL_FRAMEBUFFER = 2, GL_LINEAR = 3;
constexpr int GL_TEXTURE_MIN_FILTER = 4, GL_TEXTURE_MAG_FILTER = 5;
constexpr int GL_TEXTURE_WRAP_S = 6, GL_TEXTURE_WRAP_T = 7;
constexpr int GL_CLAMP_TO_EDGE = 8, GL_RGBA = 9, GL_UNSIGNED_BYTE = 10;
constexpr int GL_COLOR_ATTACHMENT0 = 11;
constexpr int EGL_DRAW = 1, EGL_READ = 2, EGL_NONE = 0;
constexpr int EGL_NO_SURFACE = 0, EGL_GL_TEXTURE_2D_KHR = 3;
constexpr EGLImageKHR EGL_NO_IMAGE_KHR = 0;
constexpr int MPV_RENDER_PARAM_OPENGL_FBO = 1, MPV_RENDER_PARAM_FLIP_Y = 2;
constexpr int MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME = 3, MPV_RENDER_PARAM_INVALID = 0;
struct mpv_opengl_fbo { int fbo, w, h, format; };
struct mpv_render_param { int type; void* data; };
struct Frame { int value = 0; };
struct VideoOutput {
  gint64 width = 64, height = 32;
  int revision = 0;
  bool destroyed = false;
  guint8* pixel_buffer = nullptr;
  guint32 sw_frame_width = 0, sw_frame_height = 0;
  GMutex mutex;
};
using mpv_render_context = VideoOutput;
struct TextureGL {
  guint32 name = 0, fbo = 0, mpv_texture = 0;
  EGLImageKHR egl_image = 0;
  guint32 current_width = 1, current_height = 1;
  VideoOutput* video_output;
};
using FlTextureGL = TextureGL;
#define TEXTURE_GL(value) (value)
struct TextureSW {
  guint32 current_width = 1, current_height = 1;
  VideoOutput* video_output;
  guint8* snapshot = nullptr;
};
using FlPixelBufferTexture = TextureSW;
#define TEXTURE_SW(value) (value)

int current_context = 1;
guint32 next_name = 1;
std::array<guint32, 3> bound_texture{}, bound_fbo{};
std::array<std::vector<std::function<void()>>, 3> queues;
std::unordered_map<guint32, std::shared_ptr<Frame>> textures;
std::unordered_map<guint32, guint32> attachments;
std::unordered_map<EGLImageKHR, std::shared_ptr<Frame>> images;
bool allocation_fails = false;

void Require(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}
void glFinish() {
  auto work = std::move(queues[current_context]);
  queues[current_context].clear();
  for (auto& command : work) command();
}
void glFlush() {}  // Submission is deliberately NOT GPU completion.
EGLDisplay eglGetCurrentDisplay() { return 1; }
EGLContext eglGetCurrentContext() { return current_context; }
EGLSurface eglGetCurrentSurface(int) { return 1; }
bool eglMakeCurrent(EGLDisplay, EGLSurface, EGLSurface, EGLContext value) {
  current_context = value;
  return true;
}
void glGenFramebuffers(int, guint32* value) { *value = next_name++; }
void glGenTextures(int, guint32* value) {
  *value = next_name++;
  textures[*value] = std::make_shared<Frame>();
}
void glDeleteTextures(int, const guint32* value) { textures.erase(*value); }
void glDeleteFramebuffers(int, const guint32* value) { attachments.erase(*value); }
void glBindTexture(int, guint32 value) { bound_texture[current_context] = value; }
void glBindFramebuffer(int, guint32 value) { bound_fbo[current_context] = value; }
void glTexParameteri(int, int, int) {}
void glTexImage2D(int, int, int, guint32, guint32, int, int, int, const void*) {}
void glFramebufferTexture2D(int, int, int, guint32 texture, int) {
  attachments[bound_fbo[current_context]] = texture;
}
EGLImageKHR eglCreateImageKHR(EGLDisplay, EGLContext, int, EGLClientBuffer texture, const EGLint*) {
  const auto image = static_cast<guint32>(reinterpret_cast<uintptr_t>(texture));
  images[image] = textures.at(image);
  return image;
}
void eglDestroyImageKHR(EGLDisplay, EGLImageKHR image) { images.erase(image); }
void glEGLImageTargetTexture2DOES(int, EGLImageKHR image) {
  textures[bound_texture[current_context]] = images.at(image);
}
gint64 video_output_get_width(VideoOutput* value) { return value->width; }
gint64 video_output_get_height(VideoOutput* value) { return value->height; }
EGLDisplay video_output_get_egl_display(VideoOutput*) { return 1; }
EGLContext video_output_get_egl_context(VideoOutput*) { return 2; }
mpv_render_context* video_output_get_render_context(VideoOutput* value) { return value; }
void video_output_notify_texture_update(VideoOutput*) {}
int mpv_render_context_render(mpv_render_context* output, mpv_render_param*) {
  const auto image = textures.at(attachments.at(bound_fbo[current_context]));
  const auto revision = output->revision;
  queues[current_context].push_back([image, revision] { image->value = revision; });
  return 0;
}
void g_mutex_lock(GMutex* mutex) { mutex->lock(); }
void g_mutex_unlock(GMutex* mutex) { mutex->unlock(); }
void* g_try_malloc(size_t size) { return allocation_fails ? nullptr : std::malloc(size); }
void g_free(void* value) { std::free(value); }

#include "linux_texture_gl_body.inc"
#include "linux_video_copy_body.inc"
#include "linux_texture_sw_body.inc"

void CrossContextReadsAndWritesAreOrdered() {
  VideoOutput output;
  TextureGL texture;
  texture.video_output = &output;
  guint32 target = 0, name = 0, width = 0, height = 0;
  for (int frame = 1; frame <= 100; ++frame) {
    output.revision = frame;
    if (frame % 10 == 0) { output.width = 32 + frame; output.height = 16 + frame; }
    Require(texture_gl_populate_texture(&texture, &target, &name, &width, &height, nullptr),
            "Production GL populate failed");
    Require(current_context == 1, "Producer context escaped into Flutter");
    const auto image = textures.at(name);
    Require(image->value == frame, "Published before producer GPU completion");
    Require(width == output.width && height == output.height, "Published stale dimensions");
    queues[1].push_back([image, frame] {
      Require(image->value == frame, "Delayed Flutter read observed a later producer frame");
    });
  }
  glFinish();
}

void SoftwarePixelsRemainStableAfterProducerUnlock() {
  VideoOutput output;
  TextureSW texture;
  texture.video_output = &output;
  const guint8* pixels = nullptr;
  guint32 width = 0, height = 0;
  Require(!texture_sw_copy_pixels(&texture, &pixels, &width, &height, nullptr),
          "Unrendered software pixels were published");
  std::vector<guint8> producer(64 * 32 * 4, 17);
  output.pixel_buffer = producer.data();
  output.sw_frame_width = 64;
  output.sw_frame_height = 32;
  // Native dimensions can have advanced before the current pixel buffer did.
  output.width = 128;
  output.height = 64;
  Require(texture_sw_copy_pixels(&texture, &pixels, &width, &height, nullptr), "No software frame");
  Require(width == 64 && height == 32, "Pixels and metadata came from different frames");
  std::fill(producer.begin(), producer.end(), 99);
  Require(pixels[0] == 17 && pixels[64 * 32 * 4 - 1] == 17,
          "Producer rewrote Flutter's returned pixel bytes");
  allocation_fails = true;
  Require(texture_sw_copy_pixels(&texture, &pixels, &width, &height, nullptr) && pixels[0] == 17,
          "Allocation failure discarded the last complete image");
  allocation_fails = false;
  output.sw_frame_width = 32;
  output.sw_frame_height = 16;
  Require(texture_sw_copy_pixels(&texture, &pixels, &width, &height, nullptr) && pixels[0] == 99,
          "Completed resized software frame was not published");
  Require(width == 32 && height == 16, "Software resize metadata is stale");
  output.destroyed = true;
  Require(texture_sw_copy_pixels(&texture, &pixels, &width, &height, nullptr) && pixels[0] == 99,
          "Closing output discarded the acquired complete frame");
  g_free(texture.snapshot);
}

int main() {
  try {
    CrossContextReadsAndWritesAreOrdered();
    SoftwarePixelsRemainStableAfterProducerUnlock();
    std::cout << "PASS: exact Linux production methods, 100 delayed cross-context reads, "
                 "resize, software snapshots, metadata and failure fallback\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
}
