import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../auth/application/auth_controller.dart';
import '../../video/application/watch_later_queue_registry.dart';
import '../../video/domain/watch_later_queue.dart';
import '../domain/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => throw UnimplementedError('ProfileRepository'),
);
final profileControllerProvider = NotifierProvider.autoDispose
    .family<ProfileController, ProfileState, UserId>(ProfileController.new);

final class ProfileListState {
  const ProfileListState({
    this.items = const [],
    this.videoPages = const {},
    this.page = 0,
    this.pagesWithoutNewItems = 0,
    this.cursor,
    this.loading = false,
    this.hasMore = true,
    this.isHidden = false,
    this.message,
  });
  final List<ProfileEntry> items;
  final Map<VideoId, int> videoPages;
  final int page, pagesWithoutNewItems;
  final String? cursor, message;
  final bool loading, hasMore, isHidden;
}

final class ProfileState {
  const ProfileState({
    this.sessionGeneration = 0,
    this.profile,
    this.profileLoading = false,
    this.profileMessage,
    this.liveRoom,
    this.liveRoomMessage,
    this.section = ProfileSection.videos,
    this.lists = const {},
    this.order = 'pubdate',
    this.keyword = '',
    this.folderId,
    this.folderTitle,
    this.queueLoading = false,
    this.queueMessage,
  });
  final UserProfile? profile;

  /// Retained presentation state must be discarded when account state resets.
  final int sessionGeneration;
  final ProfileLiveRoom? liveRoom;
  final String? liveRoomMessage;
  final bool profileLoading;
  final String? profileMessage, folderId, folderTitle;
  final ProfileSection section;
  final Map<ProfileSection, ProfileListState> lists;
  final String order, keyword;
  final bool queueLoading;
  final String? queueMessage;
  ProfileListState get current => lists[section] ?? const ProfileListState();
  ProfileState copy({
    UserProfile? profile,
    bool? profileLoading,
    String? profileMessage,
    bool clearProfileMessage = false,
    ProfileLiveRoom? liveRoom,
    String? liveRoomMessage,
    bool clearLiveRoom = false,
    bool clearLiveRoomMessage = false,
    ProfileSection? section,
    Map<ProfileSection, ProfileListState>? lists,
    String? order,
    String? keyword,
    String? folderId,
    String? folderTitle,
    bool closeFolder = false,
    bool? queueLoading,
    String? queueMessage,
    bool clearQueueMessage = false,
  }) => ProfileState(
    sessionGeneration: sessionGeneration,
    profile: profile ?? this.profile,
    profileLoading: profileLoading ?? this.profileLoading,
    profileMessage: clearProfileMessage
        ? null
        : profileMessage ?? this.profileMessage,
    liveRoom: clearLiveRoom ? null : liveRoom ?? this.liveRoom,
    liveRoomMessage: clearLiveRoomMessage
        ? null
        : liveRoomMessage ?? this.liveRoomMessage,
    section: section ?? this.section,
    lists: lists ?? this.lists,
    order: order ?? this.order,
    keyword: keyword ?? this.keyword,
    folderId: closeFolder ? null : folderId ?? this.folderId,
    folderTitle: closeFolder ? null : folderTitle ?? this.folderTitle,
    queueLoading: queueLoading ?? this.queueLoading,
    queueMessage: clearQueueMessage ? null : queueMessage ?? this.queueMessage,
  );
}

class ProfileController extends Notifier<ProfileState> {
  ProfileController(this.id);
  final UserId id;
  int _generation = 0, _profileGeneration = 0;
  int _liveRoomGeneration = 0;
  RequestCancellation _profileRead = RequestCancellation();
  RequestCancellation _liveRoomRead = RequestCancellation();
  RequestCancellation _queueRead = RequestCancellation();
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
        loadLiveRoom();
        load();
      }
    });
    return ProfileState(sessionGeneration: generation);
  }

  void _cancel() {
    _profileRead.cancel();
    _liveRoomRead.cancel();
    _queueRead.cancel();
    for (final read in _reads.values) {
      read.cancel();
    }
    _reads.clear();
    _versions.clear();
    ++_profileGeneration;
    ++_liveRoomGeneration;
  }

  bool _current(int generation, String scope, int epoch) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(profileRepositoryProvider).accountScope == scope &&
      ref.read(profileRepositoryProvider).sessionEpoch == epoch;

  Future<WatchLaterQueue?> captureFavoriteQueue({VideoId? initial}) {
    final folderId = state.folderId;
    final list = state.lists[ProfileSection.folders];
    final page = initial == null ? 1 : list?.videoPages[initial];
    if (state.section != ProfileSection.folders ||
        folderId == null ||
        list == null ||
        list.page == 0 ||
        list.isHidden ||
        page == null) {
      return Future.value();
    }
    return _captureQueue(page: page, folderId: folderId, initial: initial);
  }

  Future<WatchLaterQueue?> playAll() => _captureQueue(page: 1);

  Future<WatchLaterQueue?> _captureQueue({
    required int page,
    String? folderId,
    VideoId? initial,
  }) async {
    if (state.queueLoading) return null;
    final repository = ref.read(profileRepositoryProvider);
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    final generation = _generation;
    final order = state.order;
    final name = state.profile?.name ?? 'UP主';
    final title = folderId == null ? null : state.folderTitle ?? '收藏夹';
    _queueRead.cancel();
    final read = _queueRead = RequestCancellation();
    bool current() =>
        _current(generation, scope, epoch) &&
        identical(_queueRead, read) &&
        (folderId == null || state.folderId == folderId);
    state = state.copy(queueLoading: true, clearQueueMessage: true);
    try {
      final result = await repository
          .loadEntries(
            id,
            folderId == null ? ProfileSection.videos : ProfileSection.folders,
            page: page,
            order: order,
            folderId: folderId,
            cancellation: read,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              read.cancel();
              throw const AppFailure(AppFailureKind.timeout, '播放列表加载超时，请重试');
            },
          );
      if (!current() || read.isCancelled) return null;
      final items = profileQueueItems(result.items);
      if (items.isEmpty) {
        throw AppFailure(
          AppFailureKind.notFound,
          folderId == null ? '暂无可播放的公开投稿' : '当前收藏页暂无可播放的视频',
        );
      }
      final selected = initial == null
          ? 0
          : items.indexWhere((item) => item.video.id == initial);
      if (selected < 0) {
        throw const AppFailure(AppFailureKind.notFound, '该视频已不在当前收藏页，请刷新后重试');
      }
      final start = items.length > WatchLaterQueue.maximumInitialProfileItems
          ? (selected - 49).clamp(
              0,
              items.length - WatchLaterQueue.maximumInitialProfileItems,
            )
          : 0;
      final queue = ref
          .read(watchLaterQueueRegistryProvider)
          .capture(
            scope: scope,
            sessionEpoch: epoch,
            items: items
                .skip(start)
                .take(WatchLaterQueue.maximumInitialProfileItems)
                .toList(),
            current: initial ?? items.first.video.id,
            profileSource: ProfileVideoQueueSource(
              userId: id,
              name: name,
              order: order,
              folderId: folderId,
            ),
            favoriteTitle: title,
            hasMore: result.hasMore,
            nextPage: page + 1,
            truncated:
                items.length > WatchLaterQueue.maximumInitialProfileItems,
          );
      state = state.copy(queueLoading: false);
      return queue;
    } on AppFailure catch (error) {
      if (current()) {
        state = state.copy(
          queueLoading: false,
          queueMessage: error.kind == AppFailureKind.cancelled
              ? null
              : error.message,
        );
      }
    } catch (_) {
      if (current()) {
        state = state.copy(queueLoading: false, queueMessage: '播放列表暂时无法加载，请重试');
      }
    } finally {
      read.cancel();
      if (ref.mounted && identical(_queueRead, read) && state.queueLoading) {
        state = state.copy(queueLoading: false);
      }
    }
    return null;
  }

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
    await Future.wait([loadProfile(), loadLiveRoom(), load(refresh: true)]);
  }

  Future<void> loadLiveRoom() async {
    _liveRoomRead.cancel();
    _liveRoomRead = RequestCancellation();
    final version = ++_liveRoomGeneration, generation = _generation;
    final repository = ref.read(profileRepositoryProvider);
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    state = state.copy(clearLiveRoomMessage: true);
    try {
      final room = await repository.loadLiveRoom(
        id,
        cancellation: _liveRoomRead,
      );
      if (_current(generation, scope, epoch) &&
          version == _liveRoomGeneration) {
        state = state.copy(liveRoom: room, clearLiveRoom: room == null);
      }
    } on AppFailure catch (error) {
      if (_current(generation, scope, epoch) &&
          version == _liveRoomGeneration) {
        state = state.copy(
          liveRoomMessage: error.kind == AppFailureKind.cancelled
              ? null
              : error.message,
        );
      }
    } catch (_) {
      if (_current(generation, scope, epoch) &&
          version == _liveRoomGeneration) {
        state = state.copy(liveRoomMessage: '直播间信息暂时无法加载，请重试');
      }
    }
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
    final previousEmptyPages = base.message == null
        ? base.pagesWithoutNewItems
        : 0;
    _setList(
      section,
      ProfileListState(
        items: base.items,
        videoPages: base.videoPages,
        page: base.page,
        pagesWithoutNewItems: previousEmptyPages,
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
      final videoPages = {...base.videoPages};
      for (final entry in result.items) {
        if (entry.video case final video?) {
          videoPages.putIfAbsent(video.id, () => page);
        }
      }
      final cursorAdvanced =
          section != ProfileSection.dynamics ||
          (result.cursor != null && result.cursor != base.cursor);
      final hasMore = result.hasMore && cursorAdvanced && unique.length < 500;
      final emptyPages = bounded.length == base.items.length
          ? previousEmptyPages + 1
          : 0;
      _setList(
        section,
        ProfileListState(
          items: List.unmodifiable(bounded),
          videoPages: Map.unmodifiable({
            for (final entry in bounded)
              if (entry.video case final video?)
                video.id: videoPages[video.id] ?? page,
          }),
          page: page,
          pagesWithoutNewItems: emptyPages,
          cursor: result.cursor,
          hasMore: hasMore,
          // Automatic viewport filling must stop on repeated/filtered pages.
          // Keep the server cursor so an explicit retry can continue.
          message: hasMore && emptyPages >= 3 ? '连续多页没有新内容，可重试继续加载' : null,
        ),
      );
    } on AppFailure catch (error) {
      if (_current(generation, scope, epoch) && _versions[section] == version) {
        _setList(
          section,
          ProfileListState(
            items: base.items,
            videoPages: base.videoPages,
            page: base.page,
            pagesWithoutNewItems: previousEmptyPages,
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
            videoPages: base.videoPages,
            page: base.page,
            pagesWithoutNewItems: previousEmptyPages,
            cursor: base.cursor,
            hasMore: base.hasMore,
            message: '内容暂时无法加载，请重试',
          ),
        );
      }
    }
  }
}

List<WatchLaterQueueItem> profileQueueItems(List<ProfileEntry> entries) => [
  ...{
    for (final entry in entries)
      if (entry.video case final video? when video.id.isValid)
        video.id: WatchLaterQueueItem(video: video),
  }.values,
];
