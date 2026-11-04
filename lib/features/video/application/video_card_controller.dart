import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../auth/application/auth_controller.dart';
import '../../playback/domain/video_preview_repository.dart';
import '../domain/video_card_interactions.dart';
import '../domain/video_repository.dart';
import '../domain/video_actions_repository.dart';
import 'video_controller.dart';
import 'video_actions_controller.dart';
import 'video_card_preview_playback.dart';

final videoCardPlaybackRepositoryProvider = Provider<VideoPreviewRepository>(
  (ref) => throw UnimplementedError('Video card playback repository'),
);
final videoCardPreviewPlaybackProvider = Provider<VideoCardPreviewPlayback>(
  (ref) => throw UnimplementedError('Video card preview playback'),
);
final videoCardWatchLaterAddedProvider = Provider<void Function(VideoId)?>(
  (ref) => null,
);
final videoCardWatchLaterRepositoryProvider =
    Provider<VideoCardWatchLaterRepository?>((ref) => null);

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
    onWatchLaterAdded: ref.watch(videoCardWatchLaterAddedProvider),
    watchLater: ref.watch(videoCardWatchLaterRepositoryProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// One active hover read; bounded, account-owned metadata and write outcomes.
final class VideoCardController
    implements
        VideoCardOperations,
        VideoCardWatchLaterRemovalSync,
        VideoCardWatchLaterToggle {
  VideoCardController({
    required this.videos,
    required this.playback,
    required this.previews,
    required this.actions,
    required this.signedIn,
    this.onWatchLaterAdded,
    this.watchLater,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final VideoRepository videos;
  final VideoPreviewRepository playback;
  final VideoCardPreviewPlayback previews;
  final VideoActionsRepository actions;
  final bool signedIn;
  final void Function(VideoId)? onWatchLaterAdded;
  final VideoCardWatchLaterRepository? watchLater;
  final DateTime Function() _now;
  final _changes = StreamController<VideoId>.broadcast();
  final _membership = <VideoId, String>{};
  RequestCancellation? _membershipToken;
  Future<bool>? _membershipRead;
  DateTime? _membershipLoadedAt;
  int _membershipRevision = 0;
  final _parts = <VideoId, VideoPart>{};
  final _added = <VideoId>{};
  final _uncertain = <VideoId>{};
  final _writes = <VideoId, RequestCancellation>{};
  final _removing = <VideoId>{};
  RequestCancellation? _hover;
  bool _disposed = false;

  bool _current(String scope, RequestCancellation token) =>
      !_disposed && !token.isCancelled && actions.accountScope == scope;

  @override
  bool isAdded(VideoId id) =>
      !_uncertain.contains(id) &&
      (_added.contains(id) || _membership.containsKey(id));
  @override
  bool isUncertain(VideoId id) => _uncertain.contains(id);

  @override
  Stream<VideoId> get watchLaterChanges => _changes.stream;

  @override
  bool isWatchLaterBusy(VideoId id) =>
      _writes.containsKey(id) || _removing.contains(id);

  @override
  Future<bool> refreshWatchLater() {
    if (_disposed) return Future.value(false);
    if (!signedIn || watchLater == null) return Future.value(true);
    final pending = _membershipRead;
    if (pending != null) return pending;
    final loadedAt = _membershipLoadedAt;
    if (loadedAt != null &&
        _now().difference(loadedAt) < const Duration(seconds: 30)) {
      return Future.value(true);
    }
    return _membershipRead = _loadMembership().whenComplete(() {
      _membershipRead = null;
    });
  }

  Future<bool> _loadMembership() async {
    final repository = watchLater;
    if (repository == null) return true;
    final token = _membershipToken = RequestCancellation();
    final scope = actions.accountScope;
    final revision = _membershipRevision;
    try {
      final entries = await repository.load(token);
      if (!_current(scope, token)) return false;
      // A snapshot started before a write cannot undo that confirmed outcome.
      if (revision != _membershipRevision) return false;
      final changed = {..._membership.keys, ..._added, ...entries.keys};
      _membership
        ..clear()
        ..addEntries(entries.entries.take(1000));
      _added.clear();
      _membershipLoadedAt = _now();
      for (final id in changed) {
        _changes.add(id);
      }
      return true;
    } on AppFailure {
      return false;
    }
  }

  @override
  bool beginWatchLaterRemoval(VideoId id) {
    if (_disposed ||
        _uncertain.contains(id) ||
        _writes.containsKey(id) ||
        _removing.contains(id)) {
      return false;
    }
    _removing.add(id);
    _membershipRevision++;
    _changes.add(id);
    return true;
  }

  @override
  void finishWatchLaterRemoval(
    VideoId id, {
    bool removed = false,
    bool uncertain = false,
  }) {
    if (_disposed || !_removing.remove(id)) return;
    _membershipRevision++;
    if (removed) {
      _added.remove(id);
      _membership.remove(id);
      _uncertain.remove(id);
    } else if (uncertain) {
      _added.remove(id);
      _uncertain.add(id);
    }
    _changes.add(id);
  }

  @override
  Future<WatchLaterResult> removeWatchLater(VideoId id) async {
    if (_disposed) return WatchLaterResult.cancelled;
    if (!signedIn) return WatchLaterResult.signIn;
    if (_uncertain.contains(id)) return WatchLaterResult.uncertain;
    final repository = watchLater;
    if (repository == null || !id.isValid || !isAdded(id)) {
      return WatchLaterResult.failed;
    }
    if (_writes.length >= 8 || !beginWatchLaterRemoval(id)) {
      return WatchLaterResult.busy;
    }
    final token = RequestCancellation();
    final scope = actions.accountScope;
    _writes[id] = token;
    var removed = false, uncertain = false;
    try {
      var aid = _membership[id];
      aid ??= (await videos.loadDetail(id, cancellation: token)).aid;
      if (!_current(scope, token)) return WatchLaterResult.cancelled;
      if (aid == null || !RegExp(r'^[1-9][0-9]*$').hasMatch(aid)) {
        return WatchLaterResult.failed;
      }
      removed = await repository.remove(id, aid, token);
      if (!_current(scope, token)) return WatchLaterResult.cancelled;
      return removed ? WatchLaterResult.removed : WatchLaterResult.busy;
    } on UnknownWriteOutcome {
      if (!_current(scope, token)) return WatchLaterResult.cancelled;
      uncertain = true;
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
      finishWatchLaterRemoval(id, removed: removed, uncertain: uncertain);
    }
  }

  @override
  Future<VideoCardPreviewSession?> preview(
    VideoId id,
    RequestCancellation cancellation, {
    String? cid,
  }) async {
    if (_disposed || cancellation.isCancelled || !id.isValid) return null;
    _hover?.cancel();
    _hover = cancellation;
    final scope = actions.accountScope;
    try {
      var part = _parts.remove(id);
      final suppliedCid = cid != null && RegExp(r'^[1-9][0-9]*$').hasMatch(cid)
          ? cid
          : null;
      if (part == null && suppliedCid == null) {
        final detail = await videos.loadDetail(id, cancellation: cancellation);
        if (!_current(scope, cancellation) || detail.parts.isEmpty) return null;
        part = detail.parts.first;
      }
      if (part != null) {
        _parts[id] = part;
        if (_parts.length > 24) _parts.remove(_parts.keys.first);
      }
      final previewCid = suppliedCid ?? part?.cid;
      if (previewCid == null) return null;
      final media = await playback.resolve(
        id,
        previewCid,
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
    if (_removing.contains(id)) return WatchLaterResult.busy;
    if (isAdded(id)) return WatchLaterResult.alreadyAdded;
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
    _membershipRevision++;
    _changes.add(id);
    try {
      // This endpoint accepts BVID directly; no interaction-state read is needed.
      await actions.watchLater((id: id, aid: ''), token);
      if (!_current(scope, token)) return WatchLaterResult.cancelled;
      _added.add(id);
      onWatchLaterAdded?.call(id);
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
      _membershipRevision++;
      if (!_disposed) _changes.add(id);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _hover?.cancel();
    _membershipToken?.cancel();
    for (final token in _writes.values) {
      token.cancel();
    }
    _parts.clear();
    _added.clear();
    _uncertain.clear();
    _removing.clear();
    _membership.clear();
    unawaited(_changes.close());
  }
}
