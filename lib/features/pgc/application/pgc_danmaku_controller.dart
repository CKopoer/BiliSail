import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../../playback/application/playback_session.dart';
import '../../playback/domain/content_playback.dart';
import '../domain/pgc_danmaku_repository.dart';

final pgcDanmakuRepositoryProvider = Provider<PgcDanmakuRepository>(
  (ref) =>
      throw UnimplementedError('PgcDanmakuRepository must be provided by app'),
);
final pgcDanmakuControllerProvider = NotifierProvider.autoDispose
    .family<PgcDanmakuController, PgcDanmakuState, PgcDanmakuTarget>(
      PgcDanmakuController.new,
      dependencies: [playbackSessionProvider],
    );

final class PgcDanmakuState {
  const PgcDanmakuState({
    this.signedIn = false,
    this.busy = false,
    this.uncertain = false,
    this.message,
  });
  final bool signedIn, busy, uncertain;
  final String? message;
}

/// Sends only on an explicit composer action and fixes account, source and
/// confirmed position before the single write. Source switches cancel the write
/// and prevent its result from changing the next episode's draft/feedback.
final class PgcDanmakuController extends Notifier<PgcDanmakuState> {
  PgcDanmakuController(this.target);
  final PgcDanmakuTarget target;
  RequestCancellation? _active;
  int _revision = 0;

  @override
  PgcDanmakuState build() {
    final auth = ref.watch(authControllerProvider);
    final session = ref.watch(playbackSessionProvider);
    _active?.cancel();
    ++_revision;
    var sourceGeneration = session.sourceGeneration;
    void onSourceChanged() {
      if (!ref.mounted || sourceGeneration == session.sourceGeneration) return;
      sourceGeneration = session.sourceGeneration;
      _active?.cancel();
      ++_revision;
      state = PgcDanmakuState(signedIn: state.signedIn);
    }

    session.addListener(onSourceChanged);
    ref.onDispose(() {
      ++_revision;
      _active?.cancel();
      session.removeListener(onSourceChanged);
    });
    return PgcDanmakuState(signedIn: auth.isSignedIn);
  }

  bool _matchesSource(PlaybackSession session) =>
      !session.isResolving &&
      session.media != null &&
      session.danmakuCid == target.cid &&
      switch (session.contentTarget) {
        PgcPlaybackTarget(:final episodeId) => episodeId == target.episodeId,
        _ => false,
      };

  Future<bool> send(
    String text, {
    required int mode,
    required int color,
  }) async {
    final message = text.trim();
    if (!state.signedIn || state.busy || state.uncertain) return false;
    if (message.isEmpty ||
        message.runes.length > 100 ||
        !target.video.isValid ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(target.cid) ||
        !const [1, 4, 5].contains(mode) ||
        color < 0 ||
        color > 0xffffff) {
      return false;
    }
    final session = ref.read(playbackSessionProvider);
    final repository = ref.read(pgcDanmakuRepositoryProvider);
    final scope = repository.accountScope;
    final epoch = repository.sessionEpoch;
    final sourceGeneration = session.sourceGeneration;
    if (!_matchesSource(session) || session.sourceAccountScope != scope) {
      return false;
    }
    final position = session.snapshots.value.position;
    final duration = session.media?.duration ?? Duration.zero;
    if (position.isNegative ||
        (duration > Duration.zero && position > duration)) {
      return false;
    }
    final cancellation = RequestCancellation();
    _active = cancellation;
    final revision = ++_revision;
    bool current() =>
        ref.mounted &&
        revision == _revision &&
        !cancellation.isCancelled &&
        repository.accountScope == scope &&
        repository.sessionEpoch == epoch &&
        session.sourceGeneration == sourceGeneration &&
        _matchesSource(session);
    state = PgcDanmakuState(signedIn: true, busy: true);
    try {
      await repository.send(
        target,
        message,
        position,
        mode: mode,
        color: color,
        cancellation: cancellation,
      );
      if (!current()) return false;
      state = const PgcDanmakuState(signedIn: true, message: '弹幕已发送');
      return true;
    } catch (error) {
      if (!current()) return false;
      if (error is AppFailure && error.kind == AppFailureKind.cancelled) {
        state = const PgcDanmakuState(signedIn: true);
        return false;
      }
      final uncertain = error is PgcDanmakuWriteUncertain;
      state = PgcDanmakuState(
        signedIn: true,
        uncertain: uncertain,
        message: uncertain
            ? '发送结果暂时无法确认，请核对后再发送，未自动重试'
            : error is AppFailure
            ? error.message
            : '弹幕发送失败，请稍后重试',
      );
      return false;
    }
  }
}
