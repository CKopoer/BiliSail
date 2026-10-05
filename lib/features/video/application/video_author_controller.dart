import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/video_actions_repository.dart';
import '../domain/video_author_repository.dart';

final videoAuthorRepositoryProvider = Provider<VideoAuthorRepository>(
  (ref) => throw UnimplementedError('VideoAuthorRepository'),
);
final videoAuthorControllerProvider = NotifierProvider.autoDispose
    .family<VideoAuthorController, VideoAuthorState, VideoAuthorId>(
      VideoAuthorController.new,
    );

final class VideoAuthorState {
  const VideoAuthorState({
    this.author,
    this.signedIn = false,
    this.isSelf = false,
    this.loading = false,
    this.busy = false,
    this.uncertain = false,
    this.message,
  });
  final VideoAuthor? author;
  final bool signedIn, isSelf, loading, busy, uncertain;
  final String? message;

  VideoAuthorState copyWith({
    VideoAuthor? author,
    bool? loading,
    bool? busy,
    bool? uncertain,
    String? message,
  }) => VideoAuthorState(
    author: author ?? this.author,
    signedIn: signedIn,
    isSelf: isSelf,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    uncertain: uncertain ?? this.uncertain,
    message: message,
  );
}

class VideoAuthorController extends Notifier<VideoAuthorState> {
  VideoAuthorController(this.id);
  final VideoAuthorId id;
  RequestCancellation _cancellation = RequestCancellation();
  int _generation = 0;

  @override
  VideoAuthorState build() {
    final auth = ref.watch(authControllerProvider);
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    final generation = ++_generation;
    ref.onDispose(() {
      ++_generation;
      _cancellation.cancel();
    });
    Future<void>.microtask(() {
      if (ref.mounted && generation == _generation) return refresh();
    });
    return VideoAuthorState(
      signedIn: auth.isSignedIn,
      isSelf: auth.isSignedIn && auth.mid == id.value,
      loading: true,
    );
  }

  bool _current(int generation, String scope, int epoch) {
    if (!ref.mounted || generation != _generation) return false;
    final repo = ref.read(videoAuthorRepositoryProvider);
    if (repo.accountScope != scope || repo.sessionEpoch != epoch) {
      // A restored session may keep the same AuthState identity. Drop its old
      // operation and rebuild even if no distinct auth notification arrived.
      ref.invalidateSelf();
      return false;
    }
    return true;
  }

  Future<void> refresh() async {
    if (!ref.mounted || state.busy) return;
    final repo = ref.read(videoAuthorRepositoryProvider);
    final scope = repo.accountScope;
    final epoch = repo.sessionEpoch;
    final generation = ++_generation;
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    state = state.copyWith(loading: true);
    try {
      final author = await repo.load(id, _cancellation);
      if (!_current(generation, scope, epoch)) return;
      state = state.copyWith(author: author, loading: false, uncertain: false);
    } catch (error) {
      if (!_current(generation, scope, epoch)) return;
      state = state.copyWith(loading: false, message: _message(error));
    }
  }

  Future<void> toggleFollow() async {
    final author = state.author;
    if (author == null ||
        !state.signedIn ||
        state.isSelf ||
        state.busy ||
        state.loading ||
        state.uncertain) {
      return;
    }
    final repo = ref.read(videoAuthorRepositoryProvider);
    final scope = repo.accountScope;
    final epoch = repo.sessionEpoch;
    final generation = ++_generation;
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    state = state.copyWith(busy: true);
    try {
      await repo.follow(id, !author.following, _cancellation);
      if (!_current(generation, scope, epoch)) return;
      state = state.copyWith(
        author: author.withFollowing(!author.following),
        busy: false,
      );
    } catch (error) {
      if (!_current(generation, scope, epoch)) return;
      state = state.copyWith(
        busy: false,
        uncertain: error is UnknownWriteOutcome,
        message: error is UnknownWriteOutcome
            ? '关注结果暂时无法确认，请刷新状态后再操作'
            : _message(error),
      );
    }
  }

  static String? _message(Object error) => error is AppFailure
      ? (error.kind == AppFailureKind.cancelled ? null : error.message)
      : 'UP 主信息加载或操作失败，请重试';
}
