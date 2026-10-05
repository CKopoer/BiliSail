import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/favorite_folder_repository.dart';

final favoriteFolderRepositoryProvider = Provider<FavoriteFolderRepository>(
  (ref) => throw UnimplementedError('FavoriteFolderRepository'),
);
final favoriteFolderControllerProvider = NotifierProvider.autoDispose
    .family<
      FavoriteFolderController,
      FavoriteFolderEditorState,
      FavoriteFolderTarget
    >(FavoriteFolderController.new);

final class FavoriteFolderEditorState {
  const FavoriteFolderEditorState({
    this.info,
    this.active = true,
    this.loading = false,
    this.busy = false,
    this.uncertain = false,
    this.message,
  });
  final FavoriteFolderInfo? info;
  final bool active, loading, busy, uncertain;
  final String? message;
}

final class FavoriteFolderController
    extends Notifier<FavoriteFolderEditorState> {
  FavoriteFolderController(this.target);
  final FavoriteFolderTarget target;
  RequestCancellation _cancellation = RequestCancellation();
  int _generation = 0;
  int? _loadedEpoch;
  FavoriteFolderEdit? _attempt;

  @override
  FavoriteFolderEditorState build() {
    final auth = ref.watch(
      authControllerProvider.select(
        (value) => (isSignedIn: value.isSignedIn, mid: value.mid),
      ),
    );
    _cancellation.cancel();
    _loadedEpoch = null;
    _attempt = null;
    ++_generation;
    ref.onDispose(() {
      ++_generation;
      _cancellation.cancel();
    });
    final active = auth.isSignedIn && target.scope == 'user:${auth.mid}';
    if (active) Future<void>.microtask(refresh);
    return FavoriteFolderEditorState(
      active: active,
      loading: active,
      message: active ? null : '登录状态已变化，请关闭后重新打开',
    );
  }

  bool _current(int generation, int epoch) {
    if (!ref.mounted || generation != _generation) return false;
    final repository = ref.read(favoriteFolderRepositoryProvider);
    if (repository.accountScope != target.scope ||
        repository.sessionEpoch != epoch) {
      _cancellation.cancel();
      _loadedEpoch = null;
      state = const FavoriteFolderEditorState(
        active: false,
        message: '登录状态已变化，请关闭后重新打开',
      );
      return false;
    }
    return !_cancellation.isCancelled;
  }

  /// Returns true when a previously uncertain save is confirmed by a read.
  Future<bool> refresh() async {
    if (!ref.mounted || !state.active || state.busy) return false;
    final repository = ref.read(favoriteFolderRepositoryProvider);
    final epoch = repository.sessionEpoch;
    final generation = ++_generation;
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    if (!_current(generation, epoch)) return false;
    final uncertain = state.uncertain;
    state = FavoriteFolderEditorState(
      info: state.info,
      loading: true,
      uncertain: uncertain,
    );
    try {
      final info = await repository.load(target, _cancellation);
      if (!_current(generation, epoch)) return false;
      _loadedEpoch = epoch;
      final confirmed = uncertain && _attempt?.matches(info) == true;
      _attempt = null;
      state = FavoriteFolderEditorState(
        info: info,
        message: uncertain && !confirmed ? '已读取服务器信息，请核对后再保存' : null,
      );
      return confirmed;
    } catch (error) {
      if (!_current(generation, epoch)) return false;
      state = FavoriteFolderEditorState(
        info: state.info,
        uncertain: uncertain,
        message: _message(error),
      );
      return false;
    }
  }

  Future<bool> save(FavoriteFolderEdit edit) async {
    if (!ref.mounted ||
        !state.active ||
        state.info == null ||
        state.busy ||
        state.loading ||
        state.uncertain) {
      return false;
    }
    if (edit.title.trim().isEmpty) {
      state = FavoriteFolderEditorState(info: state.info, message: '请输入收藏夹名称');
      return false;
    }
    final repository = ref.read(favoriteFolderRepositoryProvider);
    final epoch = _loadedEpoch;
    final generation = ++_generation;
    if (epoch == null || !_current(generation, epoch)) return false;
    final normalized = FavoriteFolderEdit(
      title: edit.title.trim(),
      intro: edit.intro,
      isPrivate: edit.isPrivate,
    );
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    _attempt = normalized;
    state = FavoriteFolderEditorState(info: state.info, busy: true);
    try {
      await repository.update(target, normalized, _cancellation);
      if (!_current(generation, epoch)) return false;
      state = FavoriteFolderEditorState(
        info: FavoriteFolderInfo(
          id: target.id,
          title: normalized.title,
          intro: normalized.intro,
          isPrivate: normalized.isPrivate,
        ),
      );
      _attempt = null;
      return true;
    } catch (error) {
      if (!_current(generation, epoch)) return false;
      state = FavoriteFolderEditorState(
        info: state.info,
        uncertain: error is FavoriteFolderWriteUncertain,
        message: error is FavoriteFolderWriteUncertain
            ? '保存结果暂时无法确认，请先重新读取服务器信息'
            : _message(error),
      );
      return false;
    }
  }

  static String? _message(Object error) =>
      error is AppFailure && error.kind == AppFailureKind.cancelled
      ? null
      : error is AppFailure
      ? error.message
      : '收藏夹操作失败，请重试';
}
