import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/live_danmaku_repository.dart';
import '../domain/live_room.dart';
import 'live_controller.dart';

final liveDanmakuRepositoryProvider = Provider<LiveDanmakuRepository>(
  (ref) =>
      throw UnimplementedError('LiveDanmakuRepository must be provided by app'),
);
final liveDanmakuControllerProvider = NotifierProvider.autoDispose
    .family<LiveDanmakuController, LiveDanmakuState, RoomId>(
      LiveDanmakuController.new,
      dependencies: [liveControllerProvider],
    );

final class LiveDanmakuState {
  LiveDanmakuState({
    this.signedIn = false,
    this.canSend = false,
    this.busy = false,
    this.uncertain = false,
    this.draft = '',
    this.selected,
    List<LiveEmoticonPackage> packages = const [],
    this.emoticonsLoading = false,
    this.emoticonsLoaded = false,
    this.emoticonsMessage,
    this.message,
  }) : packages = List.unmodifiable(packages);
  final bool signedIn, canSend, busy, uncertain;
  final bool emoticonsLoading, emoticonsLoaded;
  final String draft;
  final LiveEmoticon? selected;
  final List<LiveEmoticonPackage> packages;
  final String? emoticonsMessage, message;

  LiveDanmakuState copyWith({
    bool? busy,
    bool? uncertain,
    String? draft,
    LiveEmoticon? selected,
    bool clearSelected = false,
    List<LiveEmoticonPackage>? packages,
    bool? emoticonsLoading,
    bool? emoticonsLoaded,
    String? emoticonsMessage,
    bool clearEmoticonsMessage = false,
    String? message,
    bool clearMessage = false,
  }) => LiveDanmakuState(
    signedIn: signedIn,
    canSend: canSend,
    busy: busy ?? this.busy,
    uncertain: uncertain ?? this.uncertain,
    draft: draft ?? this.draft,
    selected: clearSelected ? null : selected ?? this.selected,
    packages: packages ?? this.packages,
    emoticonsLoading: emoticonsLoading ?? this.emoticonsLoading,
    emoticonsLoaded: emoticonsLoaded ?? this.emoticonsLoaded,
    emoticonsMessage: clearEmoticonsMessage
        ? null
        : emoticonsMessage ?? this.emoticonsMessage,
    message: clearMessage ? null : message ?? this.message,
  );
}

/// Both composers share one draft, one pending write and one account/room epoch.
final class LiveDanmakuController extends Notifier<LiveDanmakuState> {
  LiveDanmakuController(this.requestedId);
  final RoomId requestedId;
  RequestCancellation? _write, _read;
  int _revision = 0;

  @override
  LiveDanmakuState build() {
    final auth = ref.watch(authControllerProvider);
    final room = ref.watch(
      liveControllerProvider(requestedId)
          .select((state) => (state.room?.id, state.room?.isLive ?? false)),
    );
    _write?.cancel();
    _read?.cancel();
    ++_revision;
    ref.onDispose(() {
      ++_revision;
      _write?.cancel();
      _read?.cancel();
    });
    return LiveDanmakuState(
      signedIn: auth.isSignedIn,
      canSend: room.$1?.isValid == true && room.$2,
    );
  }

  void setDraft(String value) {
    if (state.busy || value.runes.length > 100) return;
    state = state.copyWith(
      draft: value,
      clearSelected: true,
      clearMessage: true,
    );
  }

  void chooseEmoticon(LiveEmoticon item) {
    if (state.busy ||
        !item.allowed ||
        !state.packages.any((package) => package.items.contains(item))) {
      return;
    }
    if (item.isSticker) {
      state = state.copyWith(
        draft: item.text,
        selected: item,
        clearMessage: true,
      );
    } else {
      setDraft('${state.draft}${item.text}');
    }
  }

  void acknowledgeUncertain() {
    if (!state.busy) {
      state = state.copyWith(uncertain: false, clearMessage: true);
    }
  }

  Future<void> loadEmoticons() async {
    if (!state.signedIn || state.emoticonsLoading || state.emoticonsLoaded) {
      return;
    }
    final room = ref.read(liveControllerProvider(requestedId)).room;
    if (room == null) return;
    final repository = ref.read(liveDanmakuRepositoryProvider);
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    final revision = _revision;
    final cancellation = RequestCancellation();
    _read = cancellation;
    bool current() =>
        ref.mounted &&
        revision == _revision &&
        !cancellation.isCancelled &&
        repository.accountScope == scope &&
        repository.sessionEpoch == epoch &&
        ref.read(liveControllerProvider(requestedId)).room?.id == room.id;
    state = state.copyWith(emoticonsLoading: true, clearEmoticonsMessage: true);
    try {
      final packages = await repository.loadEmoticons(
        room.id,
        cancellation: cancellation,
      );
      if (!current()) return;
      state = state.copyWith(
        packages: packages,
        emoticonsLoading: false,
        emoticonsLoaded: true,
      );
    } catch (error) {
      if (!current()) return;
      state = state.copyWith(
        emoticonsLoading: false,
        emoticonsMessage: error is AppFailure ? error.message : '表情包加载失败，请重试',
      );
    }
  }

  Future<bool> send() async {
    if (!state.signedIn || !state.canSend || state.busy || state.uncertain) {
      return false;
    }
    final text = state.draft.trim();
    if (text.isEmpty || text.runes.length > 100) return false;
    final room = ref.read(liveControllerProvider(requestedId)).room;
    if (room == null || !room.isLive) return false;
    final repository = ref.read(liveDanmakuRepositoryProvider);
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    final revision = _revision;
    final cancellation = RequestCancellation();
    _write = cancellation;
    final selected = state.selected;
    if (selected != null && !selected.allowed) return false;
    bool current() =>
        ref.mounted &&
        revision == _revision &&
        !cancellation.isCancelled &&
        repository.accountScope == scope &&
        repository.sessionEpoch == epoch &&
        ref.read(liveControllerProvider(requestedId)).room?.id == room.id &&
        ref.read(liveControllerProvider(requestedId)).room?.isLive == true;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      await repository.send(
        room.id,
        text,
        emoticonUnique: selected?.unique,
        cancellation: cancellation,
      );
      if (!current()) return false;
      state = state.copyWith(
        busy: false,
        draft: '',
        clearSelected: true,
        message: '弹幕已发送',
      );
      return true;
    } catch (error) {
      if (!current()) return false;
      if (error is AppFailure && error.kind == AppFailureKind.cancelled) {
        state = state.copyWith(busy: false);
        return false;
      }
      final uncertain = error is LiveDanmakuWriteUncertain;
      state = state.copyWith(
        busy: false,
        uncertain: uncertain,
        message: uncertain
            ? '发送结果暂时无法确认，请核对聊天记录后再发送'
            : error is AppFailure
            ? (error.kind == AppFailureKind.permission
                  ? '发送被拒绝，请检查禁言、弹幕长度或表情权限'
                  : error.message)
            : '弹幕发送失败，请稍后重试',
      );
      return false;
    }
  }
}
