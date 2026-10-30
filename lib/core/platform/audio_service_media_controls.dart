import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:flutter/foundation.dart';

import 'system_media_controls.dart';
import 'windows_media_controls.dart';

Future<SystemMediaControls> createSystemMediaControls() async {
  if (Platform.isWindows) return WindowsMediaControls();
  if (Platform.isLinux) {
    AudioServiceMpris.init(
      dBusName: 'bilisail',
      identity: 'BiliSail',
      desktopEntry: 'dev.bilisail.bilisail',
      canControl: true,
      canPlay: true,
      canPause: true,
    );
  }
  final controls = AudioServiceMediaControls();
  controls._errors = AudioService.asyncError.listen(
    (_) => reportSystemMediaFailure(),
  );
  try {
    await AudioService.init(
      builder: () => controls.handler,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.bilisail.bilisail.playback',
        androidNotificationChannelName: '视频播放',
        androidNotificationChannelDescription: '播放状态与媒体控制',
        androidNotificationIcon: 'drawable/ic_media_notification',
        // Reopening audio or advancing a playlist briefly pauses the engine.
        // Keep the foreground service until stop/close so background playback
        // does not depend on permission to start a new foreground service.
        androidStopForegroundOnPause: false,
        preloadArtwork: false,
        artDownscaleWidth: 512,
        artDownscaleHeight: 512,
      ),
    );
  } catch (_) {
    await controls.close();
    rethrow;
  }
  return controls;
}

final class AudioServiceMediaControls extends SystemMediaControls {
  AudioServiceMediaControls() {
    handler = _MediaHandler(this);
  }

  late final BaseAudioHandler handler;
  SystemMediaState? _state;
  Object? _metadata;
  bool _closed = false;
  StreamSubscription<Object>? _errors;

  @override
  void publish(SystemMediaState? state) {
    if (_closed) return;
    _state = state;
    if (state == null) {
      _metadata = null;
      handler.mediaItem.add(null);
      handler.playbackState.add(PlaybackState());
      return;
    }
    final metadata = (
      state.id,
      state.title,
      state.artist,
      state.artUri,
      state.duration,
      state.isLive,
    );
    if (_metadata != metadata) {
      _metadata = metadata;
      handler.mediaItem.add(
        MediaItem(
          id: state.id,
          title: state.title,
          artist: state.artist,
          album: 'BiliSail',
          artUri: state.artUri,
          duration: state.isLive ? null : state.duration,
          isLive: state.isLive,
        ),
      );
    }
    handler.playbackState.add(
      PlaybackState(
        controls: [
          state.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1],
        systemActions: {if (state.canSeek) MediaAction.seek},
        processingState: switch (state.phase) {
          SystemMediaPhase.loading => AudioProcessingState.loading,
          SystemMediaPhase.ready => AudioProcessingState.ready,
          SystemMediaPhase.buffering => AudioProcessingState.buffering,
          SystemMediaPhase.completed => AudioProcessingState.completed,
          SystemMediaPhase.failed => AudioProcessingState.error,
        },
        playing: state.playing,
        updatePosition: state.isLive ? Duration.zero : state.position,
        bufferedPosition: state.isLive ? Duration.zero : state.buffered,
        speed: state.rate,
        errorCode: state.phase == SystemMediaPhase.failed ? 1 : null,
        errorMessage: state.phase == SystemMediaPhase.failed ? '视频播放失败' : null,
      ),
    );
  }

  Future<void> _command(SystemMediaAction action, [Duration? position]) async {
    final state = _state;
    if (_closed ||
        state == null ||
        (action == SystemMediaAction.seek && !state.canSeek)) {
      return;
    }
    await onCommand?.call(
      SystemMediaCommand(state.id, action, position: position),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    publish(null);
    _closed = true;
    onCommand = null;
    await _errors?.cancel();
    // audio_service observes these subjects for the lifetime of the engine.
    // Keep them open until the engine exits so pending native callbacks see idle.
  }
}

final class _MediaHandler extends BaseAudioHandler {
  _MediaHandler(this.controls);
  final AudioServiceMediaControls controls;

  @override
  Future<void> play() => controls._command(SystemMediaAction.play);
  @override
  Future<void> pause() => controls._command(SystemMediaAction.pause);
  @override
  Future<void> stop() => controls._command(SystemMediaAction.stop);
  @override
  Future<void> seek(Duration position) =>
      controls._command(SystemMediaAction.seek, position);
  @override
  Future<void> onTaskRemoved() => controls._command(SystemMediaAction.stopAll);
}

/// Notification failures must not turn a valid media source into a playback
/// failure. Report a fixed message without plugin exceptions or media URLs.
void reportSystemMediaFailure() {
  debugPrint('System media controls are unavailable.');
}
