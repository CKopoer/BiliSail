import 'dart:async';
import 'dart:ffi';

import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit/generated/libmpv/bindings.dart'
    show mpv_event_hook, mpv_event_property, mpv_event_id;
import 'package:ffi/ffi.dart';

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
  Duration? audioPosition;
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
    resetClocks();
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

  int _clockEpoch = 0;

  void resetClocks() {
    _clockEpoch++;
    audioPosition = null;
  }

  void clockChanged({double? seconds, int? epoch}) {
    if (_disposed || epoch != null && epoch != _clockEpoch) return;
    audioPosition = seconds != null && seconds.isFinite && seconds >= 0
        ? Duration(microseconds: (seconds * 1000000).round())
        : null;
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
    resetClocks();
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

/// A weak client has a separate event queue: never consume media_kit's events
/// or replace its wakeup callback. Owned and released before its native Player.
final class NativeLoadObserver {
  NativeLoadObserver._(
    this.state,
    this._sampleClocks,
    this._pause,
    this._detach,
  );

  final NativeLoadState state;
  final void Function() _sampleClocks;
  final Future<void> Function() _pause;
  final void Function() _detach;
  bool _disposed = false;

  void sampleClocks() {
    if (!_disposed) _sampleClocks();
  }

  Future<void> pause() =>
      _disposed ? Future.error(const SourceSuperseded()) : _pause();

  static Future<NativeLoadObserver> attach(
    mk.NativePlayer platform, {
    required bool Function() isCurrent,
    required void Function(int errorCode) onFailure,
    void Function(String filename)? onExternalAudio,
    FutureOr<void> Function()? onPreloaded,
  }) async {
    final handle = platform.ctx.address;
    if (!isCurrent()) throw const SourceSuperseded();
    final mpv = platform.mpv;
    final client = mpv.mpv_create_weak_client(
      Pointer.fromAddress(handle),
      nullptr,
    );
    if (client == nullptr) {
      throw StateError('Native load observer unavailable.');
    }
    final state = NativeLoadState();
    var detached = false;
    int? pendingClockEpoch;
    Completer<void>? pausing;
    void sampleClocks() {
      // At most one async read may be pending, even if the core never replies.
      if (pendingClockEpoch != null) return;
      pendingClockEpoch = state._clockEpoch;
      final property = 'audio-pts'.toNativeUtf8();
      try {
        if (mpv.mpv_get_property_async(client, 3, property.cast(), 5) < 0) {
          pendingClockEpoch = null;
        }
      } finally {
        calloc.free(property);
      }
    }

    Future<void> pause() {
      if (pausing case final pending?) return pending.future;
      final pending = pausing = Completer<void>();
      final name = 'pause'.toNativeUtf8();
      // MPV_FORMAT_FLAG requires a C int, never a one-byte Dart Bool.
      final value = calloc<Int>()..value = 1;
      try {
        if (mpv.mpv_set_property_async(
              client,
              5,
              name.cast(),
              3,
              value.cast(),
            ) <
            0) {
          pending.completeError(StateError('Native pause request rejected.'));
          pausing = null;
        }
      } finally {
        calloc.free(name);
        calloc.free(value);
      }
      return pending.future;
    }

    Future<void> prepare(int hookId) async {
      try {
        await onPreloaded!();
      } on Object catch (error) {
        if (!detached && isCurrent()) {
          // Keep a safe typed output failure when supplied by the caller.
          state.failPreparation(error: error);
          platform.setProperty('vid', 'no');
        }
      } finally {
        // Detaching destroys the weak client and releases its pending hooks.
        // A late platform-channel reply must not access that destroyed client.
        if (!detached) mpv.mpv_hook_continue(client, hookId);
      }
    }

    // NativeCallable.listener only posts a message from the foreign thread;
    // draining runs on the Dart isolate after the native callback has returned.
    void drain(Pointer<Void> _) {
      if (detached) return;
      while (!detached) {
        final event = mpv.mpv_wait_event(client, 0).ref;
        if (event.event_id == 0) break;
        if (!isCurrent()) continue;
        if (event.event_id == 4 && event.reply_userdata == 5) {
          final pending = pausing;
          pausing = null;
          if (pending != null && !pending.isCompleted) {
            if (event.error < 0) {
              pending.completeError(StateError('Native pause request failed.'));
            } else {
              pending.complete();
            }
          }
          continue;
        }
        if (event.event_id == 3 &&
            event.reply_userdata == 3 &&
            pendingClockEpoch != null) {
          final epoch = pendingClockEpoch;
          pendingClockEpoch = null;
          final property = event.data == nullptr
              ? null
              : event.data.cast<mpv_event_property>().ref;
          state.clockChanged(
            epoch: epoch,
            seconds:
                event.error >= 0 &&
                    property != null &&
                    property.format == 5 &&
                    property.data != nullptr
                ? property.data.cast<Double>().value
                : null,
          );
          continue;
        }
        // These notifications carry no data. A command reply or time-pos
        // update can precede the target frame; wait for the matching restart.
        if (event.event_id == mpv_event_id.MPV_EVENT_SEEK) {
          state.seekStarted();
          continue;
        }
        if (event.event_id == mpv_event_id.MPV_EVENT_PLAYBACK_RESTART) {
          state.playbackRestarted();
          continue;
        }
        if (event.data == nullptr) continue;
        if (event.event_id == 25 && onPreloaded != null) {
          final hookId = event.data.cast<mpv_event_hook>().ref.id;
          unawaited(prepare(hookId));
        } else if (event.event_id == 22) {
          final property = event.data.cast<mpv_event_property>().ref;
          if (event.reply_userdata == 6 || event.reply_userdata == 7) {
            final value = property.format == 1 && property.data != nullptr
                ? property.data.cast<Pointer<Utf8>>().value
                : nullptr;
            state.outputChanged(
              event.reply_userdata == 6
                  ? NativeOutputProperty.colorMatrix
                  : NativeOutputProperty.driver,
              value == nullptr ? null : value.toDartString(),
            );
          }
          if (event.reply_userdata == 1 &&
              onExternalAudio != null &&
              property.format == 1 &&
              property.data != nullptr) {
            final value = property.data.cast<Pointer<Utf8>>().value;
            if (value != nullptr) onExternalAudio(value.toDartString());
          }
        } else if (event.event_id == 6) {
          state.started(event.data.cast<Int64>().value);
        } else if (event.event_id == 7) {
          final end = event.data.cast<_MpvEndFile>().ref;
          final code = end.error;
          if (state.ended(
            entryId: end.entryId,
            reason: end.reason,
            error: code,
          )) {
            onFailure(code);
          }
        }
      }
    }

    final wakeup = NativeCallable<Void Function(Pointer<Void>)>.listener(drain);
    try {
      if (onPreloaded != null) {
        // Output color/VO confirmation can follow decoded dimensions. Keep a
        // source-owned event cache instead of polling the core during startup.
        for (final (id, property) in [
          (6, 'video-out-params/colormatrix'),
          (7, 'current-vo'),
        ]) {
          final name = property.toNativeUtf8();
          try {
            if (mpv.mpv_observe_property(client, id, name.cast(), 1) < 0) {
              throw StateError('Native video output observation unavailable.');
            }
          } finally {
            calloc.free(name);
          }
        }
        final name = 'on_preloaded'.toNativeUtf8();
        try {
          if (mpv.mpv_hook_add(client, 2, name.cast(), 0) < 0) {
            throw StateError('Native video preparation hook unavailable.');
          }
        } finally {
          calloc.free(name);
        }
      }
      if (onExternalAudio != null) {
        final property = 'current-tracks/audio/external-filename'
            .toNativeUtf8();
        try {
          final result = mpv.mpv_observe_property(
            client,
            1,
            property.cast(),
            1,
          );
          if (result < 0) {
            throw StateError('External audio observation unavailable.');
          }
        } finally {
          calloc.free(property);
        }
      }
      mpv.mpv_set_wakeup_callback(client, wakeup.nativeFunction, nullptr);
    } on Object {
      mpv.mpv_destroy(client);
      wakeup.close();
      await state.dispose();
      rethrow;
    }
    return NativeLoadObserver._(state, sampleClocks, pause, () {
      detached = true;
      final pending = pausing;
      if (pending != null && !pending.isCompleted) {
        pending.completeError(const SourceSuperseded());
      }
      mpv.mpv_set_wakeup_callback(client, nullptr, nullptr);
      mpv.mpv_destroy(client);
      // Destroy/unregister first; queued Dart callbacks see detached and never
      // dereference the now invalid client or event data.
      wakeup.close();
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _detach();
    await state.dispose();
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
