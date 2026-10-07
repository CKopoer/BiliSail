import 'dart:async';

import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/dynamic/application/dynamic_actions_controller.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_fakes.dart';

void main() {
  late DynamicAuthFake auth;
  late DynamicRepositoryFake repository;
  late ProviderContainer container;
  late DynamicActionsController controller;
  final post = DynamicPost(id: '100', likeCount: 4, repostCount: 2);
  DynamicActionsState state() => container.read(dynamicActionsProvider('100'));
  setUp(() {
    auth = DynamicAuthFake();
    repository = DynamicRepositoryFake();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        dynamicRepositoryProvider.overrideWithValue(repository),
      ],
    );
    container.listen(dynamicActionsProvider('100'), (_, _) {});
    controller = container.read(dynamicActionsProvider('100').notifier);
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });

  test(
    'rapid clicks send once, update after success, and can cancel the like',
    () async {
      repository.pendingLike = Completer<void>();
      final pending = controller.toggleLike(post);
      expect(await controller.toggleLike(post), false);
      expect(state().liked, isNull);
      expect(repository.likes, [('100', true)]);
      repository.pendingLike!.complete();
      expect(await pending, true);
      expect(state().liked, true);
      expect(state().likeCount, 5);
      repository.pendingLike = null;
      expect(await controller.toggleLike(post), true);
      expect(repository.likes.last, ('100', false));
      expect(state().likeCount, 4);
    },
  );

  test(
    'unknown like blocks replays until an authoritative read resolves it',
    () async {
      repository.error = const DynamicWriteUncertain();
      expect(await controller.toggleLike(post), false);
      expect(state().likeUncertain, true);
      expect(await controller.toggleLike(post), false);
      expect(repository.likes, hasLength(1));
      repository.error = null;
      expect(await controller.refresh(), true);
      expect(state().likeUncertain, false);
      expect(state().liked, true);
      await controller.toggleLike(post);
      expect(repository.likes.last, ('100', false));
    },
  );

  test('unknown repost retains lock across refresh and needs explicit acknowledgement', () async {
    repository.error = const DynamicWriteUncertain();
    expect(await controller.repost(post, '草稿'), false);
    expect(state().repostUncertain, true);
    repository.error = null;
    await controller.refresh();
    expect(await controller.repost(post, '草稿'), false);
    expect(repository.reposts, hasLength(1));
    controller.acknowledgeRepost();
    expect(await controller.repost(post, '草稿'), true);
    expect(state().repostCount, 3);
  });

  for (final action in ['like', 'repost']) {
    test(
      'account change cancels $action and ignores its late success',
      () async {
        repository.pendingLike = Completer<void>();
        repository.pendingRepost = Completer<String>();
        final pending = action == 'like'
            ? controller.toggleLike(post)
            : controller.repost(post, '草稿');
        final cancellation = repository.lastCancellation!;
        repository.accountScope = 'user:8';
        repository.sessionEpoch++;
        auth.change(const AuthState(status: AuthStatus.signedIn, mid: '8'));
        await container.pump();
        expect(cancellation.isCancelled, true);
        repository.pendingLike!.complete();
        repository.pendingRepost!.complete('101');
        expect(await pending, false);
        expect(state().liked, isNull);
        expect(state().repostCount, isNull);
        expect(state().accountScope, 'user:8');
      },
    );
  }

  test(
    'guests, unavailable content and forbidden actions never mutate',
    () async {
      expect(
        await controller.toggleLike(
          DynamicPost(id: '100', likeForbidden: true),
        ),
        false,
      );
      expect(
        await controller.repost(
          DynamicPost(id: '100', repostForbidden: true),
          '',
        ),
        false,
      );
      auth.change(const AuthState());
      await container.pump();
      expect(await controller.toggleLike(post), false);
      expect(await controller.repost(post, ''), false);
      expect(repository.likes, isEmpty);
      expect(repository.reposts, isEmpty);
    },
  );
}
