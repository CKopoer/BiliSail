import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/foundation.dart';

/// Layout tests need only mode notifications, without constructing an engine.
class PlaybackLayoutSessionFake extends ChangeNotifier
    implements PlaybackSession {
  @override
  bool audioOnly = false;

  final _snapshots = _LayoutSnapshots();

  @override
  ValueNotifier<PlaybackSnapshot> get snapshots => _snapshots;

  bool get hasSnapshotListeners => _snapshots.hasLayoutListeners;

  @override
  void dispose() {
    snapshots.dispose();
    super.dispose();
  }

  @override
  Future<void> setAudioOnly(bool enabled) async {
    audioOnly = enabled;
    notifyListeners();
  }

  void publishMetadata() => notifyListeners();

  bool get hasLayoutListeners => hasListeners;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused layout fixture member: ${invocation.memberName}',
  );
}

class _LayoutSnapshots extends ValueNotifier<PlaybackSnapshot> {
  _LayoutSnapshots()
    : super(const PlaybackSnapshot(phase: PlaybackPhase.idle, generation: 0));

  bool get hasLayoutListeners => hasListeners;
}
