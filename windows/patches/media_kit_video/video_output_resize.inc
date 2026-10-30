// BiliSail stable texture registration for Predidit media-kit 83b7ca6 (MIT).
void VideoOutput::Resize(int64_t required_width, int64_t required_height) {
  std::lock_guard<std::mutex> lock(textures_mutex_);
  if (d3d11_renderer_ != nullptr) {
    // Retain the last completed allocation before the mailbox releases its
    // slots. A first-frame GPU timeout can continue displaying this frame.
    if (auto* texture = d3d11_renderer_->ReadTextureSnapshot()) {
      last_video_texture_ = texture;
      last_video_handle_ = d3d11_renderer_->ConsumerAcquire();
    }
    d3d11_renderer_->SetSize(static_cast<int32_t>(required_width),
                             static_cast<int32_t>(required_height));
    // Finish the new allocation's first redraw before the consumer can acquire
    // it. This is also needed for paused video, which has no next video frame.
    if (render_context_ != nullptr) {
      mpv_render_context_render(render_context_, nullptr);
      mpv_render_context_report_swap(render_context_);
      d3d11_renderer_->ProducerCommit();
    }
    if (texture_id_ == 0) {
      auto descriptor = std::make_unique<FlutterDesktopGpuSurfaceDescriptor>();
      auto variant =
          std::make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
              kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
              [this](auto, auto) -> const FlutterDesktopGpuSurfaceDescriptor* {
                std::lock_guard<std::mutex> frame_lock(textures_mutex_);
                if (destroyed_) return nullptr;
                if (auto* texture = d3d11_renderer_->ReadTextureSnapshot()) {
                  last_video_texture_ = texture;
                  last_video_handle_ = d3d11_renderer_->ConsumerAcquire();
                }
                if (!last_video_texture_) return nullptr;
                using TextureReference =
                    Microsoft::WRL::ComPtr<ID3D11Texture2D>;
                auto reference =
                    std::make_unique<TextureReference>(last_video_texture_);
                D3D11_TEXTURE2D_DESC dimensions{};
                reference->Get()->GetDesc(&dimensions);
                auto& descriptor = *textures_.at(texture_id_);
                descriptor.struct_size = sizeof(descriptor);
                descriptor.handle = last_video_handle_;
                descriptor.width = descriptor.visible_width = dimensions.Width;
                descriptor.height = descriptor.visible_height =
                    dimensions.Height;
                descriptor.format = kFlutterDesktopPixelFormatBGRA8888;
                descriptor.release_context = reference.release();
                descriptor.release_callback = [](void* context) {
                  delete static_cast<TextureReference*>(context);
                };
                // Flutter 3.47 reads visible dimensions AFTER release_callback.
                // Only the COM lease is released there; the descriptor remains
                // alive until this texture is unregistered.
                return &descriptor;
              }));
      texture_id_ =
          registrar_->texture_registrar()->RegisterTexture(variant.get());
      textures_.emplace(texture_id_, std::move(descriptor));
      texture_variants_.emplace(texture_id_, std::move(variant));
    }
  } else if (pixel_buffer_ != nullptr) {
    auto descriptor = std::make_unique<FlutterDesktopPixelBuffer>();
    descriptor->buffer = pixel_buffer_.get();
    descriptor->width = required_width;
    descriptor->height = required_height;
    descriptor->release_context = nullptr;
    descriptor->release_callback = [](void*) {};
    if (texture_id_ == 0) {
      auto variant = std::make_unique<flutter::TextureVariant>(
          flutter::PixelBufferTexture([this](auto, auto) {
            std::lock_guard<std::mutex> frame_lock(textures_mutex_);
            if (destroyed_)
              return static_cast<FlutterDesktopPixelBuffer*>(nullptr);
            // Keep callback metadata alive across a concurrent producer resize.
            last_pixel_buffer_ = *pixel_buffer_textures_.at(texture_id_);
            return &last_pixel_buffer_;
          }));
      texture_id_ =
          registrar_->texture_registrar()->RegisterTexture(variant.get());
      texture_variants_.emplace(texture_id_, std::move(variant));
    }
    pixel_buffer_textures_[texture_id_] = std::move(descriptor);
  }
  // Layout changes update dimensions, never unregister the live texture.
  texture_update_callback_(texture_id_, required_width, required_height);
}
