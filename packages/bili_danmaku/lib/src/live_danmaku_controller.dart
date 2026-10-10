import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'danmaku_controller.dart' show DanmakuMode;
import 'danmaku_text_style.dart';

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
  const _Visible(this.event, this.at, this.width, this.height, this.lane);
  final LiveDanmakuEvent event;
  final Duration at;
  final double width;
  final double height;
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
    this.maxAdmissionsPerFrame = 32,
    this.scrollDuration = const Duration(seconds: 8),
    this.fixedDuration = const Duration(seconds: 4),
    this.maxPendingAge = const Duration(seconds: 2),
  }) : assert(maxAdmissionsPerFrame > 0),
       _now = monotonicNow;

  final Duration Function() _now;
  final int maxPending, maxVisible, maxTextLayouts;
  final int maxAdmissionsPerFrame;
  final Duration scrollDuration, fixedDuration, maxPendingAge;
  final Queue<_Received> _pending = Queue();
  final List<_Visible> _visible = [];
  late final _layouts = DanmakuTextLayouts(maxTextLayouts);
  final Map<String, Duration> _recentIds = {};
  bool _enabled = true;
  double _width = 0, _height = 0, _bottomInset = 0, _area = .75, _speed = 1;
  double _topInset = 0;
  double _lineSpacing = 5;
  Duration _offset = Duration.zero;
  bool _mergeDuplicates = false;
  int _maxOnScreen = 0;
  double get _top => _topInset.clamp(0, _height - _bottomInset);
  double get _availableHeight => (_height - _bottomInset - _top) * _area;
  double _laneHeight = DanmakuTextLayouts.minFontSize + 5;
  int _maxPerSecond = 20, _windowCount = 0;
  Duration _windowAt = Duration.zero;
  int dropped = 0;
  int get pendingCount => _pending.length;
  int get visibleCount => _visible.length;
  int get textLayoutCount => _layouts.length;
  int get textLayoutBuildCount => _layouts.buildCount;
  int get textRasterBytes => _layouts.rasterBytes;
  bool get isAnimating =>
      _enabled && (_pending.isNotEmpty || _visible.isNotEmpty);
  Duration get _scrollLifetime =>
      Duration(microseconds: (scrollDuration.inMicroseconds / _speed).round());

  /// [topInset] reserves logical pixels before applying [area].
  /// [lineSpacing] adds 0–100 logical pixels after measured text height.
  /// The default gap is 5 pixels.
  void configure({
    required double area,
    required double speed,
    required int maxPerSecond,
    double topInset = 0,
    double lineSpacing = 5,
    Duration offset = Duration.zero,
    bool mergeDuplicates = false,
    int maxOnScreen = 0,
    DanmakuTextStyle textStyle = const DanmakuTextStyle(),
  }) {
    final nextArea = area.clamp(.25, 1.0), nextSpeed = speed.clamp(.5, 2.0);
    final nextTopInset = topInset.isFinite
        ? topInset.clamp(0.0, double.infinity)
        : 0.0;
    final nextLineSpacing = lineSpacing.isFinite
        ? lineSpacing.clamp(0.0, 100.0)
        : 5.0;
    final nextMaxPerSecond = maxPerSecond.clamp(0, 100);
    if (_area != nextArea ||
        _speed != nextSpeed ||
        _topInset != nextTopInset ||
        _lineSpacing != nextLineSpacing ||
        _offset != offset ||
        _mergeDuplicates != mergeDuplicates ||
        _maxOnScreen != maxOnScreen.clamp(0, maxVisible) ||
        _layouts.style != textStyle ||
        _maxPerSecond != nextMaxPerSecond) {
      _area = nextArea;
      _speed = nextSpeed;
      _topInset = nextTopInset;
      _lineSpacing = nextLineSpacing;
      _offset = offset;
      _mergeDuplicates = mergeDuplicates;
      _maxOnScreen = maxOnScreen.clamp(0, maxVisible);
      _maxPerSecond = nextMaxPerSecond;
      _laneHeight = DanmakuTextLayouts.minFontSize + _lineSpacing;
      _clearLayouts();
      _layouts.style = textStyle;
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
    _windowCount = 0;
    _windowAt = _now();
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
      if (_maxPerSecond > 0 && _windowCount >= _maxPerSecond) {
        dropped++;
        continue;
      }
      _windowCount++;
      _recentIds[event.id] = now;
      if (_pending.length >= maxPending) {
        _pending.removeFirst();
        dropped++;
      }
      // Live messages have no past media clock: negative offsets are immediate.
      _pending.add(
        _Received(
          event,
          now + (_offset > Duration.zero ? _offset : Duration.zero),
        ),
      );
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

  TextPainter _layout(LiveDanmakuEvent event) =>
      _layouts.layout(event.text, event.color, event.fontSize);

  void paintText(
    LiveDanmakuEvent event,
    Canvas canvas,
    Offset offset, {
    double pixelRatio = 1,
  }) => _layouts.paint(
    event.text,
    event.color,
    event.fontSize,
    canvas,
    offset,
    pixelRatio: pixelRatio,
  );

  void _clearLayouts() => _layouts.clear();

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
    final prepared = <(LiveDanmakuEvent, double, double)>[];
    final texts = _mergeDuplicates
        ? {for (final item in _visible) (item.event.mode, item.event.text)}
        : <(DanmakuMode, String)>{};
    while (_pending.isNotEmpty && _pending.first.at <= now) {
      if (prepared.length >= maxAdmissionsPerFrame) break;
      final received = _pending.removeFirst();
      if (now - received.at > maxPendingAge ||
          _visible.length >= (_maxOnScreen == 0 ? maxVisible : _maxOnScreen)) {
        dropped++;
        continue;
      }
      if (_mergeDuplicates &&
          !texts.add((received.event.mode, received.event.text))) {
        continue;
      }
      final layout = _layout(received.event);
      prepared.add((received.event, layout.width, layout.height));
    }
    var textHeight = _visible.isEmpty
        ? DanmakuTextLayouts.minFontSize
        : _laneHeight - _lineSpacing;
    for (final item in _visible) {
      if (item.height > textHeight) textHeight = item.height;
    }
    for (final item in prepared) {
      if (item.$3 > textHeight) textHeight = item.$3;
    }
    _laneHeight = textHeight + _lineSpacing;
    final laneCount = (_availableHeight / _laneHeight).floor().clamp(0, 24);
    _visible.removeWhere((item) => item.lane >= laneCount);
    final lanes = List.generate(
      DanmakuMode.values.length,
      (_) => List.generate(laneCount, (_) => <_Visible>[]),
    );
    for (final item in _visible) {
      lanes[item.event.mode.index][item.lane].add(item);
    }
    for (final (event, width, height) in prepared) {
      if (_visible.length >= (_maxOnScreen == 0 ? maxVisible : _maxOnScreen)) {
        dropped++;
        continue;
      }
      final lane = _findLane(event, width, now, lanes[event.mode.index]);
      if (lane < 0) {
        dropped++;
        continue;
      }
      final item = _Visible(event, now, width, height, lane);
      _visible.add(item);
      lanes[event.mode.index][lane].add(item);
    }
    _layouts.protectRasters(
      _visible.map(
        (item) => (item.event.text, item.event.color, item.event.fontSize),
      ),
    );
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
              ? _top + _availableHeight - (item.lane + 1) * _laneHeight
              : _top + item.lane * _laneHeight,
        ),
    ];
  }

  int _findLane(
    LiveDanmakuEvent event,
    double textWidth,
    Duration now,
    List<List<_Visible>> lanes,
  ) {
    for (var lane = 0; lane < lanes.length; lane++) {
      var free = true;
      for (final prior in lanes[lane]) {
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

  @override
  void dispose() {
    _clearLayouts();
    super.dispose();
  }
}
