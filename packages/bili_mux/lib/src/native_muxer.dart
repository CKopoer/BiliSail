import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

enum MuxFailure {
  unavailable,
  cancelled,
  input,
  output,
  verification,
  internal,
  timeout,
}

final class MuxException implements Exception {
  const MuxException(this.failure);
  final MuxFailure failure;
  @override
  String toString() => 'MuxException(${failure.name})';
}

/// Cancellation belongs to a single merge operation, not a widget/player.
final class MuxCancellation {
  bool _cancelled = false;
  void Function()? _listener;
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _listener?.call();
  }
}

/// An opaque native job runs in a worker isolate. Only atomic cancellation and
/// progress queries execute on the calling isolate; it never copies media data.
final class NativeMuxer {
  NativeMuxer({String? libraryPath}) : _path = libraryPath ?? _defaultPath();
  final String? _path;
  _Bindings? _bindings;
  bool _attempted = false;

  bool get available => _load() != null;

  _Bindings? _load() {
    if (!_attempted) {
      _attempted = true;
      final path = _path;
      if (path != null) {
        try {
          final bindings = _Bindings(path);
          if (bindings.abi() == 1) _bindings = bindings;
        } on ArgumentError {
          // An absent/incompatible asset is a capability failure. Existing
          // separate-track downloads and playback remain usable.
        }
      }
    }
    return _bindings;
  }

  Future<void> merge({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    required MuxCancellation cancellation,
    void Function(double)? onProgress,
  }) async {
    if (cancellation.isCancelled) {
      throw const MuxException(MuxFailure.cancelled);
    }
    final bindings = _load();
    final path = _path;
    if (bindings == null || path == null) {
      throw const MuxException(MuxFailure.unavailable);
    }
    if (cancellation._listener != null) {
      throw StateError('A cancellation token may own only one active merge');
    }
    for (final value in [videoPath, audioPath, outputPath]) {
      if (value.contains('\u0000') || !File(value).isAbsolute) {
        throw const MuxException(MuxFailure.input);
      }
    }
    final arena = Arena();
    late final Pointer<Void> job;
    try {
      job = bindings.create(
        videoPath.toNativeUtf8(allocator: arena),
        audioPath.toNativeUtf8(allocator: arena),
        outputPath.toNativeUtf8(allocator: arena),
      );
    } finally {
      arena.releaseAll();
    }
    if (job == nullptr) throw const MuxException(MuxFailure.input);
    Timer? timer;
    try {
      cancellation._listener = () => bindings.cancel(job);
      if (cancellation.isCancelled) bindings.cancel(job);
      var lastProgress = -1;
      timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        final progress = bindings.progress(job);
        if (progress != lastProgress) {
          lastProgress = progress;
          onProgress?.call(progress / 10000);
        }
      });
      final address = job.address;
      // Send only scalars; never capture the bindings/library/cancellation in
      // the worker closure. The job stays alive until this future completes.
      final status = await _runWorker(path, address);
      if (cancellation.isCancelled || status == 1) {
        throw const MuxException(MuxFailure.cancelled);
      }
      if (status != 0) {
        throw MuxException(switch (status) {
          2 => MuxFailure.input,
          3 => MuxFailure.output,
          4 => MuxFailure.verification,
          6 => MuxFailure.timeout,
          _ => MuxFailure.internal,
        });
      }
      onProgress?.call(1);
    } finally {
      timer?.cancel();
      cancellation._listener = null;
      bindings.destroy(job);
    }
  }

  static Future<int> _runWorker(String path, int address) => Isolate.run(
    () => _Bindings(path).run(Pointer<Void>.fromAddress(address)),
  );

  static String? _defaultPath() {
    if (Platform.isWindows) {
      return '${File(Platform.resolvedExecutable).parent.path}/bili_mux.dll';
    }
    if (Platform.isAndroid) return 'libbili_mux.so';
    if (Platform.isMacOS) {
      return File(Platform.resolvedExecutable).uri
          .resolve('../Frameworks/BiliMux.framework/BiliMux')
          .toFilePath();
    }
    return null;
  }
}

final class _Bindings {
  _Bindings(String path) : _library = DynamicLibrary.open(path);
  final DynamicLibrary _library;
  late final abi = _library.lookupFunction<Int32 Function(), int Function()>(
    'bili_mux_abi',
  );
  late final create = _library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)
      >('bili_mux_create');
  late final run = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('bili_mux_run');
  late final cancel = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('bili_mux_cancel');
  late final progress = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('bili_mux_progress');
  late final destroy = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('bili_mux_destroy');
}
