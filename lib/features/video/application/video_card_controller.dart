import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../auth/application/auth_controller.dart';
import '../../playback/domain/playback_repository.dart';
import '../domain/video_card_interactions.dart';
import '../domain/video_repository.dart';
import '../domain/video_actions_repository.dart';
import 'video_controller.dart';
import 'video_actions_controller.dart';
import 'video_card_preview_playback.dart';

final videoCardPlaybackRepositoryProvider = Provider<PlaybackRepository>(
  (ref) => throw UnimplementedError('Video card playback repository'),
);
final videoCardPreviewPlaybackProvider = Provider<VideoCardPreviewPlayback>(
  (ref) => throw UnimplementedError('Video card preview playback'),
);

final videoCardControllerProvider = Provider<VideoCardController>((ref) {
  final signedIn = ref.watch(
    authControllerProvider.select((s) => (s.status, s.mid)),
  );
  final controller = VideoCardController(
    videos: ref.watch(videoRepositoryProvider),
    playback: ref.watch(videoCardPlaybackRepositoryProvider),
    previews: ref.watch(videoCardPreviewPlaybackProvider),
    actions: ref.watch(videoActionsRepositoryProvider),
    signedIn:
        signedIn.$2 != null && ref.read(authControllerProvider).isSignedIn,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// One active hover read; bounded, account-owned metadata and write outcomes.
final class VideoCardController implements VideoCardOperations {
  VideoCardController({
    required this.videos,
    required this.playback,
    required this.previews,
    required this.actions,
    required this.signedIn,
  });
  final VideoRepository videos;
  final PlaybackRepository playback;
  final VideoCardPreviewPlayback previews;
  final VideoActionsRepository actions;
  final bool signedIn;
  final _parts = <VideoId, VideoPart>{};
  final _added = <VideoId>{};
  final _uncertain = <VideoId>{};
  final _writes = <VideoId, RequestCancellation>{};
  RequestCancellation? _hover;
  bool _disposed = false;

  bool _current(String scope, RequestCancellation token) =>
      !_disposed && !token.isCancelled && actions.accountScope == scope;

  @override
  bool isAdded(VideoId id) => _added.contains(id);
  @override
  bool isUncertain(VideoId id) => _uncertain.contains(id);

  @override
  Future<VideoCardPreviewSession?> preview(
    VideoId id,
    RequestCancellation cancellation,
  ) async {
    if (_disposed || cancellation.isCancelled || !id.isValid) return null;
    _hover?.cancel();
    _hover = cancellation;
    final scope = actions.accountScope;
    try {
      var part = _parts.remove(id);
      if (part == null) {
        final detail = await videos.loadDetail(id, cancellation: cancellation);
        if (!_current(scope, cancellation) || detail.parts.isEmpty) return null;
        part = detail.parts.first;
      }
      _parts[id] = part;
      if (_parts.length > 24) _parts.remove(_parts.keys.first);
      final media = await playback.resolve(
        id,
        part.cid,
        quality: 32,
        cancellation: cancellation,
      );
      if (!_current(scope, cancellation)) return null;
      return await previews.start(media, cancellation);
    } on AppFailure {
      cancellation.cancel();
      rethrow;
    }
  }

  @override
  Future<WatchLaterResult> addWatchLater(VideoId id) async {
    if (_disposed) return WatchLaterResult.cancelled;
    if (!signedIn) return WatchLaterResult.signIn;
    if (_added.contains(id)) return WatchLaterResult.alreadyAdded;
    if (_uncertain.contains(id)) return WatchLaterResult.uncertain;
    if (_writes.containsKey(id) || _writes.length >= 8) {
      return WatchLaterResult.busy;
    }
    // Keep uncertain outcomes for this account lifetime; never evict and replay.
    if (!id.isValid ||
        _added.length + _uncertain.length + _writes.length >= 256) {
      return WatchLaterResult.failed;
    }
    final token = RequestCancellation();
    final scope = actions.accountScope;
    _writes[id] = token;
    try {
      // This endpoint accepts BVID directly; no interaction-state read is needed.
      await actions.watchLater((id: id, aid: ''), token);
      if (!_current(scope, token)) return WatchLaterResult.cancelled;
      _added.add(id);
      return WatchLaterResult.added;
    } on UnknownWriteOutcome {
      if (!_current(scope, token)) return WatchLaterResult.cancelled;
      _uncertain.add(id);
      return WatchLaterResult.uncertain;
    } on AppFailure catch (failure) {
      if (!_current(scope, token) || failure.kind == AppFailureKind.cancelled) {
        return WatchLaterResult.cancelled;
      }
      return failure.kind == AppFailureKind.authentication
          ? WatchLaterResult.signIn
          : WatchLaterResult.failed;
    } finally {
      _writes.remove(id);
    }
  }

  void dispose() {
    _disposed = true;
    _hover?.cancel();
    for (final token in _writes.values) {
      token.cancel();
    }
    _parts.clear();
    _added.clear();
    _uncertain.clear();
  }
}
