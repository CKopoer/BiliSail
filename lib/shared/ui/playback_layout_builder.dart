import 'dart:math' as math;

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/playback/application/playback_session.dart';

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

/// Selects decoded display dimensions without rebuilding on position updates.
class PlaybackVideoDimensions extends ConsumerStatefulWidget {
  const PlaybackVideoDimensions({super.key, required this.builder});

  final Widget Function(BuildContext context, VideoDimensions? dimensions)
  builder;

  @override
  ConsumerState<PlaybackVideoDimensions> createState() =>
      _PlaybackVideoDimensionsState();
}

class _PlaybackVideoDimensionsState
    extends ConsumerState<PlaybackVideoDimensions> {
  PlaybackSession? _session;
  VideoDimensions? _dimensions;

  void _onSnapshot() {
    final dimensions = _session?.snapshots.value.videoDimensions;
    if (dimensions == _dimensions) return;
    setState(() => _dimensions = dimensions);
  }

  @override
  void dispose() {
    _session?.snapshots.removeListener(_onSnapshot);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.exists(playbackSessionProvider)
        ? ref.watch(playbackSessionProvider)
        : null;
    if (!identical(session, _session)) {
      _session?.snapshots.removeListener(_onSnapshot);
      _session = session;
      _dimensions = session?.snapshots.value.videoDimensions;
      session?.snapshots.addListener(_onSnapshot);
    }
    if (session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.exists(playbackSessionProvider)) setState(() {});
      });
    }
    return widget.builder(context, _dimensions);
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
