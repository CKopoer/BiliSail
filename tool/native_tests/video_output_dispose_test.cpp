// Exercise the production replacement method bodies with controlled native
// completion signals. No Flutter process, GPU, libmpv or account is required.
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <future>
#include <iostream>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <thread>
#include <unordered_map>
#include <vector>

#include "thread_pool.h"

using namespace std::chrono_literals;

void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

struct RenderState {
  std::atomic<bool> callback_removed{false};
  std::atomic<bool> freed{false};
  std::atomic<bool> current{false};
  std::atomic<bool> surface_destroyed{false};
  bool gpu = true;
  std::thread::id render_thread;
};

void mpv_render_context_set_update_callback(RenderState *state, void *,
                                            void *) {
  state->callback_removed = true;
}

void mpv_render_context_free(RenderState *state) {
  require(std::this_thread::get_id() == state->render_thread,
          "mpv freed outside the rendering thread");
  require(state->callback_removed, "mpv callback still attached");
  require(!state->surface_destroyed, "GL surface destroyed before mpv");
  require(!state->gpu || state->current, "GL context is not current");
  state->freed = true;
}

struct Surface {
  explicit Surface(RenderState &state) : state(state) {}
  ~Surface() { state.surface_destroyed = true; }
  void MakeCurrent(bool value) { state.current = value; }
  RenderState &state;
};

class Registrar {
public:
  Registrar *texture_registrar() { return this; }
  void UnregisterTexture(int64_t, std::function<void()> callback) {
    std::lock_guard<std::mutex> lock(mutex);
    callbacks.push_back(std::move(callback));
    changed.notify_all();
  }
  void wait_for_callbacks(size_t count) {
    std::unique_lock<std::mutex> lock(mutex);
    require(
        changed.wait_for(lock, 2s, [&] { return callbacks.size() == count; }),
        "texture unregister was not requested");
  }
  void finish_one() {
    std::function<void()> callback;
    {
      std::lock_guard<std::mutex> lock(mutex);
      require(!callbacks.empty(), "missing unregister callback");
      callback = std::move(callbacks.back());
      callbacks.pop_back();
    }
    callback();
  }

private:
  std::mutex mutex;
  std::condition_variable changed;
  std::vector<std::function<void()>> callbacks;
};

class VideoOutput {
public:
  VideoOutput(ThreadPool &pool, Registrar &registrar, RenderState &state,
              int64_t texture)
      : render_context_(&state), texture_id_(texture), registrar_(&registrar),
        thread_pool_ref_(&pool) {
    state.render_thread =
        pool.Post([] { return std::this_thread::get_id(); }).get();
    if (state.gpu)
      surface_manager_ = std::make_unique<Surface>(state);
  }
  ~VideoOutput();
  void UnregisterTexture(int64_t id, std::function<void()> callback);
  void NotifyRender();
  void CheckAndResize() {}
  void Render() {}
  int64_t GetVideoWidth();
  int64_t GetVideoHeight();
  void SetDisplaySize(std::optional<int64_t> width,
                      std::optional<int64_t> height) {
    width_ = width;
    height_ = height;
  }

private:
  RenderState *render_context_;
  int64_t texture_id_;
  Registrar *registrar_;
  ThreadPool *thread_pool_ref_;
  std::optional<int64_t> width_, height_;
  std::atomic<bool> destroyed_{false};
  std::mutex render_tasks_mutex_;
  std::mutex texture_release_mutex_;
  std::condition_variable textures_released_;
  size_t pending_texture_releases_ = 0;
  std::mutex textures_mutex_;
  std::vector<int> texture_variants_, textures_, pixel_buffer_textures_;
  std::unique_ptr<Surface> surface_manager_;
  std::unique_ptr<uint8_t[]> pixel_buffer_;
};

class VideoOutputManager {
public:
  void Dispose(int64_t handle, std::function<void()> on_disposed);
  std::mutex mutex_;
  std::unordered_map<int64_t, std::unique_ptr<VideoOutput>> video_outputs_;
};

// Same method bodies included by the patched upstream translation units.
#include "video_output_dispose.inc"
#include "video_output_manager_dispose.inc"
#include "video_output_dimensions.inc"

void texture_callbacks_gate_dispose() {
  ThreadPool pool(1);
  Registrar registrar;
  RenderState state;
  VideoOutputManager manager;
  auto output = std::make_unique<VideoOutput>(pool, registrar, state, 22);
  bool old_callback_finished = false;
  output->UnregisterTexture(11, [&] { old_callback_finished = true; });
  manager.video_outputs_.emplace(1, std::move(output));
  std::promise<void> reply;
  auto done = reply.get_future();
  manager.Dispose(1, [&] { reply.set_value(); });
  registrar.wait_for_callbacks(2);
  require(done.wait_for(0ms) == std::future_status::timeout,
          "Dispose replied before texture callbacks");
  require(!state.freed, "mpv freed while texture was still in use");
  registrar.finish_one();
  require(done.wait_for(0ms) == std::future_status::timeout,
          "Dispose ignored the older resize callback");
  registrar.finish_one();
  require(done.wait_for(2s) == std::future_status::ready,
          "Dispose did not finish");
  require(old_callback_finished && state.freed && state.surface_destroyed,
          "Dispose acknowledged incomplete cleanup");
  require(!state.current, "GL context remained current after cleanup");
}

void render_queue_gates_dispose() {
  ThreadPool pool(1);
  Registrar registrar;
  RenderState state;
  VideoOutputManager manager;
  auto output = std::make_unique<VideoOutput>(pool, registrar, state, 0);
  std::promise<void> unblock;
  auto blocked = unblock.get_future();
  auto queued = pool.Post([&] { blocked.wait(); });
  manager.video_outputs_.emplace(1, std::move(output));
  std::promise<void> reply;
  auto done = reply.get_future();
  manager.Dispose(1, [&] { reply.set_value(); });
  require(done.wait_for(20ms) == std::future_status::timeout,
          "Dispose did not wait for in-flight render work");
  require(!state.freed, "mpv freed before render work drained");
  unblock.set_value();
  require(done.wait_for(2s) == std::future_status::ready,
          "texture-free output waited for a nonexistent callback");
  require(state.freed && state.surface_destroyed, "cleanup not completed");
}

void software_output_without_texture() {
  ThreadPool pool(1);
  Registrar registrar;
  RenderState state;
  state.gpu = false;
  { VideoOutput output(pool, registrar, state, 0); }
  require(state.freed, "software render context leaked");
}

void missing_output_acknowledges_dispose() {
  VideoOutputManager manager;
  std::promise<void> reply;
  auto done = reply.get_future();
  manager.Dispose(999, [&] { reply.set_value(); });
  require(done.wait_for(2s) == std::future_status::ready,
          "missing output did not acknowledge Dispose");
}

void dimensions_use_events_without_querying_mpv_core() {
  ThreadPool pool(1);
  Registrar registrar;
  RenderState state;
  VideoOutput output(pool, registrar, state, 0);
  require(output.GetVideoWidth() == 0 && output.GetVideoHeight() == 0,
          "unknown dimensions should keep the placeholder texture");
  output.SetDisplaySize(854, 480);
  require(output.GetVideoWidth() == 854 && output.GetVideoHeight() == 480,
          "display size event was not applied");
  output.SetDisplaySize(480, 854);
  require(output.GetVideoWidth() == 480 && output.GetVideoHeight() == 854,
          "updated/rotated dimensions were not applied");
  output.SetDisplaySize(std::nullopt, std::nullopt);
  require(output.GetVideoWidth() == 0 && output.GetVideoHeight() == 0,
          "cleared dimensions triggered a synchronous core query");
  // This fixture deliberately has no mpv_get_property declaration: the actual
  // production methods above must compile without any synchronous core API.
}

int main() {
  texture_callbacks_gate_dispose();
  render_queue_gates_dispose();
  software_output_without_texture();
  missing_output_acknowledges_dispose();
  dimensions_use_events_without_querying_mpv_core();
  std::cout << "PASS: 5 native video lifecycle and dimension event tests\n";
}
