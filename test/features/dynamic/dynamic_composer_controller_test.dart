import 'dart:async';
import 'dart:typed_data';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/local_image.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/dynamic/application/dynamic_composer_controller.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_composer_repository.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_repository.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_draft.dart';
import 'package:bilisail/features/dynamic/application/dynamic_compose_choices.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_composer_fakes.dart';
import '../../support/dynamic_fakes.dart';

void main() {
  late ProviderContainer container;
  late DynamicComposerFake repository;
  late DynamicAuthFake auth;
  DynamicComposerController controller() =>
      container.read(dynamicComposerProvider.notifier);
  DynamicComposerState state() => container.read(dynamicComposerProvider);
  LocalImage image() => LocalImage(Uint8List.fromList([1, 2, 3]), 'image/png');
  setUp(() {
    repository = DynamicComposerFake();
    auth = DynamicAuthFake();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        dynamicComposerRepositoryProvider.overrideWithValue(repository),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });

  test(
    'empty, guest, oversized text and image limits cannot publish',
    () async {
      expect(await controller().publish(), isFalse);
      controller().setText('😀' * 1001);
      expect(state().canPublish, isFalse);
      controller().setText('😀' * 1000);
      expect(state().canPublish, isTrue);
      controller().addImages(List.generate(19, (_) => image()));
      expect(state().images, isEmpty);
      controller().addImages([LocalImage(Uint8List(0), 'image/png')]);
      expect(state().images, isEmpty);
      auth.change(const AuthState());
      await container.pump();
      controller().setText('游客');
      expect(await controller().publish(), isFalse);
      expect(repository.drafts, isEmpty);
      expect(repository.uploads, isEmpty);
    },
  );

  test(
    'publishes a topic with pictures once and clears only after success',
    () async {
      controller().setText('原始 &+=%/# 文本');
      controller().setTopic(const DynamicComposeTopic('12', '测试话题'));
      controller().addImages([image()]);
      repository.pendingUpload = Completer<DynamicPicture>();
      final pending = controller().publish();
      expect(state().busy, isTrue);
      expect(await controller().publish(), isFalse);
      controller().setText('不能覆盖发送中的快照');
      expect(repository.drafts, isEmpty);
      repository.pendingUpload!.complete(
        DynamicPicture(Uri.https('i0.hdslb.com', '/image.png'), 1, 1, 1),
      );
      expect(await pending, isTrue);
      expect(repository.uploads, hasLength(1));
      final draft = repository.drafts.single;
      expect(
        (draft.mid, draft.text, draft.topic?.id, draft.pictures.length),
        ('7', '原始 &+=%/# 文本', '12', 1),
      );
      expect(state().text, isEmpty);
      expect(state().images, isEmpty);
      expect(state().topic, isNull);
    },
  );

  test('image-only posts work and a known rejection keeps uploaded pictures for explicit retry', () async {
    controller().addImages([image(), image()]);
    repository.createError = const AppFailure(
      AppFailureKind.rateLimited,
      '请求过多',
    );
    expect(await controller().publish(), isFalse);
    expect(state().images, hasLength(2));
    expect(state().uncertain, isFalse);
    repository.createError = null;
    expect(await controller().publish(), isTrue);
    expect(repository.uploads, hasLength(2));
    expect(repository.drafts, hasLength(2));
  });

  test(
    'upload failure retains draft and never creates a partial post',
    () async {
      controller().setText('草稿');
      controller().addImages([image()]);
      repository.uploadError = const AppFailure(AppFailureKind.network, '上传失败');
      expect(await controller().publish(), isFalse);
      expect(repository.drafts, isEmpty);
      expect(
        (state().text, state().images.length, state().busy),
        ('草稿', 1, false),
      );
    },
  );

  test('an uncertain creation stays blocked through editing until explicit reconciliation', () async {
    controller().setText('不要重复');
    repository.createError = const DynamicWriteUncertain();
    expect(await controller().publish(), isFalse);
    expect(state().uncertain, isTrue);
    controller().setText('编辑也不能自动重发');
    controller().clear();
    expect(await controller().publish(), isFalse);
    expect(repository.drafts, hasLength(1));
    controller().confirmNotPublished();
    repository.createError = null;
    expect(await controller().publish(), isTrue);
  });

  for (final sameMid in [false, true]) {
    test(
      'account transition cancels upload and clears draft, sameMid=$sameMid',
      () async {
        controller().setText('私有草稿');
        controller().addImages([image()]);
        repository.pendingUpload = Completer<DynamicPicture>();
        final pending = controller().publish();
        final request = repository.lastRequest!;
        repository.sessionEpoch++;
        repository.accountScope = sameMid ? 'user:7' : 'user:8';
        auth.change(
          AuthState(status: AuthStatus.signedIn, mid: sameMid ? '7' : '8'),
        );
        await container.pump();
        expect(state().text, isEmpty);
        expect(state().images, isEmpty);
        expect(request.isCancelled, isTrue);
        repository.pendingUpload!.complete(
          DynamicPicture(Uri.https('i0.hdslb.com', '/a'), 1, 1, 1),
        );
        expect(await pending, isFalse);
        expect(repository.drafts, isEmpty);
      },
    );
  }

  test('late creation cannot clear a new account draft', () async {
    controller().setText('旧账号');
    repository.pendingCreate = Completer<String>();
    final pending = controller().publish();
    repository.sessionEpoch++;
    repository.accountScope = 'user:8';
    auth.change(const AuthState(status: AuthStatus.signedIn, mid: '8'));
    await container.pump();
    controller().setText('新账号');
    repository.pendingCreate!.complete('123');
    expect(await pending, isFalse);
    expect(state().text, '新账号');
  });

  test(
    'topic search cancels superseded requests and ignores a late result',
    () async {
      final old = Completer<List<DynamicComposeTopic>>();
      repository.onTopics = (query, _) => query == 'old'
          ? old.future
          : Future.value([DynamicComposeTopic('13', query)]);
      container.listen(dynamicComposeTopicsProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      final search = container.read(dynamicComposeTopicsProvider.notifier);
      final pending = search.search('old');
      await search.search('new');
      old.complete([const DynamicComposeTopic('12', 'old')]);
      await pending;
      expect(
        container.read(dynamicComposeTopicsProvider).requireValue.single.name,
        'new',
      );
    },
  );

  test('18 images preserve explicit order and cropping invalidates only the replaced upload', () async {
    final images = List.generate(18, (_) => image());
    controller().addImages(images);
    expect(state().images, hasLength(18));
    controller().moveImage(0, 1);
    expect(state().images[1], same(images[0]));
    repository.createError = const AppFailure(AppFailureKind.rateLimited, '拒绝');
    await controller().publish();
    final replacement = image();
    controller().replaceImage(images[0], replacement);
    controller().removeImage(images.last);
    repository.createError = null;
    expect(await controller().publish(), isTrue);
    expect(repository.uploads, hasLength(19));
    expect(repository.drafts.last.pictures, hasLength(17));
  });

  test(
    'rich content, title and options survive failures and reset after success',
    () async {
      controller().setText('😀');
      controller().insertToken(
        2,
        2,
        '@用户',
        DynamicTextKind.mention,
        id: '9007199254740993123',
      );
      controller().insertToken(5, 5, '[doge]', DynamicTextKind.emote);
      controller().setTitle('标题');
      controller().setOptions(
        const DynamicPublishOptions(
          onlySelf: true,
          replyPolicy: DynamicReplyPolicy.selected,
        ),
      );
      expect(await controller().publish(), isTrue);
      expect(
        repository.drafts.single.spans.map((s) => (s.start, s.end, s.id)),
        [(2, 5, '9007199254740993123'), (5, 11, '')],
      );
      expect(repository.drafts.single.title, '标题');
      expect(repository.drafts.single.options.onlySelf, isTrue);
      expect(state().title, '');
      expect(state().spans, isEmpty);
      expect(state().options.onlySelf, isFalse);
    },
  );

  DynamicPollDraft poll() => DynamicPollDraft(
    title: '选哪个',
    options: const [DynamicPollOption('一'), DynamicPollOption('二')],
    endsAt: DateTime.now().add(const Duration(days: 1)),
  );
  test('image polls upload every option before creating the poll and final dynamic', () async {
    controller().setPoll(
      DynamicPollDraft(
        title: '图片投票',
        withImages: true,
        options: [
          DynamicPollOption('一', image: image()),
          DynamicPollOption('二', image: image()),
        ],
        endsAt: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    expect(await controller().publish(), isTrue);
    expect(repository.uploads, hasLength(2));
    expect(repository.polls, hasLength(1));
    expect(repository.drafts.single.pollId, '123');
  });
  test('an account rotation during attachment creation cannot publish or clear the new draft', () async {
    controller().setPoll(poll());
    repository.pendingPoll = Completer<String>();
    final pending = controller().publish();
    final request = repository.lastRequest!;
    repository.sessionEpoch++;
    repository.accountScope = 'user:8';
    auth.change(const AuthState(status: AuthStatus.signedIn, mid: '8'));
    await container.pump();
    controller().setText('新账号');
    repository.pendingPoll!.complete('123');
    expect(await pending, isFalse);
    expect(request.isCancelled, isTrue);
    expect(repository.drafts, isEmpty);
    expect(state().text, '新账号');
  });
  test('attachments are created only on publish and reused after a known rejection', () async {
    controller().setPoll(poll());
    controller().setReserve(
      DynamicReserveDraft('直播', DateTime.now().add(const Duration(days: 1))),
    );
    expect(repository.polls, isEmpty);
    expect(repository.reserves, isEmpty);
    repository.createError = const AppFailure(AppFailureKind.rateLimited, '拒绝');
    expect(await controller().publish(), isFalse);
    expect(repository.polls, hasLength(1));
    expect(repository.reserves, hasLength(1));
    repository.createError = null;
    expect(await controller().publish(), isTrue);
    expect(repository.polls, hasLength(1));
    expect(repository.reserves, hasLength(1));
    expect(
      (repository.drafts.last.pollId, repository.drafts.last.reserveId),
      ('123', '456'),
    );
    expect((state().poll, state().reserve), (null, null));
  });
  test('uncertain attachment creation blocks dynamic submission and repeat attachment writes', () async {
    controller().setPoll(poll());
    repository.attachmentError = const DynamicWriteUncertain();
    expect(await controller().publish(), isFalse);
    expect(state().uncertain, isTrue);
    controller().setPoll(null);
    expect(state().poll, isNotNull);
    expect(await controller().publish(), isFalse);
    expect(repository.polls, hasLength(1));
    expect(repository.drafts, isEmpty);
  });
  test('expired scheduled drafts and attachments ending before publication never upload', () async {
    controller().setText('定时');
    controller().setOptions(
      DynamicPublishOptions(
        publishAt: DateTime.now().add(const Duration(minutes: 5)),
      ),
    );
    expect(await controller().publish(), isFalse);
    controller().setOptions(
      DynamicPublishOptions(
        publishAt: DateTime.now().add(const Duration(days: 2)),
      ),
    );
    controller().setPoll(poll());
    expect(await controller().publish(), isFalse);
    expect(repository.drafts, isEmpty);
    expect(repository.polls, isEmpty);
  });
  test('mention search cancels stale queries and account changes cancel emote requests', () async {
    final old = Completer<List<DynamicMention>>();
    RequestCancellation? previous, emotes;
    repository.onMentions = (query, cancellation) {
      previous = cancellation;
      return old.future;
    };
    final first = container.listen(
      dynamicComposeMentionsProvider('old'),
      (_, _) {},
    );
    await Future<void>.delayed(Duration.zero);
    first.close();
    await container.pump();
    expect(previous!.isCancelled, isTrue);
    old.complete([const DynamicMention('1', 'old')]);
    final pending = Completer<List<DynamicEmotePackage>>();
    repository.onEmotes = (c) {
      emotes = c;
      return pending.future;
    };
    container.listen(dynamicComposeEmotesProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    final request = emotes!;
    repository.sessionEpoch++;
    auth.change(const AuthState(status: AuthStatus.signedIn, mid: '8'));
    await container.pump();
    expect(request.isCancelled, isTrue);
    pending.complete(const []);
  });
}
