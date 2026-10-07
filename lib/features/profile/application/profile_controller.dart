import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => throw UnimplementedError('ProfileRepository'),
);
final profileControllerProvider = NotifierProvider.autoDispose
    .family<ProfileController, ProfileState, UserId>(ProfileController.new);

final class ProfileListState {
  const ProfileListState({
    this.items = const [],
    this.page = 0,
    this.cursor,
    this.loading = false,
    this.hasMore = true,
    this.isHidden = false,
    this.message,
  });
  final List<ProfileEntry> items;
  final int page;
  final String? cursor, message;
  final bool loading, hasMore, isHidden;
}

final class ProfileState {
  const ProfileState({
    this.profile,
    this.profileLoading = false,
    this.profileMessage,
    this.section = ProfileSection.videos,
    this.lists = const {},
    this.order = 'pubdate',
    this.keyword = '',
    this.folderId,
    this.folderTitle,
  });
  final UserProfile? profile;
  final bool profileLoading;
  final String? profileMessage, folderId, folderTitle;
  final ProfileSection section;
  final Map<ProfileSection, ProfileListState> lists;
  final String order, keyword;
  ProfileListState get current => lists[section] ?? const ProfileListState();
  ProfileState copy({
    UserProfile? profile,
    bool? profileLoading,
    String? profileMessage,
    bool clearProfileMessage = false,
    ProfileSection? section,
    Map<ProfileSection, ProfileListState>? lists,
    String? order,
    String? keyword,
    String? folderId,
    String? folderTitle,
    bool closeFolder = false,
  }) => ProfileState(
    profile: profile ?? this.profile,
    profileLoading: profileLoading ?? this.profileLoading,
    profileMessage: clearProfileMessage
        ? null
        : profileMessage ?? this.profileMessage,
    section: section ?? this.section,
    lists: lists ?? this.lists,
    order: order ?? this.order,
    keyword: keyword ?? this.keyword,
    folderId: closeFolder ? null : folderId ?? this.folderId,
    folderTitle: closeFolder ? null : folderTitle ?? this.folderTitle,
  );
}

class ProfileController extends Notifier<ProfileState> {
  ProfileController(this.id);
  final UserId id;
  int _generation = 0, _profileGeneration = 0;
  RequestCancellation _profileRead = RequestCancellation();
  final Map<ProfileSection, RequestCancellation> _reads = {};
  final Map<ProfileSection, int> _versions = {};
  @override
  ProfileState build() {
    ref.watch(authControllerProvider);
    _cancel();
    final generation = ++_generation;
    ref.onDispose(() {
      ++_generation;
      _cancel();
    });
    Future<void>.microtask(() {
      if (ref.mounted && generation == _generation) {
        loadProfile();
        load();
      }
    });
    return const ProfileState();
  }

  void _cancel() {
    _profileRead.cancel();
    for (final read in _reads.values) {
      read.cancel();
    }
    _reads.clear();
    _versions.clear();
    ++_profileGeneration;
  }

  bool _current(int generation, String scope, int epoch) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(profileRepositoryProvider).accountScope == scope &&
      ref.read(profileRepositoryProvider).sessionEpoch == epoch;
  Future<void> loadProfile() async {
    _profileRead.cancel();
    _profileRead = RequestCancellation();
    final version = ++_profileGeneration, generation = _generation;
    final repository = ref.read(profileRepositoryProvider),
        scope = ref.read(profileRepositoryProvider).accountScope;
    final epoch = repository.sessionEpoch;
    state = state.copy(profileLoading: true, clearProfileMessage: true);
    try {
      final profile = await repository.loadProfile(
        id,
        cancellation: _profileRead,
      );
      if (_current(generation, scope, epoch) && version == _profileGeneration) {
        state = state.copy(profile: profile, profileLoading: false);
      }
    } on AppFailure catch (error) {
      if (_current(generation, scope, epoch) && version == _profileGeneration) {
        state = state.copy(
          profileLoading: false,
          profileMessage: error.kind == AppFailureKind.cancelled
              ? null
              : error.message,
        );
      }
    } catch (_) {
      if (_current(generation, scope, epoch) && version == _profileGeneration) {
        state = state.copy(
          profileLoading: false,
          profileMessage: '用户资料暂时无法加载，请重试',
        );
      }
    }
  }

  void select(ProfileSection section) {
    if (section == state.section) return;
    state = state.copy(section: section);
    if (!state.lists.containsKey(section)) load();
  }

  void filter({String? order, String? keyword}) {
    state = state.copy(order: order, keyword: keyword?.trim());
    load(refresh: true);
  }

  void openFolder(ProfileEntry entry) {
    state = state.copy(
      folderId: entry.id,
      folderTitle: entry.title,
      section: ProfileSection.folders,
    );
    load(refresh: true);
  }

  void closeFolder() {
    state = state.copy(closeFolder: true);
    load(refresh: true);
  }

  Future<void> refresh() async {
    await Future.wait([loadProfile(), load(refresh: true)]);
  }

  void _setList(ProfileSection section, ProfileListState list) {
    state = state.copy(
      lists: Map.unmodifiable({...state.lists, section: list}),
    );
  }

  Future<void> load({bool refresh = false}) async {
    final section = state.section, old = state.current;
    if (!refresh && (old.loading || !old.hasMore)) return;
    _reads[section]?.cancel();
    final read = RequestCancellation();
    _reads[section] = read;
    final version = (_versions[section] ?? 0) + 1;
    _versions[section] = version;
    final generation = _generation,
        repository = ref.read(profileRepositoryProvider);
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    final base = refresh ? const ProfileListState() : old;
    final page = base.page + 1;
    _setList(
      section,
      ProfileListState(
        items: base.items,
        page: base.page,
        cursor: base.cursor,
        loading: true,
        hasMore: base.hasMore,
      ),
    );
    try {
      final result = await repository.loadEntries(
        id,
        section,
        page: page,
        cursor: base.cursor,
        order: state.order,
        keyword: state.keyword,
        folderId: state.folderId,
        cancellation: read,
      );
      if (!_current(generation, scope, epoch) ||
          _versions[section] != version) {
        return;
      }
      if (result.isHidden) {
        _setList(
          section,
          const ProfileListState(hasMore: false, isHidden: true),
        );
        return;
      }
      final unique = <String, ProfileEntry>{
        for (final entry in base.items) entry.id: entry,
      };
      for (final entry in result.items) {
        unique.putIfAbsent(entry.id, () => entry);
      }
      final bounded = unique.values.take(500).toList(growable: false);
      final cursorAdvanced =
          section != ProfileSection.dynamics ||
          (result.cursor != null && result.cursor != base.cursor);
      _setList(
        section,
        ProfileListState(
          items: List.unmodifiable(bounded),
          page: page,
          cursor: result.cursor,
          hasMore: result.hasMore && cursorAdvanced && unique.length < 500,
        ),
      );
    } on AppFailure catch (error) {
      if (_current(generation, scope, epoch) && _versions[section] == version) {
        _setList(
          section,
          ProfileListState(
            items: base.items,
            page: base.page,
            cursor: base.cursor,
            hasMore: base.hasMore,
            message: error.kind == AppFailureKind.cancelled
                ? null
                : error.message,
          ),
        );
      }
    } catch (_) {
      if (_current(generation, scope, epoch) && _versions[section] == version) {
        _setList(
          section,
          ProfileListState(
            items: base.items,
            page: base.page,
            cursor: base.cursor,
            hasMore: base.hasMore,
            message: '内容暂时无法加载，请重试',
          ),
        );
      }
    }
  }
}
