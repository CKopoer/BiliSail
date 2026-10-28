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
  const _Active(this.event, this.start, this.width, this.height, this.lane);
  final DanmakuEvent event;
  final Duration start;
  final double width;
  final double height;
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
    this.maxAdmissionsPerFrame = 32,
    this.maxInterpolation = const Duration(milliseconds: 700),
    this.scrollDuration = const Duration(seconds: 8),
    this.fixedDuration = const Duration(seconds: 4),
  }) : assert(maxAdmissionsPerFrame > 0),
       _now = monotonicNow;

  final Duration Function() _now;
  final int maxPending;
  final int maxVisible;
  final int maxTextLayouts;

  /// Caps text preparation per frame; remaining arrivals keep their media age.
  final int maxAdmissionsPerFrame;
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
    _laneHeight = DanmakuTextLayouts.minFontSize + _lineSpacing;
    seekConfirmed(position);
  }

  final Duration fixedDuration;
  late final _layouts = DanmakuTextLayouts(maxTextLayouts);
  final List<_Active> _active = [];
  bool _rasterProtectionDirty = false;
  int _laneIndexBuildCount = 0;
  int _rasterProtectionUpdateCount = 0;
  int _visualRevision = 0;

  /// Changes to visible content or layout, separate from clock confirmations.
  int get visualRevision => _visualRevision;
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
  int get textLayoutBuildCount => _layouts.buildCount;
  int get textRasterBytes => _layouts.rasterBytes;
  DanmakuRasterStatistics get rasterStatistics => _layouts.rasterStatistics;

  @visibleForTesting
  int get laneIndexBuildCount => _laneIndexBuildCount;

  @visibleForTesting
  int get rasterProtectionUpdateCount => _rasterProtectionUpdateCount;

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

  bool get isAnimating => _isAnimatingAt(_now());

  bool _isAnimatingAt(Duration now) =>
      _playing &&
      !_buffering &&
      !_seeking &&
      now - _anchorTime < maxInterpolation;

  /// Finish bounded admission after a paused seek without advancing either clock.
  bool get needsFrame => _needsFrameAt(_now());

  bool _needsFrameAt(Duration now) {
    if (_width <= 0 || _height <= 0) return false;
    if (_next < _events.length &&
        _events[_next].at <= _estimate(now) - _offset) {
      return true;
    }
    final at = _animationAt(now);
    final animating = _isAnimatingAt(now);
    for (final item in _active) {
      final scrolling = item.event.mode == DanmakuMode.scroll;
      if (at - item.start >= (scrolling ? _scrollLifetime : fixedDuration) ||
          (scrolling && animating)) {
        return true;
      }
    }
    return false;
  }

  /// Wake at the next arrival or fixed-text expiry between confirmed samples.
  /// Never extrapolate beyond the existing bounded interpolation window.
  Duration? get nextFrameDelay {
    final now = _now();
    if (!_isAnimatingAt(now) ||
        _needsFrameAt(now) ||
        _width <= 0 ||
        _height <= 0) {
      return null;
    }
    final remaining = maxInterpolation - (now - _anchorTime);
    Duration? delay;
    if (_next < _events.length) {
      final micros =
          (_events[_next].at - (_estimate(now) - _offset)).inMicroseconds /
          _rate;
      if (micros.isFinite && micros > 0 && micros <= remaining.inMicroseconds) {
        delay = Duration(microseconds: micros.ceil());
      }
    }
    final at = _animationAt(now);
    for (final item in _active) {
      final untilExpiry = item.start + fixedDuration - at;
      if (untilExpiry > Duration.zero &&
          untilExpiry <= remaining &&
          (delay == null || untilExpiry < delay)) {
        delay = untilExpiry;
      }
    }
    return delay;
  }

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
    _visualRevision++;
    if (_width > 0 && _height > 0) {
      // Fullscreen and control visibility are layout changes, not seeks.
      // Keep arrival times, lanes and the cursor: replaying dropped history
      // can displace comments already on screen. frame() projects their
      // existing progress onto the new width; text layouts are width-independent.
      final laneCount = _laneCount;
      _removeActiveWhere((item) => item.lane >= laneCount);
    }
    notifyListeners();
  }

  /// Holds only a bounded, sorted window supplied by the application layer.
  /// Set [sorted] only when the input is already in ascending media-time order.
  void replaceEvents(Iterable<DanmakuEvent> events, {bool sorted = false}) {
    final previous = {for (final event in _events) event.id: event};
    final ids = <String>{};
    final ordered = events
        .where(
          (e) =>
              e.at >= Duration.zero &&
              e.text.isNotEmpty &&
              e.text.length <= 300 &&
              e.fontSize.isFinite &&
              e.fontSize > 0 &&
              ids.add(e.id),
        )
        .toList();
    if (!sorted) ordered.sort((a, b) => a.at.compareTo(b.at));
    assert(
      !sorted ||
          Iterable<int>.generate(ordered.length - (ordered.isEmpty ? 0 : 1))
              .every((i) => ordered[i].at <= ordered[i + 1].at),
      'sorted events must be in media-time order',
    );
    // Queue capacity limits future admission, not the lifetime of items that
    // already have a lane. Still honor authoritative filtering/content changes.
    final supplied = {for (final event in ordered) event.id: event};
    if (ordered.length > maxPending) {
      final pivot = _lowerBound(ordered, _displayPosition);
      final from = (pivot - maxPending ~/ 4).clamp(
        0,
        ordered.length - maxPending,
      );
      _events = List.unmodifiable(ordered.sublist(from, from + maxPending));
      dropped += ordered.length - maxPending;
    } else {
      _events = List.unmodifiable(ordered);
    }
    final available = {for (final event in _events) event.id: event};
    _consumedIds.removeWhere((id) {
      final oldEvent = previous[id];
      final nextEvent = available[id];
      return oldEvent == null ||
          nextEvent == null ||
          !_sameEvent(oldEvent, nextEvent);
    });
    _removeActiveWhere((item) {
      final next = supplied[item.event.id];
      return next == null || !_sameEvent(item.event, next);
    });
    // Active IDs may sit outside the trimmed queue. Keep them consumed until
    // they expire so a later refresh cannot admit a second copy.
    _consumedIds.addAll(_active.map((item) => item.event.id));
    _rewindTo(_displayPosition);
    notifyListeners();
  }

  /// Release rebuildable pixels while retaining bounded text layout and media
  /// scheduling state. The owner reanchors to confirmed time before presenting.
  void releaseRasterCache() {
    _layouts.releaseRasters();
    _rasterProtectionDirty = true;
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
    final animation = _animationAt(now);
    if (animation != _anchorAnimation &&
        _active.any((item) => item.event.mode == DanmakuMode.scroll)) {
      // Also paint the last settled position when pausing between ticker frames.
      _visualRevision++;
    }
    _anchorAnimation = animation;
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
      _visualRevision++;
      _rasterProtectionDirty = true;
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
    _visualRevision++;
    _rasterProtectionDirty = true;
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

  void paintText(
    DanmakuEvent event,
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

  void _removeActiveWhere(bool Function(_Active) test) {
    final previousLength = _active.length;
    _active.removeWhere(test);
    if (_active.length != previousLength) {
      _rasterProtectionDirty = true;
      _visualRevision++;
    }
  }

  List<DanmakuPlacement> frame() {
    final result = <DanmakuPlacement>[];
    _visitFrame((event, x, y) {
      result.add(DanmakuPlacement(event: event, x: x, y: y));
    });
    return result;
  }

  /// Advance admission once and paint in arrival order without allocating a
  /// position snapshot for every visible comment. The caller owns clipping.
  void paintFrame(Canvas canvas, {double pixelRatio = 1}) {
    final ratio = pixelRatio.isFinite && pixelRatio > 0 ? pixelRatio : 1.0;
    _layouts.beginFrame(canvas, ratio);
    try {
      _visitFrame((event, x, y) {
        paintText(event, canvas, Offset(x, y), pixelRatio: ratio);
      });
    } finally {
      _layouts.endFrame();
    }
  }

  void _visitFrame(void Function(DanmakuEvent, double, double) visit) {
    final now = _now();
    final mediaAt = _estimate(now) - _offset;
    final at = _animationAt(now);
    final atMicros = at.inMicroseconds;
    final scrollMicros = _scrollLifetime.inMicroseconds;
    final fixedMicros = fixedDuration.inMicroseconds;
    _removeActiveWhere(
      (item) =>
          atMicros - item.start.inMicroseconds >=
          (item.event.mode == DanmakuMode.scroll ? scrollMicros : fixedMicros),
    );
    if (_width <= 0 || _height <= 0) return;
    // Animation-only frames need positions, not admission/collision indexes.
    if (_next < _events.length && _events[_next].at <= mediaAt) {
      _admit(mediaAt, at);
    }
    if (_rasterProtectionDirty) {
      _layouts.protectRasters(
        _active.map(
          (item) => (item.event.text, item.event.color, item.event.fontSize),
        ),
      );
      _rasterProtectionDirty = false;
      _rasterProtectionUpdateCount++;
    }
    final top = _top;
    final bottom = top + _availableHeight;
    for (final item in _active) {
      final ageMicros = atMicros - item.start.inMicroseconds;
      final x = item.event.mode == DanmakuMode.scroll
          ? _width - (_width + item.width) * (ageMicros / scrollMicros)
          : (_width - item.width) / 2;
      final y = item.event.mode == DanmakuMode.bottom
          ? bottom - (item.lane + 1) * _laneHeight
          : top + item.lane * _laneHeight;
      visit(item.event, x, y);
    }
  }

  void _admit(Duration mediaAt, Duration at) {
    final prepared = <(DanmakuEvent, Duration, double, double)>[];
    final texts = _mergeDuplicates
        ? {for (final item in _active) (item.event.mode, item.event.text)}
        : <(DanmakuMode, String)>{};
    while (_next < _events.length && _events[_next].at <= mediaAt) {
      if (prepared.length >= maxAdmissionsPerFrame) break;
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
      if (_mergeDuplicates && !texts.add((event.mode, event.text))) {
        continue;
      }
      final layout = _layout(event);
      prepared.add((event, at - age, layout.width, layout.height));
    }
    if (prepared.isEmpty) return;
    // Only due, eligible text is measured. Pending windows never populate or
    // churn the painter cache. Larger arrivals may reflow existing lanes only
    // when every occupied row still fits; otherwise discard the new arrival.
    var textHeight = _active.isEmpty
        ? DanmakuTextLayouts.minFontSize
        : _laneHeight - _lineSpacing;
    var occupiedLaneCount = 0;
    for (final item in _active) {
      if (item.height > textHeight) textHeight = item.height;
      if (item.lane >= occupiedLaneCount) occupiedLaneCount = item.lane + 1;
    }
    prepared.removeWhere((item) {
      if (item.$4 <= textHeight) return false;
      if ((_availableHeight / (item.$4 + _lineSpacing)).floor() <
          occupiedLaneCount) {
        dropped++;
        return true;
      }
      textHeight = item.$4;
      return false;
    });
    _laneHeight = textHeight + _lineSpacing;
    final laneCount = _laneCount;
    _removeActiveWhere((item) => item.lane >= laneCount);
    _laneIndexBuildCount++;
    final lanes = List.generate(
      DanmakuMode.values.length,
      (_) => List.generate(laneCount, (_) => <_Active>[]),
    );
    for (final item in _active) {
      lanes[item.event.mode.index][item.lane].add(item);
    }
    for (final (event, start, width, height) in prepared) {
      if (_active.length >= (_maxOnScreen == 0 ? maxVisible : _maxOnScreen)) {
        dropped++;
        continue;
      }
      final lane = _findLane(event, width, at, lanes[event.mode.index]);
      if (lane < 0) {
        dropped++;
        continue;
      }
      final item = _Active(event, start, width, height, lane);
      _active.add(item);
      _visualRevision++;
      _rasterProtectionDirty = true;
      lanes[event.mode.index][lane].add(item);
    }
  }

  int _findLane(
    DanmakuEvent event,
    double textWidth,
    Duration at,
    List<List<_Active>> lanes,
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
