import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/local_image.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/dynamic_composer_repository.dart';
import '../domain/dynamic_repository.dart';

final dynamicComposerRepositoryProvider = Provider<DynamicComposerRepository?>(
  (ref) => null,
);
final dynamicImagePickerProvider =
    Provider<Future<List<LocalImage>> Function(int)>(
      (ref) => throw UnimplementedError('Dynamic image picker'),
    );

// One bounded in-memory draft shared by all entry points, cleared on account changes.
final dynamicComposerProvider =
    NotifierProvider<DynamicComposerController, DynamicComposerState>(
      DynamicComposerController.new,
    );

final class DynamicComposerState {
  const DynamicComposerState({
    this.text = '',
    this.images = const [],
    this.topic,
    this.busy = false,
    this.uncertain = false,
    this.message,
    this.uploaded = 0,
    this.accountScope = 'guest',
    this.sessionEpoch = 0,
    this.mid,
  });
  final String text, accountScope;
  final String? mid, message;
  final List<LocalImage> images;
  final DynamicComposeTopic? topic;
  final bool busy, uncertain;
  final int uploaded, sessionEpoch;
  bool get canPublish =>
      mid != null &&
      !busy &&
      !uncertain &&
      text.runes.length <= 1000 &&
      (text.trim().isNotEmpty || images.isNotEmpty);
  DynamicComposerState copy({
    String? text,
    List<LocalImage>? images,
    DynamicComposeTopic? topic,
    bool clearTopic = false,
    bool? busy,
    bool? uncertain,
    String? message,
    int? uploaded,
  }) => DynamicComposerState(
    text: text ?? this.text,
    images: images ?? this.images,
    topic: clearTopic ? null : topic ?? this.topic,
    busy: busy ?? this.busy,
    uncertain: uncertain ?? this.uncertain,
    message: message,
    uploaded: uploaded ?? this.uploaded,
    accountScope: accountScope,
    sessionEpoch: sessionEpoch,
    mid: mid,
  );
}

class DynamicComposerController extends Notifier<DynamicComposerState> {
  RequestCancellation? _request;
  int _generation = 0;
  final _pictures = <LocalImage, DynamicPicture>{};
  @override
  DynamicComposerState build() {
    final repository = ref.watch(dynamicComposerRepositoryProvider);
    final account = ref.watch(
      authControllerProvider.select(
        (s) => (s.isSignedIn, s.mid, repository?.sessionEpoch ?? 0),
      ),
    );
    _request?.cancel();
    _pictures.clear();
    _generation++;
    ref.onDispose(() {
      _generation++;
      _request?.cancel();
      _pictures.clear();
    });
    return DynamicComposerState(
      accountScope: repository?.accountScope ?? 'guest',
      sessionEpoch: repository?.sessionEpoch ?? 0,
      mid: account.$1 ? account.$2 : null,
    );
  }

  bool isCurrent(String scope, int epoch) {
    if (!ref.mounted) return false;
    final repository = ref.read(dynamicComposerRepositoryProvider);
    return ref.mounted &&
        state.accountScope == scope &&
        state.sessionEpoch == epoch &&
        repository?.accountScope == scope &&
        repository?.sessionEpoch == epoch;
  }

  void setText(String text) {
    if (!state.busy) state = state.copy(text: text);
  }

  void setTopic(DynamicComposeTopic? topic) {
    if (!state.busy) {
      state = state.copy(topic: topic, clearTopic: topic == null);
    }
  }

  void addImages(List<LocalImage> images) {
    if (state.busy) return;
    if (images.any(
          (image) =>
              image.bytes.isEmpty ||
              image.bytes.length > LocalImage.maxBytes ||
              !const {
                'image/png',
                'image/jpeg',
                'image/gif',
              }.contains(image.mimeType),
        ) ||
        state.images.length + images.length > LocalImage.maxCount) {
      state = state.copy(message: '最多添加9张图片，每张不超过10 MB');
      return;
    }
    state = state.copy(images: List.unmodifiable([...state.images, ...images]));
  }

  void removeImage(LocalImage image) {
    if (state.busy) return;
    _pictures.remove(image);
    state = state.copy(
      images: List.unmodifiable(state.images.where((i) => i != image)),
    );
  }

  void clear() {
    if (state.busy || state.uncertain) return;
    _pictures.clear();
    state = state.copy(
      text: '',
      images: const [],
      clearTopic: true,
      uploaded: 0,
    );
  }

  void confirmNotPublished() {
    if (!state.busy) state = state.copy(uncertain: false);
  }

  Future<bool> publish() async {
    if (!state.canPublish) return false;
    final repository = ref.read(dynamicComposerRepositoryProvider);
    final mid = state.mid;
    if (repository == null ||
        mid == null ||
        !isCurrent(state.accountScope, state.sessionEpoch)) {
      return false;
    }
    final draft = state;
    final generation = ++_generation;
    final request = _request = RequestCancellation();
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        !request.isCancelled &&
        isCurrent(draft.accountScope, draft.sessionEpoch);
    state = state.copy(busy: true, uploaded: 0);
    try {
      final pictures = <DynamicPicture>[];
      for (final image in draft.images) {
        if (!current()) return false;
        final picture =
            _pictures[image] ?? await repository.upload(image, request);
        if (!current()) return false;
        _pictures[image] = picture;
        pictures.add(picture);
        state = state.copy(uploaded: pictures.length, busy: true);
      }
      if (!current()) return false;
      await repository.create(
        mid: mid,
        text: draft.text,
        pictures: pictures,
        topic: draft.topic,
        cancellation: request,
      );
      if (!current()) return false;
      state = state.copy(
        busy: false,
        text: '',
        images: const [],
        clearTopic: true,
        uploaded: 0,
      );
      _pictures.clear();
      return true;
    } catch (error) {
      if (!current()) return false;
      final uncertain = error is DynamicWriteUncertain;
      state = state.copy(
        busy: false,
        uncertain: uncertain,
        message: uncertain
            ? '发布结果暂时无法确认，请先查看自己的动态，确认未发布后再继续。'
            : error is AppFailure
            ? error.kind == AppFailureKind.cancelled
                  ? null
                  : error.message
            : '发布失败，草稿已保留，请稍后重试',
      );
      return false;
    } finally {
      if (current() && state.busy) {
        state = state.copy(busy: false, message: state.message);
      }
    }
  }
}

final dynamicComposeTopicsProvider =
    NotifierProvider.autoDispose<
      DynamicComposeTopicsController,
      AsyncValue<List<DynamicComposeTopic>>
    >(DynamicComposeTopicsController.new);

class DynamicComposeTopicsController
    extends Notifier<AsyncValue<List<DynamicComposeTopic>>> {
  RequestCancellation? _request;
  int _generation = 0;
  @override
  AsyncValue<List<DynamicComposeTopic>> build() {
    final repository = ref.watch(dynamicComposerRepositoryProvider);
    ref.watch(
      authControllerProvider.select(
        (s) => (s.status, s.mid, repository?.sessionEpoch ?? 0),
      ),
    );
    ref.onDispose(() {
      _generation++;
      _request?.cancel();
    });
    Future<void>.microtask(() => search(''));
    return const AsyncLoading();
  }

  Future<void> search(String keyword) async {
    if (!ref.mounted) return;
    final repository = ref.read(dynamicComposerRepositoryProvider);
    if (repository == null) {
      state = AsyncError(
        const AppFailure(AppFailureKind.unknown, '话题服务暂不可用'),
        StackTrace.current,
      );
      return;
    }
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    final generation = ++_generation;
    _request?.cancel();
    final request = _request = RequestCancellation();
    state = const AsyncLoading();
    try {
      final items = await repository.topics(keyword, request);
      if (ref.mounted &&
          generation == _generation &&
          !request.isCancelled &&
          repository.accountScope == scope &&
          repository.sessionEpoch == epoch) {
        state = AsyncData(items);
      }
    } catch (error, stack) {
      if (ref.mounted &&
          generation == _generation &&
          !request.isCancelled &&
          repository.accountScope == scope &&
          repository.sessionEpoch == epoch) {
        state = AsyncError(error, stack);
      }
    }
  }
}
