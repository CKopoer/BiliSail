import 'dart:math' as math;

import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/playback/application/playback_session.dart';
import 'collapsed_playback_header.dart';

/// Rebuilds layout only when listening mode changes, never on media position.
/// The child player may initialize the page's lazy session on its first build.
class PlaybackLayoutBuilder extends ConsumerStatefulWidget {
  const PlaybackLayoutBuilder({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    BoxConstraints constraints,
    bool listening,
  )
  builder;

  @override
  ConsumerState<PlaybackLayoutBuilder> createState() =>
      _PlaybackLayoutBuilderState();

  static double listeningHeight(double availableHeight) =>
      math.min(availableHeight, math.max(180, availableHeight * .5));
}

/// Selects the layout inputs without rebuilding on media clock ticks.
class PlaybackLayoutSnapshot extends ConsumerStatefulWidget {
  const PlaybackLayoutSnapshot({
    super.key,
    this.allowCollapse = false,
    required this.builder,
  });

  final bool allowCollapse;
  final Widget Function(
    BuildContext,
    VideoDimensions?,
    CollapsedPlaybackAction?,
  )
  builder;

  @override
  ConsumerState<PlaybackLayoutSnapshot> createState() =>
      _PlaybackLayoutSnapshotState();
}

class _PlaybackLayoutSnapshotState
    extends ConsumerState<PlaybackLayoutSnapshot> {
  PlaybackSession? _session;
  (VideoDimensions?, CollapsedPlaybackAction?) _layout = (null, null);
  int? _playedGeneration;

  (VideoDimensions?, CollapsedPlaybackAction?) _select() {
    final session = _session;
    if (session == null) return (null, null);
    final snapshot = session.snapshots.value;
    if (snapshot.phase == PlaybackPhase.playing) {
      _playedGeneration = snapshot.generation;
    }
    if (!widget.allowCollapse || session.isResolving || session.error != null) {
      return (snapshot.videoDimensions, null);
    }
    final started =
        _playedGeneration == snapshot.generation ||
        snapshot.position > Duration.zero;
    final action = switch (snapshot.phase) {
      PlaybackPhase.ended => CollapsedPlaybackAction.replay,
      PlaybackPhase.ready || PlaybackPhase.paused
          when !snapshot.desiredPlaying =>
        started ? CollapsedPlaybackAction.resume : CollapsedPlaybackAction.play,
      _ => null,
    };
    return (snapshot.videoDimensions, action);
  }

  void _onSnapshot() {
    final layout = _select();
    if (layout != _layout) setState(() => _layout = layout);
  }

  @override
  void dispose() {
    _session?.removeListener(_onSnapshot);
    _session?.snapshots.removeListener(_onSnapshot);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.exists(playbackSessionProvider)
        ? ref.watch(playbackSessionProvider)
        : null;
    if (!identical(session, _session)) {
      _session?.removeListener(_onSnapshot);
      _session?.snapshots.removeListener(_onSnapshot);
      _session = session;
      _playedGeneration = null;
      session?.snapshots.addListener(_onSnapshot);
      session?.addListener(_onSnapshot);
    }
    _layout = _select();
    if (session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.exists(playbackSessionProvider)) setState(() {});
      });
    }
    return widget.builder(context, _layout.$1, _layout.$2);
  }
}

class _PlaybackLayoutBuilderState extends ConsumerState<PlaybackLayoutBuilder> {
  PlaybackSession? _session;
  bool _listening = false;

  void _onSession() {
    final listening = _session?.audioOnly ?? false;
    if (listening == _listening) return;
    setState(() => _listening = listening);
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.exists(playbackSessionProvider)
        ? ref.watch(playbackSessionProvider)
        : null;
    if (!identical(session, _session)) {
      _session?.removeListener(_onSession);
      _session = session;
      _listening = session?.audioOnly ?? false;
      session?.addListener(_onSession);
    }
    if (session == null) {
      // Do not create engines for placeholder players or workspace Back
      // previews. Discover a session only if the child actually created one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.exists(playbackSessionProvider)) setState(() {});
      });
    }
    return LayoutBuilder(
      builder: (context, constraints) =>
          widget.builder(context, constraints, _listening),
    );
  }
}
