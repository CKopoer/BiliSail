import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'system_media_controls.dart';

final class WindowsMediaControls extends SystemMediaControls {
  WindowsMediaControls({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('bilisail/system_media') {
    _channel.setMethodCallHandler(_handleCommand);
  }

  final MethodChannel _channel;
  Future<void>? _pending;
  SystemMediaState? _state;
  bool _dirty = false;
  bool _reportedFailure = false;
  bool _closed = false;

  Future<void> _handleCommand(MethodCall call) async {
    final args = call.arguments;
    if (_closed || call.method != 'command' || args is! Map) return;
    final id = args['id'];
    if (id is! String || id != _state?.id) return;
    final action = switch (args['action']) {
      'play' => SystemMediaAction.play,
      'pause' => SystemMediaAction.pause,
      'stop' => SystemMediaAction.stop,
      'seek' => SystemMediaAction.seek,
      _ => null,
    };
    if (action == null) return;
    final milliseconds = args['positionMs'];
    await onCommand?.call(
      SystemMediaCommand(
        id,
        action,
        position: milliseconds is int
            ? Duration(milliseconds: milliseconds)
            : null,
      ),
    );
  }

  @override
  void publish(SystemMediaState? state) {
    if (_closed) return;
    _state = state;
    _dirty = true;
    // One in-flight update and one replacement state keep a slow/missing
    // platform channel from accumulating an unbounded chain of updates.
    _pending ??= _flush().whenComplete(() => _pending = null);
  }

  Future<void> _flush() async {
    while (_dirty) {
      _dirty = false;
      final state = _state;
      try {
        await _channel
            .invokeMethod<void>(
              state == null ? 'clear' : 'update',
              state == null
                  ? null
                  : <String, Object?>{
                      'id': state.id,
                      'title': state.title,
                      'artist': state.artist ?? '',
                      'artUri': state.artUri?.toString() ?? '',
                      'playing': state.playing,
                      'phase': state.phase.name,
                      'rate': state.rate,
                      'canSeek': state.canSeek,
                      'positionMs': state.position.inMilliseconds,
                      'durationMs': state.duration.inMilliseconds,
                    },
            )
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // The optional OS integration cannot interrupt playback. Never log
        // native exception details, which may contain metadata or URLs.
        if (!_reportedFailure) {
          _reportedFailure = true;
          debugPrint('Windows system media controls are unavailable.');
        }
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    publish(null);
    _closed = true;
    onCommand = null;
    await _pending;
    _channel.setMethodCallHandler(null);
  }
}
