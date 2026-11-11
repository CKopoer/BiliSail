import 'dart:async';

import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/dynamic/application/dynamic_actions_controller.dart';
import 'package:bilisail/features/dynamic/application/dynamic_content_state.dart';
import 'package:bilisail/features/dynamic/application/dynamic_management_controller.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_management_repository.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_fakes.dart';
import '../../support/dynamic_management_fakes.dart';

void main() {
  late DynamicManagementFake repo;
  late DynamicAuthFake auth;
  late ProviderContainer container;
  late DynamicManagementController controller;
  DynamicPost own({bool pinned = false, bool private = false}) => DynamicPost(
    id: '100',
    authorId: const UserId('7'),
    authorName: '自己',
    authorPendantUrl: Uri.https('i0.hdslb.com', '/pendant.png'),
    text: '正文',
    commentTarget: const CommentTarget('100', CommentTargetType.dynamic),
    pinned: pinned,
    onlySelf: private,
    editable: true,
  );
  setUp(() {
    repo = DynamicManagementFake()..loaded = own();
    auth = DynamicAuthFake();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        dynamicRepositoryProvider.overrideWithValue(repo),
      ],
    );
    container.listen(dynamicContentProvider, (_, _) {});
    container.listen(dynamicManagementProvider('100'), (_, _) {});
    controller = container.read(dynamicManagementProvider('100').notifier);
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });
  test(
    'owner checks prevent mutation of another author or mismatched IDs',
    () async {
      final other = DynamicPost(
        id: '100',
        authorId: const UserId('8'),
        editable: true,
      );
      expect(await controller.remove(other), false);
      expect(await controller.pin(other), false);
      expect(await controller.visibility(other, true), false);
      expect(await controller.editDraft(other), null);
      expect(repo.writes, isEmpty);
      auth.change(const AuthState());
      await container.pump();
      expect(await controller.remove(own()), false);
      expect(repo.writes, isEmpty);
    },
  );
  test(
    'pin visibility deletion update shared cards only after confirmed writes',
    () async {
      repo.pendingWrite = Completer<void>();
      final pending = controller.pin(own());
      expect(await controller.pin(own()), false);
      expect(container.read(dynamicContentProvider).posts, isEmpty);
      repo.pendingWrite!.complete();
      expect(await pending, true);
      expect(container.read(dynamicContentProvider).posts['100']!.pinned, true);
      expect(
        container.read(dynamicContentProvider).posts['100']!.authorPendantUrl,
        own().authorPendantUrl,
      );
      repo.pendingWrite = null;
      expect(await controller.visibility(own(), true), true);
      expect(
        container.read(dynamicContentProvider).posts['100']!.onlySelf,
        true,
      );
      expect(await controller.remove(own()), true);
      expect(container.read(dynamicContentProvider).removed, contains('100'));
      expect(repo.writes, [
        'pin:100:true',
        'visibility:100:true',
        'remove:100',
      ]);
    },
  );
  test(
    'uncertain writes stay locked after the card controller is recreated',
    () async {
      repo.writeError = const DynamicWriteUncertain();
      expect(await controller.pin(own()), false);
      container.invalidate(dynamicManagementProvider('100'));
      await container.pump();
      controller = container.read(dynamicManagementProvider('100').notifier);
      expect(await controller.pin(own()), false);
      expect(repo.writes, hasLength(1));
      expect(
        container.read(dynamicContentProvider).locked['100'],
        contains('pin'),
      );
      repo.writeError = null;
      expect(await controller.refresh(), true);
      expect(await controller.pin(own()), true);
      expect(repo.writes, hasLength(2));
    },
  );
  test('report succeeds once and never permits self reporting', () async {
    expect(await controller.report(own(), 4, ''), false);
    final other = DynamicPost(id: '100', authorId: const UserId('8'));
    expect(await controller.report(other, 4, '说明'), true);
    expect(await controller.report(other, 4, '说明'), false);
    expect(repo.writes, ['report:100:4:说明']);
  });
  test('interaction mutations require current server permission and use the comment identity', () async {
    final post = DynamicPost(
      id: '100',
      authorId: const UserId('7'),
      commentTarget: const CommentTarget('1234', CommentTargetType.album),
    );
    expect(await controller.setInteraction(post, 3), false);
    expect(await controller.loadInteraction(post), true);
    expect(await controller.setInteraction(post, 3), true);
    expect(repo.writes, ['interaction:1234:11:3']);
    expect(
      container.read(dynamicContentProvider).posts['100']!.commentForbidden,
      true,
    );
    repo.settings = const DynamicInteractionSettings(
      canSelect: false,
      selected: false,
      canComment: false,
      comments: false,
    );
    await controller.loadInteraction(post);
    expect(await controller.setInteraction(post, 4), false);
    expect(await controller.setInteraction(post, 1), false);
    expect(repo.writes, hasLength(1));
  });
  for (final sameMid in [false, true]) {
    test('session rotation discards late mutation sameMid=$sameMid', () async {
      repo.pendingWrite = Completer<void>();
      final pending = controller.remove(own());
      final request = repo.lastCancellation!;
      repo.sessionEpoch++;
      repo.accountScope = sameMid ? 'user:7' : 'user:8';
      auth.change(
        AuthState(status: AuthStatus.signedIn, mid: sameMid ? '7' : '8'),
      );
      await container.pump();
      repo.pendingWrite!.complete();
      expect(await pending, false);
      expect(request.isCancelled, true);
      expect(container.read(dynamicContentProvider).removed, isEmpty);
    });
  }
  test('late reads cannot populate the next account cache', () async {
    repo.pendingDetail = Completer<DynamicPost>();
    final pending = controller.refresh();
    repo.sessionEpoch++;
    repo.accountScope = 'user:8';
    auth.change(const AuthState(status: AuthStatus.signedIn, mid: '8'));
    await container.pump();
    repo.pendingDetail!.complete(own());
    expect(await pending, false);
    expect(container.read(dynamicContentProvider).posts, isEmpty);
  });
  test(
    'temporary filters and mutation records are bounded and account scoped',
    () async {
      final content = container.read(dynamicContentProvider.notifier);
      for (var i = 1; i <= 150; i++) {
        content.hideAuthor('$i', 'name');
      }
      expect(
        container.read(dynamicContentProvider).hiddenAuthors,
        hasLength(128),
      );
      content.restoreAuthor('150');
      expect(
        container.read(dynamicContentProvider).hiddenAuthors.containsKey('150'),
        false,
      );
      for (var i = 1; i <= 600; i++) {
        content.update(DynamicPost(id: '$i'));
        content.remove('$i');
        content.lock('$i', 'report');
      }
      expect(container.read(dynamicContentProvider).posts, hasLength(512));
      expect(container.read(dynamicContentProvider).removed, hasLength(512));
      auth.change(const AuthState());
      await container.pump();
      expect(container.read(dynamicContentProvider).hiddenAuthors, isEmpty);
      expect(container.read(dynamicContentProvider).locked, isEmpty);
    },
  );
}
