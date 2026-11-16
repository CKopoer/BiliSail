import 'dart:async';
import 'dart:ffi';

import 'package:media_kit/media_kit.dart' as mk;

import 'package:media_kit/generated/libmpv/bindings.dart' show mpv_event_id;

import 'native_readiness.dart';

enum NativeOutputProperty { colorMatrix, driver }

/// Only an error END_FILE for the matching START_FILE ends a load. Logs, EOF,
/// stop, shutdown and playlist redirects are not terminal load failures.
final class NativeLoadState {
  final _changes = StreamController<void>.broadcast(sync: true);
  int? _entryId;
  int? _errorCode;
  bool _preparationFailed = false;
  Object? _preparationError;
  bool _disposed = false;
  String? videoOutputMatrix;
  String? videoOutputDriver;
  int _seekCount = 0, _restartedSeekCount = 0;
  int _loadCount = 0, _restartedLoadCount = 0;

  int get seekCount => _seekCount;
  int get restartedSeekCount => _restartedSeekCount;
  int get loadCount => _loadCount;
  int get restartedLoadCount => _restartedLoadCount;

  // PLAYBACK_RESTART is emitted after both native decoder chains are ready,
  // including while paused. Old audio metadata alone cannot confirm a seek.
  bool get tracksReady =>
      _loadCount > 0 &&
      _restartedLoadCount == _loadCount &&
      _restartedSeekCount == _seekCount;

  void seekStarted() {
    if (_disposed) return;
    _seekCount++;
    _changes.add(null);
  }

  void playbackRestarted() {
    if (_disposed) return;
    _restartedSeekCount = _seekCount;
    _restartedLoadCount = _loadCount;
    _changes.add(null);
  }

  void outputChanged(NativeOutputProperty property, String? value) {
    if (_disposed) return;
    switch (property) {
      case NativeOutputProperty.colorMatrix:
        videoOutputMatrix = value;
      case NativeOutputProperty.driver:
        videoOutputDriver = value;
    }
    _changes.add(null);
  }

  Stream<void> get changes => _changes.stream;
  int? get errorCode => _errorCode;
  bool get preparationFailed => _preparationFailed;
  Object? get preparationError => _preparationError;

  void failPreparation({Object? error}) {
    if (_disposed || _preparationFailed) return;
    _preparationFailed = true;
    _preparationError = error;
    _changes.add(null);
  }

  void started(int entryId) {
    if (_disposed) return;
    _entryId = entryId;
    _loadCount++;
    _changes.add(null);
  }

  bool ended({required int entryId, required int reason, required int error}) {
    if (_disposed ||
        _errorCode != null ||
        entryId != _entryId ||
        reason != 4 ||
        error >= 0) {
      return false;
    }
    _errorCode = error;
    _changes.add(null);
    return true;
  }

  Future<void> dispose() {
    _disposed = true;
    return _changes.close();
  }
}

/// Adds listeners to media_kit's existing event route. No second mpv client,
/// wakeup callback, hook or polling loop is owned by the application.
final class NativeLoadObserver {
  NativeLoadObserver._(this._platform, this._onFailure);
  final mk.NativePlayer _platform;
  final void Function(int) _onFailure;
  NativeLoadState state = NativeLoadState();
  final _events = <int>[];
  final _properties = <String>[];
  bool _disposed = false;
  bool _idle = false;
  final _idleChanges = StreamController<void>.broadcast(sync: true);

  static Future<NativeLoadObserver> attach(
    mk.NativePlayer platform, {
    required void Function(int errorCode) onFailure,
  }) async {
    final observer = NativeLoadObserver._(platform, onFailure);
    try {
      for (final id in const [
        mpv_event_id.MPV_EVENT_START_FILE,
        mpv_event_id.MPV_EVENT_END_FILE,
        mpv_event_id.MPV_EVENT_SEEK,
        mpv_event_id.MPV_EVENT_PLAYBACK_RESTART,
      ]) {
        await platform.observeEvent(id, (event) async {
          if (observer._disposed) return;
          final state = observer.state;
          // Copy scalar payloads before returning to the SDK event loop.
          switch (id) {
            case mpv_event_id.MPV_EVENT_START_FILE:
              if (event.ref.data != nullptr) {
                observer._idle = false;
                state.started(event.ref.data.cast<Int64>().value);
              }
            case mpv_event_id.MPV_EVENT_END_FILE:
              if (event.ref.data != nullptr) {
                final end = event.ref.data.cast<_MpvEndFile>().ref;
                if (state.ended(
                  entryId: end.entryId,
                  reason: end.reason,
                  error: end.error,
                )) {
                  observer._onFailure(end.error);
                }
              }
            case mpv_event_id.MPV_EVENT_SEEK:
              state.seekStarted();
            case mpv_event_id.MPV_EVENT_PLAYBACK_RESTART:
              state.playbackRestarted();
          }
        });
        observer._events.add(id);
      }
      for (final (name, property) in const [
        ('video-out-params/colormatrix', NativeOutputProperty.colorMatrix),
        ('current-vo', NativeOutputProperty.driver),
      ]) {
        await platform.observeProperty(name, (value) async {
          if (!observer._disposed) {
            observer.state.outputChanged(property, value);
          }
        });
        observer._properties.add(name);
      }
      await platform.observeProperty('idle-active', (value) async {
        if (observer._disposed) return;
        observer._idle = value == 'yes';
        observer._idleChanges.add(null);
      });
      observer._properties.add('idle-active');
      return observer;
    } on Object {
      await observer.dispose();
      rethrow;
    }
  }

  Future<void> waitUntilIdle() => waitForNativeState(
    ready: () => _idle,
    superseded: () => _disposed,
    changes: [_idleChanges.stream],
    timeout: const Duration(seconds: 5),
  );

  /// Called only after Player.stop and its event queue have settled.
  Future<void> reset() async {
    if (_disposed) throw const SourceSuperseded();
    final previous = state;
    state = NativeLoadState();
    await previous.dispose();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final name in _properties) {
      await _platform.unobserveProperty(name);
    }
    for (final id in _events) {
      await _platform.unobserveEvent(id);
    }
    await state.dispose();
    await _idleChanges.close();
  }
}

// Leading ABI fields of mpv_event_end_file, mpv 0.36.0 libmpv/client.h (ISC).
// Source and license: docs/validation/playback-startup.md and
// packages/bili_player/third_party/mpv-client.LICENSE. No generated SDK edits.
final class _MpvEndFile extends Struct {
  @Int32()
  external int reason;
  @Int32()
  external int error;
  @Int64()
  external int entryId;
}
