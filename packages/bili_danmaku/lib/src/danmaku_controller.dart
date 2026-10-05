import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

enum DanmakuMode { scroll, top, bottom }

@immutable
final class DanmakuEvent {
  const DanmakuEvent({
    required this.id,
    required this.at,
    required this.text,
    this.mode = DanmakuMode.scroll,
    this.color = const Color(0xFFFFFFFF),
    this.fontSize = 24,
  });

  final String id;
  final Duration at;
  final String text;
  final DanmakuMode mode;
  final Color color;
  final double fontSize;
}

@immutable
final class DanmakuPlacement {
  const DanmakuPlacement({
    required this.event,
    required this.x,
    required this.y,
  });
  final DanmakuEvent event;
  final double x;
  final double y;
}

final class _Active {
  const _Active(this.event, this.start, this.width, this.lane);
  final DanmakuEvent event;
  final Duration start;
  final double width;
  final int lane;
}

/// Uses confirmed player position as its only media clock. [monotonicNow]
/// must not move backwards (e.g. Stopwatch.elapsed).
final class DanmakuController extends ChangeNotifier {
  DanmakuController({
    required Duration Function() monotonicNow,
    this.maxPending = 500,
    this.maxVisible = 120,
    this.maxTextLayouts = 256,
    this.maxInterpolation = const Duration(milliseconds: 700),
    this.scrollDuration = const Duration(seconds: 8),
    this.fixedDuration = const Duration(seconds: 4),
  }) : _now = monotonicNow;

  final Duration Function() _now;
  final int maxPending;
  final int maxVisible;
  final int maxTextLayouts;
  final Duration maxInterpolation;
  final Duration scrollDuration;
  double _area = 1;
  double _speed = 1;
  Duration get _scrollLifetime =>
      Duration(microseconds: (scrollDuration.inMicroseconds / _speed).round());

  void configure({required double area, required double speed}) {
    final nextArea = area.clamp(.25, 1.0);
    final nextSpeed = speed.clamp(.5, 2.0);
    if (_area == nextArea && _speed == nextSpeed) return;
    _area = nextArea;
    _speed = nextSpeed;
    seekConfirmed(position);
  }

  final Duration fixedDuration;
  final _layouts = <String, TextPainter>{};
  final List<_Active> _active = [];
  List<DanmakuEvent> _events = const [];
  int _next = 0;
  Duration _anchorPosition = Duration.zero;
  Duration _anchorTime = Duration.zero;
  Duration _lastRendered = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _seeking = false;
  double _rate = 1;
  double _width = 0;
  double _height = 0;
  double _bottomInset = 0;
  int dropped = 0;

  Duration get position => _estimate(_now());
  int get pendingCount => _events.length - _next;
  int get visibleCount => _active.length;
  int get textLayoutCount => _layouts.length;
  bool get isAnimating =>
      _playing &&
      !_buffering &&
      !_seeking &&
      _now() - _anchorTime < maxInterpolation;

  Duration _estimate(Duration now) {
    if (!_playing || _buffering || _seeking) return _anchorPosition;
    final since = now - _anchorTime;
    if (since <= Duration.zero) {
      return _anchorPosition;
    }
    final advance = since < maxInterpolation ? since : maxInterpolation;
    return _anchorPosition +
        Duration(microseconds: (advance.inMicroseconds * _rate).round());
  }

  void setViewport({
    required double width,
    required double height,
    double bottomInset = 0,
  }) {
    if (width == _width && height == _height && bottomInset == _bottomInset) {
      return;
    }
    _width = width.clamp(0, double.infinity);
    _height = height.clamp(0, double.infinity);
    _bottomInset = bottomInset.clamp(0, _height);
    _active.clear();
    _clearLayouts();
    _rewindTo(position);
    notifyListeners();
  }

  /// Holds only a bounded, sorted window supplied by the application layer.
  void replaceEvents(Iterable<DanmakuEvent> events) {
    final ids = <String>{};
    final sorted =
        events
            .where(
              (e) =>
                  e.at >= Duration.zero &&
                  e.text.isNotEmpty &&
                  e.text.length <= 300 &&
                  e.fontSize.isFinite &&
                  e.fontSize > 0 &&
                  ids.add(e.id),
            )
            .toList()
          ..sort((a, b) => a.at.compareTo(b.at));
    if (sorted.length > maxPending) {
      final pivot = _lowerBound(sorted, position);
      final from = (pivot - maxPending ~/ 4).clamp(
        0,
        sorted.length - maxPending,
      );
      _events = List.unmodifiable(sorted.sublist(from, from + maxPending));
      dropped += sorted.length - maxPending;
    } else {
      _events = List.unmodifiable(sorted);
    }
    final availableIds = _events.map((event) => event.id).toSet();
    _active.removeWhere((item) => !availableIds.contains(item.event.id));
    _rewindTo(position);
    notifyListeners();
  }

  /// Pass the latest confirmed player position when phase or rate changes.
  void sync({
    required Duration confirmedPosition,
    required bool playing,
    required bool buffering,
    required bool seeking,
    required double rate,
  }) {
    final now = _now();
    _anchorPosition = confirmedPosition < Duration.zero
        ? Duration.zero
        : confirmedPosition;
    _anchorTime = now;
    _playing = playing;
    _buffering = buffering;
    _seeking = seeking;
    _rate = rate.isFinite && rate > 0 ? rate : 1;
    if ((_anchorPosition - _lastRendered).abs() > const Duration(seconds: 2)) {
      _active.clear();
      _rewindTo(_anchorPosition);
    }
    notifyListeners();
  }

  /// Call only after the player confirms the new position.
  void seekConfirmed(Duration confirmedPosition) {
    final now = _now();
    _anchorPosition = confirmedPosition < Duration.zero
        ? Duration.zero
        : confirmedPosition;
    _anchorTime = now;
    _lastRendered = _anchorPosition;
    _seeking = false;
    _active.clear();
    _rewindTo(_anchorPosition);
    notifyListeners();
  }

  void _rewindTo(Duration position) {
    final earliest =
        position -
        (_scrollLifetime > fixedDuration ? _scrollLifetime : fixedDuration);
    _next = _lowerBound(
      _events,
      earliest < Duration.zero ? Duration.zero : earliest,
    );
  }

  int _lowerBound(List<DanmakuEvent> events, Duration target) {
    var low = 0;
    var high = events.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (events[mid].at < target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  TextPainter _layout(DanmakuEvent event) {
    final fontSize = event.fontSize.clamp(12.0, 54.0);
    final key = '$fontSize|${event.color.toARGB32()}|${event.text}';
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
          fontSize: fontSize,
          shadows: const [Shadow(color: Color(0xFF000000), blurRadius: 2)],
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

  void paintText(DanmakuEvent event, Canvas canvas, Offset offset) {
    _layout(event).paint(canvas, offset);
  }

  void _clearLayouts() {
    for (final painter in _layouts.values) {
      painter.dispose();
    }
    _layouts.clear();
  }

  List<DanmakuPlacement> frame() {
    final at = position;
    _lastRendered = at;
    _active.removeWhere(
      (item) =>
          at - item.start >=
          (item.event.mode == DanmakuMode.scroll
              ? _scrollLifetime
              : fixedDuration),
    );
    if (_width <= 0 || _height <= 0) return const [];
    while (_next < _events.length && _events[_next].at <= at) {
      final event = _events[_next++];
      if (_active.length >= maxVisible) {
        dropped++;
        continue;
      }
      final age = at - event.at;
      final lifetime = event.mode == DanmakuMode.scroll
          ? _scrollLifetime
          : fixedDuration;
      if (age >= lifetime) continue;
      if (_active.any((item) => item.event.id == event.id)) continue;
      final layout = _layout(event);
      final lane = _findLane(event, layout.width, at);
      if (lane < 0) {
        dropped++;
        continue;
      }
      _active.add(_Active(event, event.at, layout.width, lane));
    }
    final result = <DanmakuPlacement>[];
    for (final item in _active) {
      final age = at - item.start;
      final x = item.event.mode == DanmakuMode.scroll
          ? _width -
                (_width + item.width) *
                    (age.inMicroseconds / _scrollLifetime.inMicroseconds)
          : (_width - item.width) / 2;
      const laneHeight = 48.0;
      final y = item.event.mode == DanmakuMode.bottom
          ? (_height - _bottomInset) * _area - (item.lane + 1) * laneHeight
          : item.lane * laneHeight;
      result.add(DanmakuPlacement(event: item.event, x: x, y: y));
    }
    return result;
  }

  int _findLane(DanmakuEvent event, double textWidth, Duration at) {
    const laneHeight = 48.0;
    final available = (_height - _bottomInset) * _area;
    final laneCount = (available / laneHeight).floor().clamp(0, 24);
    for (var lane = 0; lane < laneCount; lane++) {
      var free = true;
      for (final prior in _active) {
        if (prior.event.mode != event.mode || prior.lane != lane) continue;
        if (event.mode != DanmakuMode.scroll) {
          free = false;
          break;
        }
        final oldSpeed =
            (_width + prior.width) / _scrollLifetime.inMicroseconds;
        final newSpeed = (_width + textWidth) / _scrollLifetime.inMicroseconds;
        final elapsed = (at - prior.start).inMicroseconds;
        final oldTailNow = _width - oldSpeed * elapsed + prior.width;
        if (oldTailNow + 8 > _width) {
          free = false;
          break;
        }
        if (newSpeed > oldSpeed) {
          final remaining = ((_scrollLifetime.inMicroseconds - elapsed).clamp(
            0,
            _scrollLifetime.inMicroseconds,
          ));
          if (_width - newSpeed * remaining <
              oldTailNow - oldSpeed * remaining + 8) {
            free = false;
            break;
          }
        }
      }
      if (free) return lane;
    }
    return -1;
  }

  @override
  void dispose() {
    _clearLayouts();
    super.dispose();
  }
}
