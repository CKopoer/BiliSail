// BiliSail lifecycle replacement for media_kit_video 2.0.1 (MIT; see LICENSE).

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

  // libmpv must be freed on its rendering thread while the original GL context
  // still exists. Completion of this task is required before replying Dispose.
  thread_pool_ref_
      ->Post([this] {
        std::lock_guard<std::mutex> lock(textures_mutex_);
        if (render_context_ != nullptr) {
          if (surface_manager_ != nullptr) {
            surface_manager_->MakeCurrent(true);
          }
          mpv_render_context_free(render_context_);
          render_context_ = nullptr;
          if (surface_manager_ != nullptr) {
            surface_manager_->MakeCurrent(false);
          }
        }
        texture_id_ = 0;
        texture_variants_.clear();
        textures_.clear();
        pixel_buffer_textures_.clear();
        surface_manager_.reset();
        pixel_buffer_.reset();
      })
      .get();
}

void VideoOutput::NotifyRender() {
  std::lock_guard<std::mutex> lock(render_tasks_mutex_);
  if (destroyed_) {
    return;
  }
  thread_pool_ref_->Post(std::bind(&VideoOutput::CheckAndResize, this));
  thread_pool_ref_->Post(std::bind(&VideoOutput::Render, this));
}
