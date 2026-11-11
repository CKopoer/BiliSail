import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/dynamic/application/dynamic_poll_controller.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_poll.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_fakes.dart';
import '../../support/dynamic_poll_fakes.dart';

void main() {
  late DynamicAuthFake auth;
  late DynamicPollRepositoryFake repository;
  late ProviderContainer container;
  late DynamicPollController controller;
  DynamicPollState state() => container.read(dynamicPollProvider('42'));
  setUp(() async {
    auth = DynamicAuthFake();
    repository = DynamicPollRepositoryFake();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        dynamicPollRepositoryProvider.overrideWithValue(repository),
        dynamicPollClockProvider.overrideWithValue(() => pollNow),
      ],
    );
    container.listen(dynamicPollProvider('42'), (_, _) {});
    controller = container.read(dynamicPollProvider('42').notifier);
    await Future<void>.delayed(Duration.zero);
    await container.pump();
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });

  test(
    'single choice replaces selection; multiple choice enforces server limit',
    () async {
      controller.select(4);
      controller.select(9);
      controller.select(12);
      expect(state().selected, {4, 9});
      expect(state().message, '最多选择2项');
      controller.select(4);
      controller.select(12);
      controller.select(99);
      expect(state().selected, {9, 12});
      repository.loaded = pollFixture(maxChoices: 1);
      await controller.load();
      controller.select(4);
      controller.select(9);
      expect(state().selected, {9});
      controller.select(9);
      expect(state().selected, isEmpty);
    },
  );

  test(
    'only explicit submit writes once and shows authoritative results',
    () async {
      controller.select(9);
      controller.setAnonymous(true);
      expect(repository.votes, isEmpty);
      repository.pendingVote = Completer<DynamicPoll>();
      final pending = controller.submit(dynamicId: '101');
      expect(await controller.submit(), false);
      expect(state().submitting, true);
      final vote = repository.votes.single;
      expect(
        (vote.id, vote.voterId, vote.anonymous, vote.dynamicId),
        ('42', '7', true, '101'),
      );
      expect(vote.choices, [9]);
      repository.pendingVote!.complete(pollFixture(myVotes: {9}));
      expect(await pending, true);
      expect(state().showResults, true);
      expect(state().poll!.hasVoted, true);
      expect(await controller.submit(), false);
    },
  );

  test(
    'uncertain vote locks repeat submission until a successful read',
    () async {
      controller.select(4);
      repository.voteError = const DynamicWriteUncertain();
      expect(await controller.submit(), false);
      expect(state().selected, {4});
      expect(state().uncertain, true);
      expect(await controller.submit(), false);
      repository.readError = const AppFailure(AppFailureKind.network, '读取失败');
      await controller.load();
      expect(state().uncertain, true);
      repository.readError = null;
      repository.loaded = pollFixture(myVotes: {4});
      await controller.load();
      expect(state().uncertain, false);
      expect(state().poll!.hasVoted, true);
      expect(await controller.submit(), false);
      expect(repository.votes, hasLength(1));
    },
  );

  test('expired, already voted and guests cannot submit', () async {
    for (final poll in [
      pollFixture(ended: true),
      pollFixture(myVotes: {9}),
    ]) {
      repository.loaded = poll;
      await controller.load();
      controller.select(4);
      expect(controller.canChoose, false);
      expect(state().showResults, true);
      expect(await controller.submit(), false);
    }
    repository.loaded = pollFixture();
    auth.change(const AuthState(status: AuthStatus.guest));
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    controller.select(4);
    expect(state().signedIn, false);
    expect(await controller.submit(), false);
    expect(repository.votes, isEmpty);
  });

  for (final writing in [false, true]) {
    test(
      'account change cancels ${writing ? 'vote' : 'read'} and discards late response',
      () async {
        final completer = Completer<DynamicPoll>();
        if (writing) {
          repository.pendingVote = completer;
          controller.select(4);
        } else {
          repository.pendingRead = completer;
        }
        final pending = writing ? controller.submit() : controller.load();
        final cancellation = repository.lastCancellation!;
        repository.accountScope = 'user:8';
        repository.sessionEpoch++;
        repository.pendingRead = null;
        repository.loaded = pollFixture();
        auth.change(const AuthState(status: AuthStatus.signedIn, mid: '8'));
        await Future<void>.delayed(Duration.zero);
        await container.pump();
        expect(cancellation.isCancelled, true);
        completer.complete(pollFixture(myVotes: {4}));
        expect(await pending, false);
        expect(state().selected, isEmpty);
        expect(state().poll!.myVotes, isEmpty);
      },
    );
  }

  test('closing provider cancels its in-flight read', () async {
    repository.pendingRead = Completer<DynamicPoll>();
    final pending = controller.load();
    final cancellation = repository.lastCancellation!;
    container.dispose();
    expect(cancellation.isCancelled, true);
    repository.pendingRead!.complete(pollFixture());
    expect(await pending, false);
  });

  test('only official poll URLs with one valid identity resolve', () {
    expect(
      dynamicPollIdFromUri(
        Uri.parse(
          'https://t.bilibili.com/vote/h5/index/?vote_id=9007199254740993123',
        ),
      ),
      '9007199254740993123',
    );
    for (final url in [
      'https://example.com/vote/h5/index/?vote_id=42',
      'https://t.bilibili.com/42?vote_id=42',
      'https://t.bilibili.com/vote/h5/index/?vote_id=1&vote_id=2',
      'https://t.bilibili.com/vote/h5/index/?vote_id=1.2',
    ]) {
      expect(dynamicPollIdFromUri(Uri.parse(url)), isNull);
    }
  });
}
