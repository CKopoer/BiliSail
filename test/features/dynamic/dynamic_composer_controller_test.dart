import 'dart:async';
import 'dart:typed_data';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/local_image.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/dynamic/application/dynamic_composer_controller.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_composer_repository.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_repository.dart';
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
      controller().addImages(List.generate(10, (_) => image()));
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
}
