// Replaces TexturePlayer from wang-bin/fvp e816374 (BSD-3-Clause).
// The upstream attribution and license remain with the generated source.
class TexturePlayer final : public Player {
 public:
  TexturePlayer(int64_t handle, const ComPtr<ID3D11Texture2D>& target,
                flutter::TextureRegistrar* registrar)
      : Player(reinterpret_cast<mdkPlayerAPI*>(handle)), rt_(target) {
    D3D11_TEXTURE2D_DESC dimensions{};
    rt_->GetDesc(&dimensions);
    descriptor_.struct_size = sizeof(descriptor_);
    descriptor_.format = kFlutterDesktopPixelFormatBGRA8888;
    texture_ = make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
        kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
        [this, registrar](size_t, size_t)
            -> const FlutterDesktopGpuSurfaceDescriptor* {
          scoped_lock lock(mutex_);
          if (revision_ == 0) return nullptr;
          const auto frame = snapshot_.Capture(rt_.Get(), revision_);
          if (snapshot_.pending())
            registrar->MarkTextureFrameAvailable(textureId);
          if (!frame) return nullptr;
          // Keep descriptor metadata alive after Flutter releases its import
          // lease. Flutter 3.47 reads visible dimensions after that callback.
          using Lease = media_kit::D3D11TextureSnapshot::Frame;
          auto lease = make_unique<Lease>(frame);
          D3D11_TEXTURE2D_DESC desc{};
          frame->texture->GetDesc(&desc);
          descriptor_.handle = frame->handle;
          descriptor_.width = descriptor_.visible_width = desc.Width;
          descriptor_.height = descriptor_.visible_height = desc.Height;
          descriptor_.release_context = lease.release();
          descriptor_.release_callback = [](void* context) {
            delete static_cast<Lease*>(context);
          };
          return &descriptor_;
        }));
    textureId = registrar->RegisterTexture(texture_.get());

    D3D11RenderAPI api{};
    api.rtv = rt_.Get();
    setRenderAPI(&api);
    setVideoSurfaceSize(dimensions.Width, dimensions.Height);
    setRenderCallback([this, registrar](void*) {
      scoped_lock lock(mutex_);
      renderVideo();
      ++revision_;
      registrar->MarkTextureFrameAvailable(textureId);
    });
  }

  ~TexturePlayer() override {
    setRenderCallback(nullptr);
    setVideoSurfaceSize(-1, -1);
  }

  int64_t textureId = 0;

 private:
  unique_ptr<flutter::TextureVariant> texture_;
  FlutterDesktopGpuSurfaceDescriptor descriptor_{};
  ComPtr<ID3D11Texture2D> rt_;
  media_kit::D3D11TextureSnapshot snapshot_;
  uint64_t revision_ = 0;
  mutex mutex_;
};
