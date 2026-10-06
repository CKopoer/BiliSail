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
    this.authorAccountScope,
    this.authorSessionEpoch,
    this.signedIn = false,
    this.isSelf = false,
    this.loading = false,
    this.busy = false,
    this.uncertain = false,
    this.message,
    this.groups,
    this.selectedGroupIds = const {},
    this.savedGroupIds = const {},
    this.groupsLoading = false,
    this.groupsBusy = false,
    this.groupsUncertain = false,
    this.groupsMessage,
  });
  final VideoAuthor? author;
  final String? authorAccountScope;
  final int? authorSessionEpoch;
  final bool signedIn, isSelf, loading, busy, uncertain;
  final String? message;
  final List<FollowGroup>? groups;
  final Set<String> selectedGroupIds, savedGroupIds;
  final bool groupsLoading, groupsBusy, groupsUncertain;
  final String? groupsMessage;

  VideoAuthorState copyWith({
    VideoAuthor? author,
    String? authorAccountScope,
    int? authorSessionEpoch,
    bool? loading,
    bool? busy,
    bool? uncertain,
    String? message,
    List<FollowGroup>? groups,
    Set<String>? selectedGroupIds,
    Set<String>? savedGroupIds,
    bool? groupsLoading,
    bool? groupsBusy,
    bool? groupsUncertain,
    String? groupsMessage,
    bool clearGroups = false,
  }) => VideoAuthorState(
    author: author ?? this.author,
    authorAccountScope: authorAccountScope ?? this.authorAccountScope,
    authorSessionEpoch: authorSessionEpoch ?? this.authorSessionEpoch,
    signedIn: signedIn,
    isSelf: isSelf,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    uncertain: uncertain ?? this.uncertain,
    message: message,
    groups: clearGroups ? null : groups ?? this.groups,
    selectedGroupIds: selectedGroupIds ?? this.selectedGroupIds,
    savedGroupIds: savedGroupIds ?? this.savedGroupIds,
    groupsLoading: groupsLoading ?? this.groupsLoading,
    groupsBusy: groupsBusy ?? this.groupsBusy,
    groupsUncertain: groupsUncertain ?? this.groupsUncertain,
    groupsMessage: groupsMessage,
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

  bool _authorCurrent(VideoAuthorRepository repo) {
    if (state.authorAccountScope == repo.accountScope &&
        state.authorSessionEpoch == repo.sessionEpoch) {
      return true;
    }
    ref.invalidateSelf();
    return false;
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
      state = state.copyWith(
        author: author,
        authorAccountScope: scope,
        authorSessionEpoch: epoch,
        loading: false,
        uncertain: false,
      );
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
        state.groupsLoading ||
        state.groupsBusy ||
        state.uncertain) {
      return;
    }
    final repo = ref.read(videoAuthorRepositoryProvider);
    if (!_authorCurrent(repo)) return;
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

  Future<void> loadGroups() async {
    if (!state.signedIn ||
        state.isSelf ||
        state.author?.following != true ||
        state.busy ||
        state.groupsLoading ||
        state.groupsBusy) {
      return;
    }
    final repo = ref.read(videoAuthorRepositoryProvider);
    if (!_authorCurrent(repo)) return;
    final scope = repo.accountScope;
    final epoch = repo.sessionEpoch;
    final generation = ++_generation;
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    state = state.copyWith(
      groupsLoading: true,
      groupsMessage: null,
      clearGroups: true,
    );
    try {
      final selection = await repo.loadGroups(id, _cancellation);
      if (!_current(generation, scope, epoch)) return;
      final groups = <FollowGroup>[
        if (!selection.groups.any((group) => group.id == '0'))
          const FollowGroup(id: '0', name: '默认分组'),
        ...selection.groups,
      ];
      final selected = {...selection.selectedIds};
      // Default is the server fallback, not an additional custom group.
      if (selected.any(_isCustomGroup)) {
        selected.remove('0');
      } else {
        selected.add('0');
      }
      state = state.copyWith(
        groups: List.unmodifiable(groups),
        selectedGroupIds: Set.unmodifiable(selected),
        savedGroupIds: Set.unmodifiable(selected),
        groupsLoading: false,
        groupsUncertain: false,
      );
    } catch (error) {
      if (!_current(generation, scope, epoch)) return;
      state = state.copyWith(
        groupsLoading: false,
        groupsMessage: _message(error),
      );
    }
  }

  void selectGroup(String groupId, bool selected) {
    if (state.groupsLoading ||
        state.groupsBusy ||
        state.groupsUncertain ||
        state.groups?.any((group) => group.id == groupId) != true) {
      return;
    }
    final next = {...state.selectedGroupIds};
    if (groupId == '0' && selected) {
      next.removeWhere(_isCustomGroup);
      next.add('0');
    } else if (groupId == '0') {
      // The API represents an empty custom selection with tagids=0.
      return;
    } else if (selected) {
      next.remove('0');
      next.add(groupId);
    } else {
      next.remove(groupId);
      if (!next.any(_isCustomGroup)) next.add('0');
    }
    state = state.copyWith(selectedGroupIds: Set.unmodifiable(next));
  }

  Future<bool> saveGroups() async {
    if (!state.signedIn ||
        state.isSelf ||
        state.author?.following != true ||
        state.groups == null ||
        state.groupsLoading ||
        state.groupsBusy ||
        state.groupsUncertain ||
        state.busy) {
      return false;
    }
    final repo = ref.read(videoAuthorRepositoryProvider);
    if (!_authorCurrent(repo)) return false;
    final selected = Set<String>.of(state.selectedGroupIds);
    if (selected.any(_isCustomGroup)) {
      selected.remove('0');
    } else {
      selected.add('0');
    }
    if (selected.length == state.savedGroupIds.length &&
        selected.containsAll(state.savedGroupIds)) {
      return true;
    }
    final scope = repo.accountScope;
    final epoch = repo.sessionEpoch;
    final generation = ++_generation;
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    state = state.copyWith(groupsBusy: true);
    try {
      await repo.saveGroups(id, selected, _cancellation);
      if (!_current(generation, scope, epoch)) return false;
      state = state.copyWith(
        savedGroupIds: Set.unmodifiable(selected),
        groupsBusy: false,
      );
      return true;
    } catch (error) {
      if (!_current(generation, scope, epoch)) return false;
      state = state.copyWith(
        groupsBusy: false,
        groupsUncertain: error is UnknownWriteOutcome,
        groupsMessage: error is UnknownWriteOutcome
            ? '分组结果暂时无法确认，请刷新状态后再操作'
            : _message(error),
      );
      return false;
    }
  }

  static String? _message(Object error) => error is AppFailure
      ? (error.kind == AppFailureKind.cancelled ? null : error.message)
      : 'UP 主信息加载或操作失败，请重试';

  static bool _isCustomGroup(String id) => id != '0' && !id.startsWith('-');
}
