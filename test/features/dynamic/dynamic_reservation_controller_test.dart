import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/dynamic/application/dynamic_actions_controller.dart';
import 'package:bilisail/features/dynamic/application/dynamic_content_state.dart';
import 'package:bilisail/features/dynamic/application/dynamic_reservation_controller.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_fakes.dart';
import '../../support/dynamic_reservation_fakes.dart';

void main() {
  late DynamicAuthFake auth;
  late DynamicReservationFake repository;
  late ProviderContainer container;
  late DynamicReservationController controller;
  final provider = dynamicReservationProvider(reservation.id);
  DynamicReservationState state() => container.read(provider);
  DynamicReservation? value() =>
      container.read(dynamicContentProvider).reservations[reservation.id];
  setUp(() {
    auth = DynamicAuthFake();
    repository = DynamicReservationFake();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        dynamicRepositoryProvider.overrideWithValue(repository),
      ],
    );
    container.listen(provider, (_, _) {});
    controller = container.read(provider.notifier);
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });

  test('rapid clicks submit once and server state supplies cancellation parameters', () async {
    repository.pending = Completer<DynamicReservation>();
    final pending = controller.toggle('100', reservation);
    expect(await controller.toggle('100', reservation), false);
    expect(state().busy, true);
    expect(value(), isNull);
    expect(repository.reservations, [('100', 1, 10)]);
    repository.pending!.complete(reservation.updated(2, 42, '服务端人数'));
    expect(await pending, true);
    expect(
      (value()!.checked, value()!.total, value()!.description),
      (true, 42, '服务端人数'),
    );
    repository.pending = null;
    expect(await controller.toggle('100', reservation), true);
    expect(repository.reservations.last, ('100', 2, 42));
    expect(value()!.checked, false);
  });

  test(
    'uncertain results block replay until a matching authoritative detail read',
    () async {
      repository.error = const DynamicWriteUncertain();
      expect(await controller.toggle('100', reservation), false);
      expect(state().uncertain, true);
      expect(await controller.toggle('100', reservation), false);
      repository.error = null;
      expect(await controller.refresh('100', reservation), false);
      expect(state().uncertain, true);
      repository.loaded = DynamicPost(
        id: '100',
        contentCards: [
          reservationCard(value: reservation.updated(2, 99, '99人预约')),
        ],
      );
      expect(await controller.refresh('100', reservation), true);
      expect(state().uncertain, false);
      expect(repository.reservations, hasLength(1));
      expect(await controller.toggle('100', reservation), true);
      expect(repository.reservations.last, ('100', 2, 99));
    },
  );

  test(
    'reopening a disposed controller retains uncertainty and successful state',
    () async {
      repository.error = const DynamicWriteUncertain();
      await controller.toggle('100', reservation);
      container.invalidate(provider);
      controller = container.read(provider.notifier);
      expect(state().uncertain, true);
      expect(await controller.toggle('100', reservation), false);
      repository.loaded = DynamicPost(
        id: '100',
        contentCards: [reservationCard()],
      );
      await controller.refresh('100', reservation);
      container.invalidate(provider);
      controller = container.read(provider.notifier);
      expect(state().uncertain, false);
      expect(value()?.total, 10);
    },
  );

  test('known failures and cancellation do not change the card', () async {
    for (final kind in [AppFailureKind.permission, AppFailureKind.cancelled]) {
      repository.error = AppFailure(kind, '请求失败');
      expect(await controller.toggle('100', reservation), false);
      expect(state().uncertain, false);
      expect(value(), isNull);
      expect(state().message, kind == AppFailureKind.cancelled ? null : '请求失败');
    }
  });

  test('account switch cancels requests, clears cached status and ignores late success', () async {
    repository.pending = Completer<DynamicReservation>();
    final pending = controller.toggle('100', reservation);
    final cancellation = repository.lastCancellation!;
    repository.accountScope = 'user:8';
    repository.sessionEpoch++;
    auth.change(const AuthState(status: AuthStatus.signedIn, mid: '8'));
    await container.pump();
    expect(cancellation.isCancelled, true);
    repository.pending!.complete(reservation.updated(2, 11, '成功'));
    expect(await pending, false);
    expect(state().busy, false);
    expect(value(), isNull);
    expect(container.read(dynamicContentProvider).locked, isEmpty);
  });

  test('scope drift before submission, guests and non-actionable reservations never write', () async {
    for (final seed in [
      const DynamicReservation(
        id: '9007199254740993123',
        status: 1,
        type: 2,
        total: 10,
        disabled: true,
      ),
      const DynamicReservation(
        id: '9007199254740993123',
        status: 1,
        type: 2,
        total: 10,
        ended: true,
      ),
      const DynamicReservation(
        id: '9007199254740993123',
        status: 1,
        type: 2,
        total: 10,
        hasJump: true,
      ),
      const DynamicReservation(id: 'other', status: 1, type: 2, total: 10),
    ]) {
      expect(await controller.toggle('100', seed), false);
    }
    repository.accountScope = 'user:8';
    expect(await controller.toggle('100', reservation), false);
    repository.accountScope = 'guest';
    auth.change(const AuthState(status: AuthStatus.guest));
    await container.pump();
    expect(await controller.toggle('100', reservation), false);
    expect(repository.reservations, isEmpty);
  });

  test(
    'newly disabled or finished cards override a cached successful action',
    () async {
      expect(await controller.toggle('100', reservation), true);
      expect(value()?.checked, true);
      final ended = DynamicReservation(
        id: reservation.id,
        status: 1,
        type: 2,
        total: 20,
        ended: true,
      );
      expect(await controller.toggle('100', ended), false);
      expect(repository.reservations, hasLength(1));
    },
  );

  test(
    'closing a view cancels its pending write and preserves a refresh lock',
    () async {
      repository.pending = Completer<DynamicReservation>();
      final pending = controller.toggle('100', reservation);
      final cancellation = repository.lastCancellation!;
      container.invalidate(provider);
      container.read(provider);
      expect(cancellation.isCancelled, true);
      repository.pending!.complete(reservation.updated(2, 11, '成功'));
      expect(await pending, false);
      expect(state().uncertain, true);
    },
  );
}
