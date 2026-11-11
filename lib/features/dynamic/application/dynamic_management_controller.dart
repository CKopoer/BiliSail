import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/dynamic_management_repository.dart';
import '../domain/dynamic_repository.dart';
import 'dynamic_actions_controller.dart';
import 'dynamic_content_state.dart';

final dynamicManagementProvider = NotifierProvider.autoDispose
    .family<DynamicManagementController, DynamicManagementState, String>(
      DynamicManagementController.new,
    );

final class DynamicManagementState {
  const DynamicManagementState({
    this.busy = false,
    this.message,
    this.interaction,
    this.publicVisible,
  });
  final bool busy;
  final String? message;
  final DynamicInteractionSettings? interaction;
  final bool? publicVisible;
}

class DynamicManagementController extends Notifier<DynamicManagementState> {
  DynamicManagementController(this.id);
  final String id;
  int _generation = 0;
  RequestCancellation? _request;
  String? _scope;
  int? _epoch;
  bool _valid(RequestCancellation? request) {
    if (!ref.mounted) return false;
    final repo = ref.read(dynamicRepositoryProvider);
    return request != null &&
        identical(request, _request) &&
        !request.isCancelled &&
        repo?.accountScope == _scope &&
        repo?.sessionEpoch == _epoch;
  }

  @override
  DynamicManagementState build() {
    final repo = ref.watch(dynamicRepositoryProvider);
    if (repo != null) {
      ref.watch(
        authControllerProvider.select(
          (a) => (a.status, a.mid, repo.sessionEpoch),
        ),
      );
    }
    _generation++;
    _request?.cancel();
    ref.onDispose(() {
      _generation++;
      _request?.cancel();
    });
    return const DynamicManagementState();
  }

  bool owns(DynamicPost post) =>
      post.id == id &&
      !post.unavailable &&
      ref.read(authControllerProvider).isSignedIn &&
      post.authorId?.value == ref.read(authControllerProvider).mid;
  Future<bool> _run(
    String action,
    Future<void> Function(
      DynamicRepository,
      DynamicManagementRepository,
      RequestCancellation,
    )
    work, {
    bool write = true,
  }) async {
    if (state.busy ||
        (write &&
            (!ref.read(authControllerProvider).isSignedIn ||
                ref.read(dynamicContentProvider).locked[id]?.contains(action) ==
                    true))) {
      return false;
    }
    final repo = ref.read(dynamicRepositoryProvider);
    if (repo is! DynamicManagementRepository) {
      state = const DynamicManagementState(message: '动态管理服务暂不可用');
      return false;
    }
    if (write &&
        repo!.accountScope != 'user:${ref.read(authControllerProvider).mid}') {
      return false;
    }
    final generation = ++_generation,
        scope = repo!.accountScope,
        epoch = repo.sessionEpoch;
    _scope = scope;
    _epoch = epoch;
    _request?.cancel();
    final request = _request = RequestCancellation();
    state = DynamicManagementState(
      busy: true,
      interaction: state.interaction,
      publicVisible: state.publicVisible,
    );
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        !request.isCancelled &&
        repo.accountScope == scope &&
        repo.sessionEpoch == epoch;
    try {
      await work(repo, repo as DynamicManagementRepository, request);
      if (!current()) return false;
      state = DynamicManagementState(
        interaction: state.interaction,
        publicVisible: state.publicVisible,
      );
      return true;
    } catch (e) {
      if (!current()) return false;
      if (write && e is DynamicWriteUncertain) {
        ref.read(dynamicContentProvider.notifier).lock(id, action);
      }
      state = DynamicManagementState(
        interaction: state.interaction,
        publicVisible: state.publicVisible,
        message: e is DynamicWriteUncertain
            ? '操作结果未确认，请核对后再操作，未自动重试。'
            : e is AppFailure
            ? e.kind == AppFailureKind.cancelled
                  ? null
                  : e.message
            : '动态操作失败，请重试',
      );
      return false;
    }
  }

  Future<bool> refresh() => _run('read', (repo, _, c) async {
    final post = await repo.detail(id, c);
    if (post.id != id) {
      throw const AppFailure(AppFailureKind.protocol, '动态身份不匹配');
    }
    if (_valid(c)) {
      ref.read(dynamicContentProvider.notifier).update(post);
      ref.read(dynamicContentProvider.notifier).unlock(id, {
        'pin',
        'visibility',
        'edit',
      });
    }
  }, write: false);
  Future<bool> remove(DynamicPost post) async {
    if (!owns(post)) return false;
    final ok = await _run('remove', (_, m, c) => m.remove(id, c));
    if (ok && _valid(_request)) {
      ref.read(dynamicContentProvider.notifier).remove(id);
    }
    return ok;
  }

  Future<bool> pin(DynamicPost post) async {
    if (!owns(post)) return false;
    final ok = await _run('pin', (_, m, c) => m.pin(id, !post.pinned, c));
    if (ok && _valid(_request)) {
      final content = ref.read(dynamicContentProvider.notifier);
      if (!post.pinned) {
        for (final old
            in ref.read(dynamicContentProvider).posts.values.toList()) {
          if (old.authorId == post.authorId && old.pinned) {
            content.update(old.withManagement(pinned: false));
          }
        }
      }
      content.update(post.withManagement(pinned: !post.pinned));
    }
    return ok;
  }

  Future<bool> visibility(DynamicPost post, bool onlySelf) async {
    if (!owns(post) || onlySelf == post.onlySelf) return false;
    final ok = await _run(
      'visibility',
      (_, m, c) => m.visibility(id, onlySelf, c),
    );
    if (ok && _valid(_request)) {
      ref
          .read(dynamicContentProvider.notifier)
          .update(post.withManagement(onlySelf: onlySelf));
    }
    return ok;
  }

  Future<bool> loadInteraction(DynamicPost post) {
    if (!owns(post) || post.commentTarget == null) return Future.value(false);
    return _run('read', (_, m, c) async {
      final s = await m.interaction(post.commentTarget!, c);
      if (_valid(c)) {
        state = DynamicManagementState(busy: true, interaction: s);
        ref.read(dynamicContentProvider.notifier).unlock(id, {'interaction'});
      }
    }, write: false);
  }

  Future<bool> setInteraction(DynamicPost post, int action) async {
    final s = state.interaction;
    if (!owns(post) ||
        post.commentTarget == null ||
        s == null ||
        (action <= 2 ? !s.canSelect : !s.canComment) ||
        action < 1 ||
        action > 4) {
      return false;
    }
    final ok = await _run(
      'interaction',
      (_, m, c) => m.setInteraction(post.commentTarget!, action, c),
    );
    if (ok && _valid(_request)) {
      ref
          .read(dynamicContentProvider.notifier)
          .update(
            post.withManagement(
              commentForbidden: action == 3
                  ? true
                  : action == 4
                  ? false
                  : null,
            ),
          );
      await loadInteraction(post);
    }
    return ok;
  }

  Future<bool> report(DynamicPost post, int reason, String description) async {
    if (post.id != id || post.authorId == null || owns(post)) return false;
    final ok = await _run(
      'report',
      (_, m, c) => m.report(id, post.authorId!, reason, description, c),
    );
    if (ok && _valid(_request)) {
      ref.read(dynamicContentProvider.notifier).lock(id, 'report');
    }
    return ok;
  }

  Future<bool> checkPublic(DynamicPost post) {
    if (!owns(post)) return Future.value(false);
    return _run('read', (_, m, c) async {
      final visible = await m.publicVisible(id, c);
      if (_valid(c)) {
        state = DynamicManagementState(busy: true, publicVisible: visible);
      }
    }, write: false);
  }

  Future<DynamicEditDraft?> editDraft(DynamicPost post) async {
    if (!owns(post) ||
        !post.editable ||
        ref.read(dynamicContentProvider).locked[id]?.contains('edit') == true) {
      return null;
    }
    DynamicEditDraft? result;
    final ok = await _run('read', (_, m, c) async {
      final d = await m.editDraft(id, c);
      if (!_valid(c)) return;
      if (d.id != id || d.authorId != ref.read(authControllerProvider).mid) {
        throw const AppFailure(AppFailureKind.permission, '当前账号不能编辑该动态');
      }
      result = d;
    }, write: false);
    return ok ? result : null;
  }

  Future<bool> shareMessage(DynamicPost post, UserId receiver) => _run(
    'share:${receiver.value}',
    (_, m, c) => m.shareMessage(post, receiver, c),
  );
}
