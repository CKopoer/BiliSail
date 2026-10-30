import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../application/playback_session.dart';
import '../domain/playback_repository.dart';

/// A lazy, sentence-driven listening transcript. The media clock only moves
/// the wheel when its current cue changes. Only an explicit tap seeks.
class AudioSubtitleLyrics extends StatefulWidget {
  const AudioSubtitleLyrics({super.key, required this.session});

  final PlaybackSession session;

  @override
  State<AudioSubtitleLyrics> createState() => _AudioSubtitleLyricsState();
}

class _AudioSubtitleLyricsState extends State<AudioSubtitleLyrics>
    with WidgetsBindingObserver {
  late final List<SubtitleCue> _sourceCues = widget.session.subtitleCues;
  late final int _generation = widget.session.sourceGeneration;
  late final List<SubtitleCue> _cues;
  late final Map<SubtitleCue, int> _indices;
  late final FixedExtentScrollController _scroll;
  SubtitleCue? _playing;
  int _center = 0;
  int _browseCacheAnchor = 0;
  int? _preview;
  int _revision = 0;
  bool _browsing = false;
  bool _subscribed = false;
  bool _visible = true;
  bool _tickerEnabled = true;
  double? _itemExtent;

  bool get _currentSource =>
      widget.session.sourceGeneration == _generation &&
      identical(widget.session.subtitleCues, _sourceCues);

  @override
  void initState() {
    super.initState();
    // Keep equal-start cues in their original order and leave the session's
    // overlap semantics intact. This work runs once per source/track, not tick.
    final entries =
        _sourceCues.indexed
            .where(
              (entry) =>
                  entry.$2.end > entry.$2.start &&
                  entry.$2.text.trim().isNotEmpty,
            )
            .toList()
          ..sort((a, b) {
            final byTime = a.$2.start.compareTo(b.$2.start);
            return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
          });
    _cues = [for (final entry in entries) entry.$2];
    _indices = {for (var i = 0; i < _cues.length; i++) _cues[i]: i};
    _readPosition();
    _scroll = FixedExtentScrollController(initialItem: _center);
    WidgetsBinding.instance.addObserver(this);
    _visible = _isVisible(WidgetsBinding.instance.lifecycleState);
  }

  bool _isVisible(AppLifecycleState? state) =>
      state != AppLifecycleState.hidden &&
      state != AppLifecycleState.paused &&
      state != AppLifecycleState.detached;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncSubscription();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = _isVisible(state);
    _syncSubscription();
    if (mounted) setState(() {});
  }

  void _syncSubscription() {
    final active = _visible && _tickerEnabled;
    if (active == _subscribed) return;
    _subscribed = active;
    if (active) {
      widget.session.snapshots.addListener(_onSnapshot);
      _readPosition();
      _follow(animate: false);
    } else {
      widget.session.snapshots.removeListener(_onSnapshot);
      _revision++;
      _browsing = false;
      _preview = null;
      // Cancel any drag/ballistic/automatic animation before hiding the view.
      if (_scroll.hasClients) _scroll.jumpToItem(_center);
    }
  }

  void _readPosition() {
    if (_cues.isEmpty || !_currentSource) return;
    final position = widget.session.snapshots.value.position;
    _playing = widget.session.subtitleAt(position);
    final playingIndex = _indices[_playing];
    if (playingIndex != null) {
      _center = playingIndex;
      return;
    }
    // In a subtitle gap keep the preceding sentence centered, without marking
    // it as currently spoken. Also handles seeks before the first/after last.
    var low = 0;
    var high = _cues.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_cues[middle].start <= position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _center = (low - 1).clamp(0, _cues.length - 1);
  }

  void _onSnapshot() {
    if (!_subscribed || !_currentSource || _preview != null) {
      return;
    }
    final previous = (_playing, _center);
    _readPosition();
    if (previous == (_playing, _center)) return;
    setState(() {});
    if (!_browsing) _follow();
  }

  void _follow({bool animate = true}) {
    final revision = _revision;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          !_subscribed ||
          !_currentSource ||
          revision != _revision ||
          _browsing ||
          _preview != null ||
          !_scroll.hasClients) {
        return;
      }
      if (animate && !MediaQuery.disableAnimationsOf(context)) {
        await _scroll.animateToItem(
          _center,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scroll.jumpToItem(_center);
      }
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (!_subscribed || !_currentSource || notification.depth != 0) {
      return false;
    }
    if ((notification is ScrollStartNotification &&
            notification.dragDetails != null) ||
        (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle)) {
      // A real drag can interrupt auto-follow, including with a desktop mouse.
      _revision++;
      _browsing = true;
      if (_preview != null) setState(() => _preview = null);
    }
    return false;
  }

  Future<void> _seek(int index) async {
    final session = widget.session;
    if (!_subscribed ||
        !_currentSource ||
        session.isResolving ||
        session.media == null ||
        session.error != null) {
      return;
    }
    final revision = ++_revision;
    _browsing = false;
    setState(() => _preview = index);
    try {
      final duration = session.snapshots.value.duration;
      final start = _cues[index].start;
      await session.seek(
        start < Duration.zero
            ? Duration.zero
            : duration > Duration.zero && start > duration
            ? duration
            : start,
      );
    } finally {
      if (mounted && revision == _revision && _currentSource) {
        setState(() {
          _preview = null;
          _readPosition();
        });
        _follow();
      }
    }
  }

  void _cancelDrag(PointerCancelEvent event) {
    if (!_browsing) return;
    _revision++;
    _browsing = false;
    setState(() {
      _preview = null;
      _readPosition();
    });
    _follow(animate: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_subscribed) widget.session.snapshots.removeListener(_onSnapshot);
    _revision++;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_subscribed) return const SizedBox.expand();
    if (_cues.isEmpty) return const Center(child: Text('暂无可用字幕'));
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final fontSize = bounds.maxHeight < 64
              ? 16.0
              : bounds.maxWidth >= 480
              ? 22.0
              : 18.0;
          final lineHeight =
              MediaQuery.textScalerOf(context).scale(fontSize) * 1.3;
          final maxLines = bounds.maxHeight < lineHeight * 4 ? 1 : 2;
          final extent = (lineHeight * maxLines + 20).clamp(48.0, 160.0);
          if (_itemExtent != null && _itemExtent != extent) {
            // A resize/text-scale change alters pixels per sentence. Preserve
            // the media sentence rather than reinterpreting the old offset.
            _revision++;
            _browsing = false;
            _preview = null;
            _readPosition();
            _follow(animate: false);
          }
          _itemExtent = extent;
          return ScrollConfiguration(
            behavior: const MaterialScrollBehavior().copyWith(
              scrollbars: false,
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
                PointerDeviceKind.invertedStylus,
              },
            ),
            child: Listener(
              onPointerCancel: _cancelDrag,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: ListWheelScrollView.useDelegate(
                  key: const ValueKey('audio-subtitle-lyrics'),
                  controller: _scroll,
                  itemExtent: extent,
                  physics: const FixedExtentScrollPhysics(),
                  diameterRatio: 100,
                  perspective: .001,
                  onSelectedItemChanged: (index) {
                    if (_browsing && (index - _browseCacheAnchor).abs() >= 16) {
                      // ListWheel caches delegate widgets until a rebuild.
                      // Bound that cache even during long paused browsing.
                      setState(() => _browseCacheAnchor = index);
                    }
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: _cues.length,
                    builder: (context, index) {
                      final cue = _cues[index];
                      final selected =
                          _preview == index ||
                          (_preview == null && identical(_playing, cue));
                      return Semantics(
                        selected: selected,
                        button: true,
                        label: '跳转到 ${_time(cue.start)}，${cue.text}',
                        excludeSemantics: true,
                        onTap: () => unawaited(_seek(index)),
                        child: Tooltip(
                          message: cue.text,
                          child: InkWell(
                            key: ValueKey('audio-subtitle-$index'),
                            onTap: () => unawaited(_seek(index)),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Center(
                                child: Text(
                                  cue.text,
                                  maxLines: maxLines,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    height: 1.3,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: selected
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _time(Duration value) {
  final minutes = value.inMinutes.toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
