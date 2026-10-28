// BiliSail lifecycle replacement for Predidit media-kit 83b7ca6 (MIT; see LICENSE).

void VideoOutput::UnregisterTexture(int64_t id,
                                    std::function<void()> callback) {
  {
    std::lock_guard<std::mutex> lock(texture_release_mutex_);
    ++pending_texture_releases_;
  }
  registrar_->texture_registrar()->UnregisterTexture(
      id, [this, callback = std::move(callback)]() {
        callback();
        std::lock_guard<std::mutex> lock(texture_release_mutex_);
        --pending_texture_releases_;
        textures_released_.notify_all();
      });
}

VideoOutput::~VideoOutput() {
  {
    // A callback that already entered NotifyRender must finish posting before
    // the drain barrier; later callbacks cannot post work referring to this.
    std::lock_guard<std::mutex> lock(render_tasks_mutex_);
    destroyed_ = true;
  }
  if (render_context_ != nullptr) {
    mpv_render_context_set_update_callback(render_context_, nullptr, nullptr);
  }
  thread_pool_ref_->Post([] {}).get();

  // Resize may have left older unregister callbacks in flight as well. Keep
  // this object alive until all of them finish, including the current texture.
  if (texture_id_ != 0) {
    UnregisterTexture(texture_id_, [] {});
  }
  {
    std::unique_lock<std::mutex> lock(texture_release_mutex_);
    textures_released_.wait(lock,
                            [this] { return pending_texture_releases_ == 0; });
  }

  // libmpv must be freed on its rendering thread while the D3D11 device
  // and mailbox swap chain still exist. Completion of this task is required before replying Dispose.
  thread_pool_ref_
      ->Post([this] {
        std::lock_guard<std::mutex> lock(textures_mutex_);
        if (render_context_ != nullptr) {
          mpv_render_context_free(render_context_);
          render_context_ = nullptr;
        }
        texture_id_ = 0;
        texture_variants_.clear();
        textures_.clear();
        pixel_buffer_textures_.clear();
        d3d11_renderer_.reset();
        pixel_buffer_.reset();
      })
      .get();
}

void VideoOutput::NotifyRender() {
  std::lock_guard<std::mutex> lock(render_tasks_mutex_);
  if (destroyed_) {
    return;
  }
  if (rendering_) {
    // mpv may report another update while Render is consuming the previous
    // one. Keep one more pass so that wakeup is not lost.
    render_again_ = true;
    return;
  }
  if (render_task_queued_) {
    // The queued pass will consume the newest available frame.
    return;
  }
  render_task_queued_ = true;
  thread_pool_ref_->Post(std::bind(&VideoOutput::RenderQueued, this));
}

void VideoOutput::RenderQueued() {
  {
    std::lock_guard<std::mutex> lock(render_tasks_mutex_);
    render_task_queued_ = false;
    if (destroyed_) {
      return;
    }
    rendering_ = true;
  }
  CheckAndResize();
  Render();
  std::lock_guard<std::mutex> lock(render_tasks_mutex_);
  rendering_ = false;
  if (destroyed_ || !render_again_) {
    render_again_ = false;
    return;
  }
  render_again_ = false;
  render_task_queued_ = true;
  // Enqueue at the tail so another player's frame/size task can run first.
  thread_pool_ref_->Post(std::bind(&VideoOutput::RenderQueued, this));
}
