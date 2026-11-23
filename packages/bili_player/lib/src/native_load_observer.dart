import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as mpv;
import 'package:media_kit/media_kit.dart' as mk;

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

/// Reads the BiliSail track/seek events on an independent weak mpv client.
/// The SDK keeps exclusive ownership of its player and native wakeup callback.
final class NativeLoadObserver {
  NativeLoadObserver._(this._onFailure);
  final void Function(int) _onFailure;
  NativeLoadState state = NativeLoadState();
  final _messages = ReceivePort();
  final _idleChanges = StreamController<void>.broadcast(sync: true);
  final _ready = Completer<SendPort>();
  late final Future<void> _worker;
  bool _idle = false;
  bool _disposed = false;

  static Future<NativeLoadObserver> attach(
    mk.NativePlayer player, {
    required void Function(int errorCode) onFailure,
  }) async {
    final observer = NativeLoadObserver._(onFailure);
    observer._messages.listen(observer._receive);
    final args = (
      await player.handle,
      player.nativeLibraryPath,
      observer._messages.sendPort,
    );
    observer._worker = _runEventReader(args);
    unawaited(
      observer._worker.then(
        (_) {
          if (!observer._ready.isCompleted) {
            observer._ready.completeError(
              StateError('Native event reader closed during startup.'),
            );
          } else if (!observer._disposed) {
            observer.state.failPreparation(
              error: StateError('Native event reader stopped.'),
            );
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!observer._ready.isCompleted) {
            observer._ready.completeError(error, stack);
          } else if (!observer._disposed) {
            observer.state.failPreparation(error: error);
          }
        },
      ),
    );
    try {
      await observer._ready.future;
      return observer;
    } on Object {
      observer._messages.close();
      await observer.state.dispose();
      await observer._idleChanges.close();
      rethrow;
    }
  }

  void _receive(Object? message) {
    if (_disposed) return;
    switch (message) {
      case SendPort stop:
        _ready.complete(stop);
      case (mpv.mpv_event_id.MPV_EVENT_START_FILE, int entry):
        _idle = false;
        state.started(entry);
      case (
        mpv.mpv_event_id.MPV_EVENT_END_FILE,
        int entry,
        int reason,
        int code,
      ):
        if (state.ended(entryId: entry, reason: reason, error: code)) {
          _onFailure(code);
        }
      case mpv.mpv_event_id.MPV_EVENT_SEEK:
        state.seekStarted();
      case mpv.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART:
        state.playbackRestarted();
      case (NativeOutputProperty property, String? value):
        state.outputChanged(property, value);
      case bool idle:
        _idle = idle;
        _idleChanges.add(null);
    }
  }

  Future<void> waitUntilIdle() => waitForNativeState(
    ready: () => _idle,
    superseded: () => _disposed,
    changes: [_idleChanges.stream],
    timeout: const Duration(seconds: 5),
  );

  Future<void> reset() async {
    if (_disposed) throw const SourceSuperseded();
    final previous = state;
    state = NativeLoadState();
    await previous.dispose();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    (await _ready.future).send(null);
    try {
      await _worker;
    } finally {
      _messages.close();
      await state.dispose();
      await _idleChanges.close();
    }
  }
}

typedef _ReaderArgs = (int, String, SendPort);

Future<void> _runEventReader(_ReaderArgs args) => Isolate.run(
  () => _readNativeEvents(args),
  debugName: 'BiliSail mpv events',
);

final class _WeakClient implements Finalizable {
  _WeakClient(this.library, this.api, this.handle)
    : finalizer = NativeFinalizer(library.lookup('mpv_destroy')) {
    finalizer.attach(this, handle.cast(), detach: this);
  }
  final DynamicLibrary library;
  final mpv.MPV api;
  final Pointer<mpv.mpv_handle> handle;
  final NativeFinalizer finalizer;

  void close() {
    finalizer.detach(this);
    api.mpv_destroy(handle);
  }
}

Future<void> _readNativeEvents(_ReaderArgs args) async {
  final (address, path, target) = args;
  final library = DynamicLibrary.open(path);
  final api = mpv.MPV(library);
  final handle = api.mpv_create_weak_client(
    Pointer.fromAddress(address),
    nullptr,
  );
  if (handle == nullptr) {
    throw StateError('Could not attach to the mpv event queue.');
  }
  final client = _WeakClient(library, api, handle);
  final control = ReceivePort();
  var active = true;
  control.listen((_) => active = false);
  try {
    const properties = [
      'video-out-params/colormatrix',
      'current-vo',
      'idle-active',
    ];
    for (var i = 0; i < properties.length; i++) {
      final key = properties[i].toNativeUtf8();
      try {
        if (api.mpv_observe_property(
              handle,
              i + 1,
              key.cast(),
              mpv.mpv_format.MPV_FORMAT_STRING,
            ) <
            0) {
          throw StateError('Could not observe ${properties[i]}.');
        }
      } finally {
        calloc.free(key);
      }
    }
    target.send(control.sendPort);
    // Events wake the native wait immediately. Its upper bound only lets the
    // worker service cancellation when the player is completely idle.
    while (active) {
      final event = api.mpv_wait_event(handle, 0.1).ref;
      switch (event.event_id) {
        case mpv.mpv_event_id.MPV_EVENT_SHUTDOWN:
          return;
        case mpv.mpv_event_id.MPV_EVENT_START_FILE:
          if (event.data != nullptr) {
            target.send((
              event.event_id,
              event.data.cast<mpv.mpv_event_start_file>().ref.playlist_entry_id,
            ));
          }
        case mpv.mpv_event_id.MPV_EVENT_END_FILE:
          if (event.data != nullptr) {
            final end = event.data.cast<mpv.mpv_event_end_file>().ref;
            target.send((
              event.event_id,
              end.playlist_entry_id,
              end.reason,
              end.error,
            ));
          }
        case mpv.mpv_event_id.MPV_EVENT_SEEK:
        case mpv.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART:
          target.send(event.event_id);
        case mpv.mpv_event_id.MPV_EVENT_PROPERTY_CHANGE:
          final property = event.data.cast<mpv.mpv_event_property>().ref;
          final value =
              property.format == mpv.mpv_format.MPV_FORMAT_STRING &&
                  property.data != nullptr
              ? property.data.cast<Pointer<Utf8>>().value.toDartString()
              : null;
          switch (event.reply_userdata) {
            case 1:
              target.send((NativeOutputProperty.colorMatrix, value));
            case 2:
              target.send((NativeOutputProperty.driver, value));
            case 3:
              target.send(value == 'yes');
          }
      }
      await Future<void>.delayed(Duration.zero);
    }
  } finally {
    control.close();
    client.close();
  }
}
