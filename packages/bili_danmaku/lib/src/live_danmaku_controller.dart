import 'dart:collection';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'danmaku_controller.dart' show DanmakuMode;

@immutable
final class LiveDanmakuEvent {
  const LiveDanmakuEvent({
    required this.id,
    required this.text,
    this.mode = DanmakuMode.scroll,
    this.color = const Color(0xffffffff),
    this.fontSize = 24,
  });
  final String id, text;
  final DanmakuMode mode;
  final Color color;
  final double fontSize;
}

@immutable
final class LiveDanmakuPlacement {
  const LiveDanmakuPlacement(this.event, this.x, this.y);
  final LiveDanmakuEvent event;
  final double x, y;
}

final class _Received {
  const _Received(this.event, this.at);
  final LiveDanmakuEvent event;
  final Duration at;
}

final class _Visible {
  const _Visible(this.event, this.at, this.width, this.lane);
  final LiveDanmakuEvent event;
  final Duration at;
  final double width;
  final int lane;
}

/// Live time advances from message receipt using a monotonic wall clock.
/// It has no player position, seek, buffering or playback rate dependency.
final class LiveDanmakuController extends ChangeNotifier {
  LiveDanmakuController({
    required Duration Function() monotonicNow,
    this.maxPending = 500,
    this.maxVisible = 120,
    this.maxTextLayouts = 256,
    this.scrollDuration = const Duration(seconds: 8),
    this.fixedDuration = const Duration(seconds: 4),
    this.maxPendingAge = const Duration(seconds: 2),
  }) : _now = monotonicNow;

  final Duration Function() _now;
  final int maxPending, maxVisible, maxTextLayouts;
  final Duration scrollDuration, fixedDuration, maxPendingAge;
  final Queue<_Received> _pending = Queue();
  final List<_Visible> _visible = [];
  final Map<String, TextPainter> _layouts = {};
  final Map<String, Duration> _recentIds = {};
  bool _enabled = true;
  double _width = 0, _height = 0, _bottomInset = 0, _area = .75, _speed = 1;
  double _laneHeight = 48;
  int _maxPerSecond = 20, _windowCount = 0;
  Duration _windowAt = Duration.zero;
  int dropped = 0;
  int get pendingCount => _pending.length;
  int get visibleCount => _visible.length;
  int get textLayoutCount => _layouts.length;
  bool get isAnimating =>
      _enabled && (_pending.isNotEmpty || _visible.isNotEmpty);
  Duration get _scrollLifetime =>
      Duration(microseconds: (scrollDuration.inMicroseconds / _speed).round());

  void configure({
    required double area,
    required double speed,
    required int maxPerSecond,
  }) {
    final nextArea = area.clamp(.25, 1.0), nextSpeed = speed.clamp(.5, 2.0);
    _maxPerSecond = maxPerSecond.clamp(1, 100);
    if (_area != nextArea || _speed != nextSpeed) {
      _area = nextArea;
      _speed = nextSpeed;
      clear();
    }
  }

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    clear();
  }

  void clear() {
    _pending.clear();
    _visible.clear();
    _recentIds.clear();
    notifyListeners();
  }

  void add(Iterable<LiveDanmakuEvent> events) {
    if (!_enabled) return;
    final now = _now();
    if (now - _windowAt >= const Duration(seconds: 1)) {
      _windowAt = now;
      _windowCount = 0;
    }
    for (final event in events.take(maxPending)) {
      if (event.text.isEmpty ||
          event.text.length > 300 ||
          !event.fontSize.isFinite ||
          event.fontSize <= 0 ||
          _recentIds.containsKey(event.id)) {
        continue;
      }
      if (_windowCount >= _maxPerSecond) {
        dropped++;
        continue;
      }
      _windowCount++;
      _recentIds[event.id] = now;
      if (_pending.length >= maxPending) {
        _pending.removeFirst();
        dropped++;
      }
      _pending.add(_Received(event, now));
    }
    _recentIds.removeWhere((_, at) => now - at > const Duration(seconds: 30));
    while (_recentIds.length > maxPending) {
      _recentIds.remove(_recentIds.keys.first);
    }
    notifyListeners();
  }

  void setViewport({
    required double width,
    required double height,
    double bottomInset = 0,
  }) {
    if (_width == width && _height == height && _bottomInset == bottomInset) {
      return;
    }
    _width = width.clamp(0, double.infinity);
    _height = height.clamp(0, double.infinity);
    _bottomInset = bottomInset.clamp(0, _height);
    _visible.clear();
    _clearLayouts();
    notifyListeners();
  }

  TextPainter _layout(LiveDanmakuEvent event) {
    final size = event.fontSize.clamp(12.0, 54.0);
    final key = '$size|${event.color.toARGB32()}|${event.text}';
    final cached = _layouts.remove(key);
    if (cached != null) {
      _layouts[key] = cached;
      return cached;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: event.text,
        style: TextStyle(
          color: event.color,
          fontSize: size,
          shadows: const [Shadow(color: Color(0xff000000), blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _layouts[key] = painter;
    if (_layouts.length > maxTextLayouts) {
      _layouts.remove(_layouts.keys.first)?.dispose();
    }
    return painter;
  }

  void paintText(LiveDanmakuEvent event, Canvas canvas, Offset offset) =>
      _layout(event).paint(canvas, offset);

  List<LiveDanmakuPlacement> frame() {
    if (!_enabled) return const [];
    final now = _now();
    _visible.removeWhere(
      (item) =>
          now - item.at >=
          (item.event.mode == DanmakuMode.scroll
              ? _scrollLifetime
              : fixedDuration),
    );
    if (_width <= 0 || _height <= 0) return const [];
    final priorLaneHeight = _laneHeight;
    for (final received in _pending) {
      _laneHeight = max(_laneHeight, _layout(received.event).height + 4);
    }
    if (_laneHeight != priorLaneHeight) _visible.clear();
    while (_pending.isNotEmpty) {
      final received = _pending.removeFirst();
      if (now - received.at > maxPendingAge || _visible.length >= maxVisible) {
        dropped++;
        continue;
      }
      final layout = _layout(received.event);
      final lane = _findLane(received.event, layout.width, now);
      if (lane < 0) {
        dropped++;
        continue;
      }
      _visible.add(_Visible(received.event, now, layout.width, lane));
    }
    return [
      for (final item in _visible)
        LiveDanmakuPlacement(
          item.event,
          item.event.mode == DanmakuMode.scroll
              ? _width -
                    (_width + item.width) *
                        ((now - item.at).inMicroseconds /
                            _scrollLifetime.inMicroseconds)
              : (_width - item.width) / 2,
          item.event.mode == DanmakuMode.bottom
              ? (_height - _bottomInset) * _area - (item.lane + 1) * _laneHeight
              : item.lane * _laneHeight,
        ),
    ];
  }

  int _findLane(LiveDanmakuEvent event, double textWidth, Duration now) {
    final count = (((_height - _bottomInset) * _area) / _laneHeight)
        .floor()
        .clamp(0, 24);
    for (var lane = 0; lane < count; lane++) {
      var free = true;
      for (final prior in _visible) {
        if (prior.event.mode != event.mode || prior.lane != lane) continue;
        if (event.mode != DanmakuMode.scroll) {
          free = false;
          break;
        }
        final oldSpeed =
            (_width + prior.width) / _scrollLifetime.inMicroseconds;
        final newSpeed = (_width + textWidth) / _scrollLifetime.inMicroseconds;
        final elapsed = (now - prior.at).inMicroseconds;
        final oldTail = _width - oldSpeed * elapsed + prior.width;
        final remaining = (_scrollLifetime.inMicroseconds - elapsed).clamp(
          0,
          _scrollLifetime.inMicroseconds,
        );
        if (oldTail + 8 > _width ||
            (newSpeed > oldSpeed &&
                _width - newSpeed * remaining <
                    oldTail - oldSpeed * remaining + 8)) {
          free = false;
          break;
        }
      }
      if (free) return lane;
    }
    return -1;
  }

  void _clearLayouts() {
    for (final layout in _layouts.values) {
      layout.dispose();
    }
    _layouts.clear();
  }

  @override
  void dispose() {
    _clearLayouts();
    super.dispose();
  }
}
