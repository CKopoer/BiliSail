import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'danmaku_text_style.dart';

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

/// Schedules by confirmed media time and animates by unscaled elapsed time.
/// [monotonicNow] must not move backwards (e.g. Stopwatch.elapsed).
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
  double _topInset = 0;
  double _lineSpacing = 5;
  Duration _offset = Duration.zero;
  bool _mergeDuplicates = false;
  int _maxOnScreen = 0;
  Duration get _displayPosition => position - _offset;
  double get _top => _topInset.clamp(0, _height - _bottomInset);
  double get _availableHeight => (_height - _bottomInset - _top) * _area;
  int get _laneCount => (_availableHeight / _laneHeight).floor().clamp(0, 24);
  Duration get _scrollLifetime =>
      Duration(microseconds: (scrollDuration.inMicroseconds / _speed).round());

  /// [topInset] reserves logical pixels before applying [area].
  /// [lineSpacing] adds 0–100 logical pixels after measured text height.
  /// The default gap is 5 pixels.
  void configure({
    required double area,
    required double speed,
    double topInset = 0,
    double lineSpacing = 5,
    Duration offset = Duration.zero,
    bool mergeDuplicates = false,
    int maxOnScreen = 0,
    DanmakuTextStyle textStyle = const DanmakuTextStyle(),
  }) {
    final nextArea = area.clamp(.25, 1.0);
    final nextSpeed = speed.clamp(.5, 2.0);
    final nextTopInset = topInset.isFinite
        ? topInset.clamp(0.0, double.infinity)
        : 0.0;
    final nextLineSpacing = lineSpacing.isFinite
        ? lineSpacing.clamp(0.0, 100.0)
        : 5.0;
    if (_area == nextArea &&
        _speed == nextSpeed &&
        _topInset == nextTopInset &&
        _lineSpacing == nextLineSpacing &&
        _offset == offset &&
        _mergeDuplicates == mergeDuplicates &&
        _maxOnScreen == maxOnScreen.clamp(0, maxVisible) &&
        _layouts.style == textStyle) {
      return;
    }
    _area = nextArea;
    _speed = nextSpeed;
    _topInset = nextTopInset;
    _lineSpacing = nextLineSpacing;
    _offset = offset;
    _mergeDuplicates = mergeDuplicates;
    _maxOnScreen = maxOnScreen.clamp(0, maxVisible);
    _layouts.clear();
    _layouts.style = textStyle;
    _updateLaneHeight();
    seekConfirmed(position);
  }

  final Duration fixedDuration;
  late final _layouts = DanmakuTextLayouts(maxTextLayouts);
  final List<_Active> _active = [];
  List<DanmakuEvent> _events = const [];
  int _next = 0;
  Duration _anchorPosition = Duration.zero;
  Duration _anchorTime = Duration.zero;
  Duration _anchorAnimation = Duration.zero;
  final Set<String> _consumedIds = {};
  bool _playing = false;
  bool _buffering = false;
  bool _seeking = false;
  double _rate = 1;
  double _width = 0;
  double _height = 0;
  double _bottomInset = 0;
  double _laneHeight = 17;
  int dropped = 0;

  Duration get position => _estimate(_now());
  int get pendingCount => _events.length - _next;
  int get visibleCount => _active.length;
  int get textLayoutCount => _layouts.length;

  /// Media history needed to rebuild after seeking or refresh visible items.
  Duration get requiredHistory {
    final lifetime = _scrollLifetime > fixedDuration
        ? _scrollLifetime
        : fixedDuration;
    var history = Duration(
      microseconds: (lifetime.inMicroseconds * _rate).ceil(),
    );
    final at = _displayPosition;
    for (final item in _active) {
      final age = at - item.event.at;
      if (age > history) history = age;
    }
    return history;
  }

  bool get isAnimating =>
      _playing &&
      !_buffering &&
      !_seeking &&
      _now() - _anchorTime < maxInterpolation;

  Duration _elapsed(Duration now) {
    if (!_playing || _buffering || _seeking) return Duration.zero;
    final since = now - _anchorTime;
    if (since <= Duration.zero) return Duration.zero;
    return since < maxInterpolation ? since : maxInterpolation;
  }

  Duration _estimate(Duration now) {
    final advance = _elapsed(now);
    return _anchorPosition +
        Duration(microseconds: (advance.inMicroseconds * _rate).round());
  }

  Duration _animationAt(Duration now) => _anchorAnimation + _elapsed(now);

  void setViewport({
    required double width,
    required double height,
    double bottomInset = 0,
  }) {
    final double nextWidth = width.clamp(0, double.infinity);
    final double nextHeight = height.clamp(0, double.infinity);
    final double nextBottomInset = bottomInset.clamp(0, nextHeight);
    if (nextWidth == _width &&
        nextHeight == _height &&
        nextBottomInset == _bottomInset) {
      return;
    }
    _width = nextWidth;
    _height = nextHeight;
    _bottomInset = nextBottomInset;
    if (_width > 0 && _height > 0) {
      // Fullscreen and control visibility are layout changes, not seeks.
      // Keep arrival times, lanes and the cursor: replaying dropped history
      // can displace comments already on screen. frame() projects their
      // existing progress onto the new width; text layouts are width-independent.
      final laneCount = _laneCount;
      _active.removeWhere((item) => item.lane >= laneCount);
    }
    notifyListeners();
  }

  /// Holds only a bounded, sorted window supplied by the application layer.
  void replaceEvents(Iterable<DanmakuEvent> events) {
    final previous = {for (final event in _events) event.id: event};
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
      final pivot = _lowerBound(sorted, _displayPosition);
      final from = (pivot - maxPending ~/ 4).clamp(
        0,
        sorted.length - maxPending,
      );
      _events = List.unmodifiable(sorted.sublist(from, from + maxPending));
      dropped += sorted.length - maxPending;
    } else {
      _events = List.unmodifiable(sorted);
    }
    final available = {for (final event in _events) event.id: event};
    _consumedIds.removeWhere((id) {
      final oldEvent = previous[id];
      final nextEvent = available[id];
      return oldEvent == null ||
          nextEvent == null ||
          !_sameEvent(oldEvent, nextEvent);
    });
    _updateLaneHeight();
    _active.removeWhere((item) {
      final next = available[item.event.id];
      return next == null || !_sameEvent(item.event, next);
    });
    _rewindTo(_displayPosition);
    notifyListeners();
  }

  bool _sameEvent(DanmakuEvent a, DanmakuEvent b) =>
      a.text == b.text &&
      a.color == b.color &&
      a.fontSize == b.fontSize &&
      a.at == b.at &&
      a.mode == b.mode;

  /// Pass the latest confirmed player position when phase or rate changes.
  void sync({
    required Duration confirmedPosition,
    required bool playing,
    required bool buffering,
    required bool seeking,
    required double rate,
  }) {
    final now = _now();
    final previousPosition = _estimate(now);
    // Settle the previous phase before changing its anchor or rate. Existing
    // comments retain their visual age across media corrections/rate changes.
    _anchorAnimation = _animationAt(now);
    _anchorPosition = confirmedPosition < Duration.zero
        ? Duration.zero
        : confirmedPosition;
    _anchorTime = now;
    _playing = playing;
    _buffering = buffering;
    _seeking = seeking;
    _rate = rate.isFinite && rate > 0 ? rate : 1;
    if ((_anchorPosition - previousPosition).abs() >
        const Duration(seconds: 2)) {
      _active.clear();
      _consumedIds.clear();
      _rewindTo(_anchorPosition - _offset);
    }
    notifyListeners();
  }

  /// Call only after the player confirms the new position.
  void seekConfirmed(Duration confirmedPosition) {
    final now = _now();
    _anchorAnimation = _animationAt(now);
    _anchorPosition = confirmedPosition < Duration.zero
        ? Duration.zero
        : confirmedPosition;
    _anchorTime = now;
    _seeking = false;
    _active.clear();
    _consumedIds.clear();
    _rewindTo(_anchorPosition - _offset);
    notifyListeners();
  }

  void _rewindTo(Duration position) {
    final earliest = position - requiredHistory;
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

  TextPainter _layout(DanmakuEvent event) =>
      _layouts.layout(event.text, event.color, event.fontSize);

  void _updateLaneHeight() {
    // Keep empty layouts valid without imposing a floor on scaled text height.
    var textHeight = DanmakuTextLayouts.minFontSize;
    for (final event in _events) {
      final height = _layout(event).height;
      if (height > textHeight) textHeight = height;
    }
    final laneHeight = textHeight + _lineSpacing;
    if (_laneHeight != laneHeight) {
      _laneHeight = laneHeight;
      _active.clear();
    }
  }

  void paintText(DanmakuEvent event, Canvas canvas, Offset offset) =>
      _layouts.paint(event.text, event.color, event.fontSize, canvas, offset);

  void _clearLayouts() => _layouts.clear();

  List<DanmakuPlacement> frame() {
    final now = _now();
    final mediaAt = _estimate(now) - _offset;
    final at = _animationAt(now);
    _active.removeWhere(
      (item) =>
          at - item.start >=
          (item.event.mode == DanmakuMode.scroll
              ? _scrollLifetime
              : fixedDuration),
    );
    if (_width <= 0 || _height <= 0) return const [];
    while (_next < _events.length && _events[_next].at <= mediaAt) {
      final event = _events[_next++];
      if (!_consumedIds.add(event.id)) continue;
      if (_active.length >= (_maxOnScreen == 0 ? maxVisible : _maxOnScreen)) {
        dropped++;
        continue;
      }
      // Catch up late arrivals/seek history in real seconds at the current
      // media rate; once admitted, only the independent animation clock moves it.
      final age = Duration(
        microseconds: ((mediaAt - event.at).inMicroseconds / _rate).round(),
      );
      final lifetime = event.mode == DanmakuMode.scroll
          ? _scrollLifetime
          : fixedDuration;
      if (age >= lifetime) continue;
      if (_active.any((item) => item.event.id == event.id)) continue;
      if (_mergeDuplicates &&
          _active.any(
            (item) =>
                item.event.text == event.text && item.event.mode == event.mode,
          )) {
        continue;
      }
      final layout = _layout(event);
      final lane = _findLane(event, layout.width, at);
      if (lane < 0) {
        dropped++;
        continue;
      }
      _active.add(_Active(event, at - age, layout.width, lane));
    }
    final result = <DanmakuPlacement>[];
    for (final item in _active) {
      final age = at - item.start;
      final x = item.event.mode == DanmakuMode.scroll
          ? _width -
                (_width + item.width) *
                    (age.inMicroseconds / _scrollLifetime.inMicroseconds)
          : (_width - item.width) / 2;
      final y = item.event.mode == DanmakuMode.bottom
          ? _top + _availableHeight - (item.lane + 1) * _laneHeight
          : _top + item.lane * _laneHeight;
      result.add(DanmakuPlacement(event: item.event, x: x, y: y));
    }
    return result;
  }

  int _findLane(DanmakuEvent event, double textWidth, Duration at) {
    final laneCount = _laneCount;
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
