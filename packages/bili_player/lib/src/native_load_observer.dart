import 'dart:async';
import 'dart:ffi';

import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit/generated/libmpv/bindings.dart' show mpv_event_hook;
import 'package:ffi/ffi.dart';

import 'native_readiness.dart';

/// Only an error END_FILE for the matching START_FILE ends a load. Logs, EOF,
/// stop, shutdown and playlist redirects are not terminal load failures.
final class NativeLoadState {
  final _changes = StreamController<void>.broadcast(sync: true);
  int? _entryId;
  int? _errorCode;
  bool _preparationFailed = false;
  bool _disposed = false;

  Stream<void> get changes => _changes.stream;
  int? get errorCode => _errorCode;
  bool get preparationFailed => _preparationFailed;

  void failPreparation() {
    if (_disposed || _preparationFailed) return;
    _preparationFailed = true;
    _changes.add(null);
  }

  void started(int entryId) {
    if (!_disposed) _entryId = entryId;
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
  NativeLoadObserver._(this.state, this._detach);

  final NativeLoadState state;
  final void Function() _detach;
  bool _disposed = false;

  static Future<NativeLoadObserver> attach(
    mk.NativePlayer platform, {
    required bool Function() isCurrent,
    required void Function(int errorCode) onFailure,
    void Function(String filename)? onExternalAudio,
    void Function()? onPreloaded,
  }) async {
    final handle = platform.handle;
    if (!isCurrent()) throw const SourceSuperseded();
    final mpv = mk.NativePlayer.mpv;
    final client = mpv.mpv_create_weak_client(
      Pointer.fromAddress(handle),
      nullptr,
    );
    if (client == nullptr) {
      throw StateError('Native load observer unavailable.');
    }
    final state = NativeLoadState();
    var detached = false;
    // NativeCallable.listener only posts a message from the foreign thread;
    // draining runs on the Dart isolate after the native callback has returned.
    void drain(Pointer<Void> _) {
      if (detached) return;
      while (!detached) {
        final event = mpv.mpv_wait_event(client, 0).ref;
        if (event.event_id == 0) break;
        if (!isCurrent() || event.data == nullptr) continue;
        if (event.event_id == 25 && onPreloaded != null) {
          final hookId = event.data.cast<mpv_event_hook>().ref.id;
          try {
            onPreloaded();
          } on Object {
            // Do not leak native strings or leave the loading core blocked.
            state.failPreparation();
          } finally {
            mpv.mpv_hook_continue(client, hookId);
          }
        } else if (event.event_id == 22 && onExternalAudio != null) {
          final property = event.data.cast<_MpvEventProperty>().ref;
          if (property.format == 1 && property.data != nullptr) {
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
    return NativeLoadObserver._(state, () {
      detached = true;
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

// mpv_event_property layout from the same public client ABI as END_FILE.
final class _MpvEventProperty extends Struct {
  external Pointer<Utf8> name;
  @Int32()
  external int format;
  external Pointer<Void> data;
}
