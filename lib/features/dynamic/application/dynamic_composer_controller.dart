import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/local_image.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/dynamic_composer_repository.dart';
import '../domain/dynamic_repository.dart';
import '../domain/dynamic_draft.dart';
import '../domain/dynamic_management_repository.dart';

final dynamicComposerClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

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
    this.title = '',
    this.spans = const [],
    this.options = const DynamicPublishOptions(),
    this.poll,
    this.reserve,
    this.existingPictures = const [],
    this.editId,
    this.repostId,
    this.reserveId,
  });
  final String text, accountScope;
  final String? mid, message;
  final List<LocalImage> images;
  final DynamicComposeTopic? topic;
  final bool busy, uncertain;
  final int uploaded, sessionEpoch;
  static const maxImages = 18;
  final String title;
  final List<DynamicTextSpan> spans;
  final DynamicPublishOptions options;
  final DynamicPollDraft? poll;
  final DynamicReserveDraft? reserve;
  final List<DynamicPicture> existingPictures;
  final String? editId, repostId, reserveId;
  bool get canPublish =>
      mid != null &&
      !busy &&
      !uncertain &&
      title.runes.length <= 20 &&
      text.runes.length + (poll?.title.runes.length ?? 0) <= 1000 &&
      (text.trim().isNotEmpty ||
          images.isNotEmpty ||
          existingPictures.isNotEmpty ||
          reserveId != null ||
          poll != null ||
          reserve != null);
  DynamicComposerState copy({
    String? text,
    List<LocalImage>? images,
    DynamicComposeTopic? topic,
    bool clearTopic = false,
    bool? busy,
    bool? uncertain,
    String? message,
    int? uploaded,
    String? title,
    List<DynamicTextSpan>? spans,
    DynamicPublishOptions? options,
    DynamicPollDraft? poll,
    DynamicReserveDraft? reserve,
    bool clearPoll = false,
    bool clearReserve = false,
    List<DynamicPicture>? existingPictures,
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
    title: title ?? this.title,
    spans: spans ?? this.spans,
    options: options ?? this.options,
    poll: clearPoll ? null : poll ?? this.poll,
    reserve: clearReserve ? null : reserve ?? this.reserve,
    existingPictures: existingPictures ?? this.existingPictures,
    editId: editId,
    repostId: repostId,
    reserveId: reserveId,
  );
}

class DynamicComposerController extends Notifier<DynamicComposerState> {
  DynamicComposerController({this.editDraft});
  final DynamicEditDraft? editDraft;
  bool _seeded = false;
  RequestCancellation? _request;
  int _generation = 0;
  final _pictures = <LocalImage, DynamicPicture>{};
  String? _pollId, _reserveId;
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
    _pollId = _reserveId = null;
    _generation++;
    ref.onDispose(() {
      _generation++;
      _request?.cancel();
      _pictures.clear();
    });
    final seed = editDraft;
    final maySeed = !_seeded;
    _seeded = true;
    final matches =
        account.$1 &&
        (seed == null || (maySeed && seed.authorId == account.$2));
    return DynamicComposerState(
      accountScope: repository?.accountScope ?? 'guest',
      sessionEpoch: repository?.sessionEpoch ?? 0,
      mid: matches ? account.$2 : null,
      text: matches ? seed?.text ?? '' : '',
      title: matches ? seed?.title ?? '' : '',
      spans: matches ? seed?.spans ?? const [] : const [],
      existingPictures: matches ? seed?.pictures ?? const [] : const [],
      topic: matches ? seed?.topic : null,
      options: matches
          ? seed?.options ?? const DynamicPublishOptions()
          : const DynamicPublishOptions(),
      editId: seed?.id,
      repostId: seed?.repostId,
      reserveId: seed?.reserveId,
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
    if (!state.busy) {
      state = state.copy(
        text: text,
        spans: reconcileDynamicText(state.text, text, state.spans),
      );
    }
  }

  void insertToken(
    int start,
    int end,
    String text,
    DynamicTextKind kind, {
    String id = '',
  }) {
    if (state.busy || start < 0 || end < start || end > state.text.length) {
      return;
    }
    // Remove overlapping identities before replacing, even if the label is unchanged.
    final remaining = state.spans
        .where((s) => s.end <= start || s.start >= end)
        .toList();
    final value = state.text.replaceRange(start, end, text);
    final spans = [
      ...reconcileDynamicText(state.text, value, remaining),
      DynamicTextSpan(start, start + text.length, kind, id: id),
    ]..sort((a, b) => a.start.compareTo(b.start));
    state = state.copy(text: value, spans: List.unmodifiable(spans));
  }

  void setTitle(String title) {
    if (!state.busy) state = state.copy(title: title);
  }

  void setOptions(DynamicPublishOptions options) {
    if (!state.busy) state = state.copy(options: options);
  }

  void setPoll(DynamicPollDraft? poll) {
    if (state.busy || state.uncertain || state.editId != null) return;
    final retained = {...state.images, ...?poll?.options.map((o) => o.image)};
    _pictures.removeWhere((image, _) => !retained.contains(image));
    _pollId = null;
    state = state.copy(poll: poll, clearPoll: poll == null);
  }

  void setReserve(DynamicReserveDraft? reserve) {
    if (state.busy || state.uncertain || state.editId != null) return;
    _reserveId = null;
    state = state.copy(reserve: reserve, clearReserve: reserve == null);
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
        state.images.length + state.existingPictures.length + images.length >
            DynamicComposerState.maxImages) {
      state = state.copy(message: '最多添加18张图片，每张不超过10 MB');
      return;
    }
    state = state.copy(images: List.unmodifiable([...state.images, ...images]));
  }

  void replaceImage(LocalImage before, LocalImage after) {
    if (state.busy || !state.images.contains(before)) return;
    if (after.bytes.isEmpty ||
        after.bytes.length > LocalImage.maxBytes ||
        !const {
          'image/png',
          'image/jpeg',
          'image/gif',
        }.contains(after.mimeType)) {
      return;
    }
    _pictures.remove(before);
    state = state.copy(
      images: List.unmodifiable([
        for (final image in state.images)
          identical(image, before) ? after : image,
      ]),
    );
  }

  void moveImage(int index, int delta) {
    final target = index + delta;
    if (state.busy ||
        index < 0 ||
        index >= state.images.length ||
        target < 0 ||
        target >= state.images.length) {
      return;
    }
    final images = [...state.images];
    images.insert(target, images.removeAt(index));
    state = state.copy(images: List.unmodifiable(images));
  }

  void removeImage(LocalImage image) {
    if (state.busy) return;
    _pictures.remove(image);
    state = state.copy(
      images: List.unmodifiable(state.images.where((i) => i != image)),
    );
  }

  void removeExistingPicture(DynamicPicture picture) {
    if (state.busy) return;
    state = state.copy(
      existingPictures: List.unmodifiable(
        state.existingPictures.where((p) => !identical(p, picture)),
      ),
    );
  }

  void clear() {
    if (state.busy || state.uncertain) return;
    _pictures.clear();
    _pollId = _reserveId = null;
    state = state.copy(
      text: '',
      images: const [],
      existingPictures: const [],
      clearTopic: true,
      uploaded: 0,
      title: '',
      spans: const [],
      options: const DynamicPublishOptions(),
      clearPoll: true,
      clearReserve: true,
    );
  }

  void confirmNotPublished() {
    if (!state.busy) state = state.copy(uncertain: false);
  }

  Future<bool> publish() async {
    if (!state.canPublish) return false;
    final now = ref.read(dynamicComposerClockProvider)();
    if (!state.options.validAt(now) ||
        (state.poll != null &&
            (!state.poll!.validAt(now) ||
                (state.options.publishAt != null &&
                    !state.poll!.endsAt.isAfter(state.options.publishAt!)))) ||
        (state.reserve != null &&
            (!state.reserve!.validAt(now) ||
                (state.options.publishAt != null &&
                    !state.reserve!.startsAt.isAfter(
                      state.options.publishAt!,
                    ))))) {
      state = state.copy(message: '请检查定时发布时间（6分钟至7天）、投票截止或预约时间；附件时间须晚于发布时间。');
      return false;
    }
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
      final pictures = <DynamicPicture>[...draft.existingPictures];
      for (final image in draft.images) {
        if (!current()) return false;
        final picture =
            _pictures[image] ?? await repository.upload(image, request);
        if (!current()) return false;
        _pictures[image] = picture;
        pictures.add(picture);
        state = state.copy(
          uploaded: pictures.length - draft.existingPictures.length,
          busy: true,
        );
      }
      if (!current()) return false;
      if (draft.poll case final poll? when _pollId == null) {
        final pollPictures = <DynamicPicture>[];
        if (poll.withImages) {
          for (final option in poll.options) {
            final image = option.image!;
            final picture =
                _pictures[image] ??
                await repository.upload(image, request, forPoll: true);
            if (!current()) return false;
            _pictures[image] = picture;
            pollPictures.add(picture);
          }
        }
        final id = await repository.createPoll(
          poll,
          pollPictures,
          mid,
          request,
        );
        if (!current()) return false;
        _pollId = id;
      }
      if (draft.reserve case final reserve? when _reserveId == null) {
        final id = await repository.createReserve(reserve, request);
        if (!current()) return false;
        _reserveId = id;
      }
      if (draft.editId case final editId?) {
        if (repository is! DynamicEditRepository) {
          throw const AppFailure(AppFailureKind.permission, '编辑服务暂不可用');
        }
        await (repository as DynamicEditRepository).edit(
          mid: mid,
          id: editId,
          title: draft.title,
          text: draft.text,
          spans: draft.spans,
          pictures: pictures,
          topic: draft.topic,
          options: draft.options,
          repostId: draft.repostId,
          reserveId: draft.reserveId,
          cancellation: request,
        );
      } else {
        await repository.create(
          mid: mid,
          text: draft.text,
          pictures: pictures,
          topic: draft.topic,
          title: draft.title,
          spans: draft.spans,
          options: draft.options,
          pollId: _pollId,
          pollTitle: draft.poll?.title,
          reserveId: _reserveId,
          cancellation: request,
        );
      }
      if (!current()) return false;
      state = state.copy(
        busy: false,
        text: '',
        images: const [],
        existingPictures: const [],
        clearTopic: true,
        uploaded: 0,
        title: '',
        spans: const [],
        options: const DynamicPublishOptions(),
        clearPoll: true,
        clearReserve: true,
      );
      _pictures.clear();
      _pollId = _reserveId = null;
      return true;
    } catch (error) {
      if (!current()) return false;
      final uncertain = error is DynamicWriteUncertain;
      state = state.copy(
        busy: false,
        uncertain: uncertain,
        message: uncertain
            ? '动态或附件的创建结果暂时无法确认，请先核对自己的动态、投票和预约，确认未创建后再继续。'
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
