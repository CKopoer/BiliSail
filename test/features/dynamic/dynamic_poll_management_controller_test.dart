import 'dart:async';

import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/dynamic/application/dynamic_poll_controller.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_poll.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_fakes.dart';
import '../../support/dynamic_managed_poll_fakes.dart';

void main() {
  late DynamicPollFake repo;
  late DynamicAuthFake auth;
  late ProviderContainer container;
  late DynamicPollController controller;
  final now = DateTime(2026, 11, 11, 12);
  DynamicPollState state() => container.read(dynamicPollProvider('123'));
  setUp(() async {
    repo = DynamicPollFake()
      ..value = sampleDynamicPoll(endsAt: now.add(const Duration(days: 1)));
    auth = DynamicAuthFake();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        dynamicPollRepositoryProvider.overrideWithValue(repo),
        dynamicPollClockProvider.overrideWithValue(() => now),
      ],
    );
    container.listen(dynamicPollProvider('123'), (_, _) {});
    controller = container.read(dynamicPollProvider('123').notifier);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });
  test('multi choice limits, anonymous voting, and explicit submission use one snapshot', () async {
    controller.select(1);
    controller.select(2);
    controller.select(3);
    expect(state().selected, {1, 2});
    expect(repo.votes, isEmpty);
    controller.setAnonymous(true);
    repo.pendingVote = Completer<DynamicPoll>();
    final pending = controller.submit(dynamicId: '100');
    controller.select(1);
    expect(await controller.submit(dynamicId: '100'), false);
    expect(repo.votes.single.choices, [1, 2]);
    expect(repo.votes.single.anonymous, true);
    repo.pendingVote!.complete(sampleDynamicPoll(votes: [1, 2]));
    expect(await pending, true);
    expect(state().showResults, true);
    expect(state().poll!.myVotes, {1, 2});
    controller.select(3);
    expect(await controller.submit(dynamicId: '100'), false);
    expect(repo.votes, hasLength(1));
  });
  test('single choice replaces the prior choice and results use total option votes', () async {
    repo.value = sampleDynamicPoll(
      maxChoices: 1,
      endsAt: now.add(const Duration(days: 1)),
    );
    await controller.load();
    controller.select(1);
    controller.select(2);
    expect(state().selected, {2});
    expect(state().poll!.fraction(1), .6);
    controller.setShowResults(true);
    expect(state().showResults, true);
  });
  test('guest, expired and already-voted polls never write', () async {
    auth.change(const AuthState());
    await container.pump();
    await Future<void>.delayed(Duration.zero);
    controller.select(1);
    expect(await controller.submit(dynamicId: '100'), false);
    auth.change(const AuthState(status: AuthStatus.signedIn, mid: '7'));
    await container.pump();
    await Future<void>.delayed(Duration.zero);
    repo.value = sampleDynamicPoll(
      endsAt: now.subtract(const Duration(seconds: 1)),
    );
    await controller.load();
    controller.select(1);
    expect(await controller.submit(dynamicId: '100'), false);
    repo.value = sampleDynamicPoll(
      votes: [1],
      endsAt: now.add(const Duration(days: 1)),
    );
    await controller.load();
    expect(await controller.submit(dynamicId: '100'), false);
    expect(repo.votes, isEmpty);
  });
  test(
    'uncertain vote cannot replay before explicit refresh reconciliation',
    () async {
      controller.select(1);
      repo.voteError = const DynamicWriteUncertain();
      expect(await controller.submit(dynamicId: '100'), false);
      expect(state().uncertain, true);
      controller.select(2);
      expect(await controller.submit(dynamicId: '100'), false);
      expect(repo.votes, hasLength(1));
      repo.value = sampleDynamicPoll(
        votes: [1],
        endsAt: now.add(const Duration(days: 1)),
      );
      await controller.load();
      expect(state().uncertain, false);
      expect(await controller.submit(dynamicId: '100'), false);
    },
  );
  test(
    'late vote and social responses cannot cross an account epoch',
    () async {
      controller.select(1);
      repo.pendingVote = Completer<DynamicPoll>();
      final pending = controller.submit(dynamicId: '100');
      final c = repo.lastRequest!;
      repo.sessionEpoch++;
      repo.accountScope = 'user:8';
      auth.change(const AuthState(status: AuthStatus.signedIn, mid: '8'));
      await container.pump();
      repo.pendingVote!.complete(sampleDynamicPoll(votes: [1]));
      expect(await pending, false);
      expect(c.isCancelled, true);
      expect(state().poll?.myVotes ?? [], isEmpty);
    },
  );
  test('closing and reopening cannot replay an uncertain vote', () async {
    controller.select(1);
    repo.voteError = const DynamicWriteUncertain();
    expect(await controller.submit(dynamicId: '100'), false);
    container.invalidate(dynamicPollProvider('123'));
    await container.pump();
    controller = container.read(dynamicPollProvider('123').notifier);
    await Future<void>.delayed(Duration.zero);
    expect(state().uncertain, true);
    expect(state().canConfirmNotVoted, true);
    controller.select(2);
    expect(await controller.submit(dynamicId: '100'), false);
    expect(repo.votes, hasLength(1));
    controller.confirmNotVoted();
    expect(state().uncertain, false);
    repo.voteError = null;
    controller.select(2);
    expect(await controller.submit(dynamicId: '100'), true);
    expect(repo.votes, hasLength(2));
  });
}
