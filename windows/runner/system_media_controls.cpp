#include "system_media_controls.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <SystemMediaTransportControlsInterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <deque>
#include <mutex>
#include <string>
#include <utility>

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
using namespace winrt::Windows::Media;

template <typename T>
T Read(const EncodableMap& map, const char* key, T fallback = {}) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  const auto* value = std::get_if<T>(&it->second);
  return value ? *value : fallback;
}

int64_t ReadMilliseconds(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return 0;
  if (const auto* value = std::get_if<int64_t>(&it->second)) return *value;
  if (const auto* value = std::get_if<int32_t>(&it->second)) return *value;
  return 0;
}

struct Command {
  std::string id;
  std::string action;
  int64_t position_ms = 0;
};

struct CommandQueue {
  std::mutex mutex;
  HWND window = nullptr;
  std::string id;
  bool active = false;
  bool closed = false;
  std::deque<Command> commands;

  void Push(std::string action, int64_t position_ms = 0) {
    std::lock_guard<std::mutex> lock(mutex);
    if (closed || !active || commands.size() >= 32) return;
    commands.push_back({id, std::move(action), position_ms});
    PostMessage(window, SystemMediaControlsChannel::kCommandMessage, 0, 0);
  }
};
}  // namespace

class SystemMediaControlsChannel::Impl {
 public:
  Impl(flutter::BinaryMessenger* messenger, HWND window)
      : window_(window), queue_(std::make_shared<CommandQueue>()),
        channel_(messenger, "bilisail/system_media",
                 &flutter::StandardMethodCodec::GetInstance()) {
    queue_->window = window;
    channel_.SetMethodCallHandler([this](const auto& call, auto result) {
      try {
        if (call.method_name() == "clear") {
          Clear();
        } else if (call.method_name() == "update") {
          const auto* args = call.arguments()
                                 ? std::get_if<EncodableMap>(call.arguments())
                                 : nullptr;
          if (!args) {
            result->Error("invalid_argument", "Expected media state.");
            return;
          }
          Update(*args);
        } else {
          result->NotImplemented();
          return;
        }
        result->Success();
      } catch (const winrt::hresult_error&) {
        result->Error("system_media_unavailable", "System media controls unavailable.");
      }
    });
  }

  ~Impl() {
    {
      std::lock_guard<std::mutex> lock(queue_->mutex);
      queue_->closed = true;
      queue_->commands.clear();
    }
    channel_.SetMethodCallHandler(nullptr);
    try {
      if (controls_) {
        controls_.ButtonPressed(button_token_);
        controls_.PlaybackPositionChangeRequested(position_token_);
        controls_.IsEnabled(false);
      }
    } catch (const winrt::hresult_error&) {
      // The window or system media broker can already be gone during shutdown.
    }
  }

  void DispatchCommands() {
    std::deque<Command> commands;
    {
      std::lock_guard<std::mutex> lock(queue_->mutex);
      commands.swap(queue_->commands);
    }
    for (const auto& command : commands) {
      channel_.InvokeMethod("command", std::make_unique<EncodableValue>(EncodableMap{
          {EncodableValue("id"), EncodableValue(command.id)},
          {EncodableValue("action"), EncodableValue(command.action)},
          {EncodableValue("positionMs"), EncodableValue(command.position_ms)},
      }));
    }
  }

 private:
  void Initialize() {
    if (controls_) return;
    const auto interop = winrt::get_activation_factory<
        SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(interop->GetForWindow(
        window_, winrt::guid_of<SystemMediaTransportControls>(),
        winrt::put_abi(controls_)));
    const auto queue = queue_;
    button_token_ = controls_.ButtonPressed([queue](const auto&, const auto& args) {
      switch (args.Button()) {
        case SystemMediaTransportControlsButton::Play: queue->Push("play"); break;
        case SystemMediaTransportControlsButton::Pause: queue->Push("pause"); break;
        case SystemMediaTransportControlsButton::Stop: queue->Push("stop"); break;
        default: break;
      }
    });
    position_token_ = controls_.PlaybackPositionChangeRequested(
        [queue](const auto&, const auto& args) {
          queue->Push("seek", args.RequestedPlaybackPosition().count() / 10000);
        });
    controls_.IsNextEnabled(false);
    controls_.IsPreviousEnabled(false);
    controls_.IsFastForwardEnabled(false);
    controls_.IsRewindEnabled(false);
  }

  void Clear() {
    {
      std::lock_guard<std::mutex> lock(queue_->mutex);
      queue_->active = false;
      queue_->id.clear();
      queue_->commands.clear();
    }
    if (!controls_) return;
    controls_.PlaybackStatus(MediaPlaybackStatus::Stopped);
    controls_.IsEnabled(false);
    controls_.DisplayUpdater().ClearAll();
    controls_.DisplayUpdater().Update();
    metadata_.clear();
  }

  void Update(const EncodableMap& args) {
    Initialize();
    const auto id = Read<std::string>(args, "id");
    const auto title = Read<std::string>(args, "title");
    const auto artist = Read<std::string>(args, "artist");
    const auto art_uri = Read<std::string>(args, "artUri");
    const auto metadata = id + '\n' + title + '\n' + artist + '\n' + art_uri;
    if (metadata != metadata_) {
      auto updater = controls_.DisplayUpdater();
      updater.ClearAll();
      updater.Type(MediaPlaybackType::Video);
      updater.VideoProperties().Title(winrt::to_hstring(title));
      updater.VideoProperties().Subtitle(winrt::to_hstring(artist));
      if (!art_uri.empty()) {
        updater.Thumbnail(winrt::Windows::Storage::Streams::RandomAccessStreamReference::
            CreateFromUri(winrt::Windows::Foundation::Uri(winrt::to_hstring(art_uri))));
      }
      updater.Update();
      metadata_ = metadata;
    }
    const auto can_seek = Read<bool>(args, "canSeek");
    const auto duration_ms = can_seek ? std::max<int64_t>(0, ReadMilliseconds(args, "durationMs")) : 0;
    const auto position_ms = std::clamp<int64_t>(ReadMilliseconds(args, "positionMs"), 0, duration_ms);
    SystemMediaTransportControlsTimelineProperties timeline;
    using winrt::Windows::Foundation::TimeSpan;
    timeline.StartTime(TimeSpan{0});
    timeline.MinSeekTime(TimeSpan{0});
    timeline.EndTime(TimeSpan{duration_ms * 10000});
    timeline.MaxSeekTime(TimeSpan{duration_ms * 10000});
    timeline.Position(TimeSpan{position_ms * 10000});
    controls_.UpdateTimelineProperties(timeline);
    controls_.PlaybackRate(Read<double>(args, "rate", 1.0));
    controls_.IsPlayEnabled(true);
    controls_.IsPauseEnabled(true);
    controls_.IsStopEnabled(true);
    const auto phase = Read<std::string>(args, "phase");
    const auto playing = Read<bool>(args, "playing");
    controls_.PlaybackStatus(phase == "completed" || phase == "failed"
        ? MediaPlaybackStatus::Stopped
        : playing && (phase == "loading" || phase == "buffering")
        ? MediaPlaybackStatus::Changing
        : playing ? MediaPlaybackStatus::Playing : MediaPlaybackStatus::Paused);
    {
      std::lock_guard<std::mutex> lock(queue_->mutex);
      if (queue_->id != id) queue_->commands.clear();
      queue_->id = id;
      queue_->active = true;
    }
    controls_.IsEnabled(true);
  }

  HWND window_;
  std::shared_ptr<CommandQueue> queue_;
  flutter::MethodChannel<EncodableValue> channel_;
  SystemMediaTransportControls controls_{nullptr};
  winrt::event_token button_token_{};
  winrt::event_token position_token_{};
  std::string metadata_;
};

SystemMediaControlsChannel::SystemMediaControlsChannel(
    flutter::BinaryMessenger* messenger, HWND window)
    : impl_(std::make_unique<Impl>(messenger, window)) {}
SystemMediaControlsChannel::~SystemMediaControlsChannel() = default;
void SystemMediaControlsChannel::DispatchCommands() { impl_->DispatchCommands(); }
