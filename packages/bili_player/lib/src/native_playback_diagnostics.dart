import 'dart:async';

/// A fixed property allowlist: never read paths, track IDs, URLs or metadata.
/// Units and names follow mpv's public property API. Missing is not zero.
final class NativePlaybackSample {
  NativePlaybackSample._(
    this.values,
    this.unavailable,
    this.elapsedMs,
    this.durationMs,
    this.timedOut,
  );

  static const _numbers = {
    'speed',
    'avsync',
    'total-avsync-change',
    'video-pts',
    'audio-pts',
    'time-pos',
    'container-fps',
    'estimated-vf-fps',
    'frame-drop-count',
    'decoder-frame-drop-count',
    'mistimed-frame-count',
    'vo-delayed-frame-count',
    'demuxer-cache-duration',
    'cache-speed',
    'demuxer-cache-state/raw-input-rate',
    'audio-delay',
    'audio-buffer',
    'audio-speed-correction',
    'video-speed-correction',
    'display-fps',
    'estimated-display-fps',
    'vd-queue-max-samples',
    'vd-queue-max-secs',
    'vd-queue-max-bytes',
  };
  static const _flags = {
    'pause',
    'paused-for-cache',
    'seeking',
    'core-idle',
    'display-sync-active',
    'vd-queue-enable',
    'audio-pitch-correction',
  };
  static const _choices = <String, Set<String>>{
    'hwdec-current': {
      'no',
      'mediacodec',
      'mediacodec-copy',
      'd3d11va',
      'd3d11va-copy',
      'dxva2',
      'dxva2-copy',
      'videotoolbox',
      'videotoolbox-copy',
      'vaapi',
      'vaapi-copy',
      'vdpau',
      'vdpau-copy',
      'nvdec',
      'nvdec-copy',
      'vulkan',
      'vulkan-copy',
      'drm',
      'drm-copy',
    },
    'hwdec': {'no', 'auto', 'auto-safe', 'auto-copy', 'mediacodec,auto-safe'},
    'current-vo': {'gpu', 'gpu-next', 'libmpv', 'mediacodec_embed', 'null'},
    'video-format': {
      'h264',
      'hevc',
      'av1',
      'vp9',
      'vp8',
      'mpeg4',
      'mpeg2video',
    },
    'audio-codec-name': {
      'aac',
      'mp3',
      'flac',
      'opus',
      'vorbis',
      'ac3',
      'eac3',
      'alac',
      'pcm_s16le',
      'pcm_s24le',
      'pcm_s32le',
      'pcm_f32le',
    },
    'video-sync': {
      'audio',
      'display-resample',
      'display-tempo',
      'display-vdrop',
      'display-adrop',
      'display-desync',
      'desync',
    },
    'framedrop': {'no', 'vo', 'decoder', 'decoder+vo'},
    'video-params/pixelformat': {
      'mediacodec',
      'd3d11',
      'videotoolbox',
      'vaapi',
      'nv12',
      'p010',
      'yuv420p',
      'yuv420p10le',
      'yuv444p',
      'rgb0',
      'rgba',
    },
    'video-params/gamma': {
      'bt.1886',
      'srgb',
      'linear',
      'pq',
      'hlg',
      'gamma2.2',
      'gamma2.8',
    },
    'video-params/colormatrix': {
      'bt.601',
      'bt.709',
      'bt.2020-ncl',
      'bt.2020-cl',
      'rgb',
    },
  };
  static final properties = List<String>.unmodifiable([
    ..._numbers,
    ..._flags,
    ..._choices.keys,
    'mpv-version',
    'ffmpeg-version',
  ]);

  factory NativePlaybackSample.fromProperties(
    Map<String, String> raw, {
    required int elapsedMs,
    required int durationMs,
    bool timedOut = false,
  }) {
    final values = <String, Object>{};
    final unavailable = <String>[];
    for (final key in properties) {
      final text = raw[key];
      Object? value;
      if (text != null) {
        if (_numbers.contains(key)) {
          final number = num.tryParse(text);
          if (number != null && number.isFinite) value = number;
        } else if (_flags.contains(key)) {
          value = switch (text) {
            'yes' => true,
            'no' => false,
            _ => null,
          };
        } else if (_choices[key]?.contains(text) == true) {
          value = text;
        } else if (key == 'mpv-version' || key == 'ffmpeg-version') {
          // Keep only the numeric release, never a build path or arbitrary suffix.
          final version = RegExp(
            r'^(?:(?:lib)?mpv v?|n|v)?(\d+\.\d+(?:\.\d+)?)',
          ).firstMatch(text);
          value = version?.group(1);
          if (value == null && key == 'ffmpeg-version') {
            value = RegExp(r'^(N-\d+)(?:-|$)').firstMatch(text)?.group(1);
          }
        }
      }
      if (value == null) {
        unavailable.add(key);
      } else {
        values[key] = value;
      }
    }
    return NativePlaybackSample._(
      Map.unmodifiable(values),
      List.unmodifiable(unavailable),
      elapsedMs,
      durationMs,
      timedOut,
    );
  }

  final Map<String, Object> values;
  final List<String> unavailable;
  final int elapsedMs, durationMs;
  final bool timedOut;

  Map<String, Object?> toJson() => {
    'sampleElapsedMs': elapsedMs,
    'sampleDurationMs': durationMs,
    'sampleStatus': timedOut
        ? 'timeout'
        : unavailable.isEmpty
        ? 'complete'
        : 'partial',
    'properties': values,
    'unavailable': unavailable,
  };
}

/// Read-only, single-flight sampling, independent of the playback command pump.
/// A timed-out native batch stays in flight until it settles: an unresponsive
/// backend cannot accumulate another batch every second.
final class NativePlaybackDiagnostics {
  NativePlaybackDiagnostics({
    required this.read,
    required this.isCurrent,
    required this.shouldSample,
    required this.onSample,
    this.interval = const Duration(seconds: 1),
    this.timeout = const Duration(milliseconds: 500),
  }) {
    _timer = Timer.periodic(interval, (_) {
      if (shouldSample()) sample();
    });
  }

  final Future<String> Function(String) read;
  final bool Function() isCurrent, shouldSample;
  final void Function(NativePlaybackSample) onSample;
  final Duration interval, timeout;
  final _clock = Stopwatch()..start();
  late final Timer _timer;
  Timer? _deadline;
  bool _busy = false, _disposed = false;
  NativePlaybackSample? latest;
  int? get sampleAgeMs =>
      latest == null ? null : _clock.elapsedMilliseconds - latest!.elapsedMs;

  void sample() {
    if (_busy || _disposed || !isCurrent()) return;
    _busy = true;
    final start = _clock.elapsedMilliseconds;
    final raw = <String, String>{};
    var timedOut = false;
    void emit(bool timeout) {
      if (_disposed || !isCurrent()) return;
      latest = NativePlaybackSample.fromProperties(
        raw,
        elapsedMs: start,
        durationMs: _clock.elapsedMilliseconds - start,
        timedOut: timeout,
      );
      onSample(latest!);
    }

    _deadline = Timer(timeout, () {
      timedOut = true;
      emit(true);
    });
    Future<void> collect() async {
      final reads = <Future<void>>[];
      final properties = NativePlaybackSample.properties;
      for (var index = 0; index < properties.length; index++) {
        if (timedOut || _disposed || !isCurrent()) break;
        final key = properties[index];
        reads.add(() async {
          try {
            final value = await read(key);
            if (!timedOut && !_disposed && isCurrent()) raw[key] = value;
          } on Object {
            // Unsupported properties and native read failures stay explicitly absent.
          }
        }());
        // The pinned port wraps synchronous reads; yield between small groups
        // instead of occupying one UI event turn with the entire batch.
        if ((index + 1) % 6 == 0) await Future<void>.delayed(Duration.zero);
      }
      await Future.wait(reads);
    }

    unawaited(
      collect().then((_) {
        _deadline?.cancel();
        _busy = false;
        if (!timedOut) emit(false);
      }),
    );
  }

  void dispose() {
    _disposed = true;
    _timer.cancel();
    _deadline?.cancel();
    latest = null;
  }
}
