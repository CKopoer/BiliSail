import 'dart:async';

import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/dynamic/application/dynamic_actions_controller.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_repository.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/shared/ui/dynamic_content_card.dart';
import 'package:bilisail/shared/ui/dynamic_post_interactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_fakes.dart';
import '../../support/dynamic_reservation_fakes.dart';

void main() {
  late DynamicAuthFake auth;
  late DynamicReservationFake repository;
  late List<Uri> links;
  late int logins;
  setUp(() {
    auth = DynamicAuthFake();
    repository = DynamicReservationFake();
    links = [];
    logins = 0;
  });
  tearDown(() => auth.stream.close());

  Future<void> show(
    WidgetTester tester, {
    DynamicReservation value = reservation,
    bool forwarded = false,
    bool inDetail = false,
    DynamicContentCard? contentCard,
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        dynamicRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        builder: AppNoticeHost.builder,
        home: Scaffold(
          body: SingleChildScrollView(
            child: InteractiveDynamicPostCard(
              post: forwarded
                  ? DynamicPost(
                      id: '200',
                      original: DynamicPost(
                        id: '100',
                        contentCards: [
                          contentCard ?? reservationCard(value: value),
                        ],
                      ),
                    )
                  : DynamicPost(
                      id: '100',
                      contentCards: [
                        contentCard ?? reservationCard(value: value),
                      ],
                    ),
              inDetail: inDetail,
              onOpenLink: links.add,
              onLogin: () => logins++,
            ),
          ),
        ),
      ),
    ),
  );
  Finder button(String label) => find.widgetWithText(OutlinedButton, label);

  for (final forwarded in [false, true]) {
    for (final hasMetadata in [false, true]) {
      testWidgets(
        'reservation body stays on the current page forwarded=$forwarded metadata=$hasMetadata',
        (tester) async {
          await show(
            tester,
            forwarded: forwarded,
            contentCard: hasMetadata
                ? null
                : DynamicContentCard(
                    kind: DynamicCardKind.reservation,
                    title: '明晚直播',
                    description: '明天20点',
                    url: Uri.https('t.bilibili.com', '/100'),
                    actionLabel: '查看详情',
                  ),
          );
          final bounds = tester.getRect(find.byType(DynamicContentCardView));
          for (final position in [
            tester.getCenter(find.text('明晚直播')),
            tester.getCenter(find.textContaining('明天20点')),
            bounds.topRight + const Offset(-12, 12),
          ]) {
            await tester.tapAt(position);
            await tester.pumpAndSettle();
            expect(links, isEmpty);
            expect(repository.reservations, isEmpty);
            expect(logins, 0);
            expect(find.byType(InteractiveDynamicPostCard), findsOneWidget);
            expect(
              Navigator.of(
                tester.element(find.byType(InteractiveDynamicPostCard)),
              ).canPop(),
              false,
            );
          }
        },
      );
    }
  }

  for (final forwarded in [false, true]) {
    testWidgets(
      'reservation and cancellation in ${forwarded ? "forwarded content" : "detail"} use owner identity',
      (tester) async {
        await show(tester, forwarded: forwarded, inDetail: !forwarded);
        repository.pending = Completer<DynamicReservation>();
        await tester.tap(button('预约'));
        await tester.pump();
        expect(tester.widget<OutlinedButton>(button('预约')).onPressed, isNull);
        expect(repository.reservations, [('100', 1, 10)]);
        repository.pending!.complete(reservation.updated(2, 42, '服务端确认人数'));
        await tester.pumpAndSettle();
        expect(button('已预约'), findsOneWidget);
        expect(find.textContaining('服务端确认人数'), findsOneWidget);
        expect(find.text('42人预约'), findsOneWidget);
        repository.pending = null;
        await tester.tap(button('已预约'));
        await tester.pumpAndSettle();
        expect(repository.reservations.last, ('100', 2, 42));
        expect(button('预约'), findsOneWidget);
        expect(links, isEmpty);
      },
    );
  }

  testWidgets(
    'guest reservation opens login without a write or external navigation',
    (tester) async {
      auth.change(const AuthState(status: AuthStatus.guest));
      await show(tester);
      await tester.tap(button('预约'));
      expect(logins, 1);
      expect(repository.reservations, isEmpty);
      expect(links, isEmpty);
    },
  );

  for (final (disabled, ended, jump) in [
    (true, false, false),
    (false, true, false),
    (false, false, true),
  ]) {
    testWidgets(
      'reservation flags disabled=$disabled ended=$ended jump=$jump preserve action boundaries',
      (tester) async {
        await show(
          tester,
          value: DynamicReservation(
            id: reservation.id,
            status: 1,
            type: 2,
            total: 10,
            disabled: disabled,
            ended: ended,
            hasJump: jump,
          ),
        );
        final action = button('预约');
        expect(tester.widget<OutlinedButton>(action).onPressed == null, !jump);
        if (jump) {
          await tester.tap(action);
          expect(links.single.path, '/100');
        }
        expect(repository.reservations, isEmpty);
      },
    );
  }

  testWidgets('uncertain result replaces mutation with read-only refresh', (
    tester,
  ) async {
    repository.error = const DynamicWriteUncertain();
    await show(tester);
    await tester.tap(button('预约'));
    await tester.pumpAndSettle();
    expect(button('刷新预约状态'), findsOneWidget);
    repository.error = null;
    repository.loaded = DynamicPost(
      id: '100',
      contentCards: [
        reservationCard(value: reservation.updated(2, 55, '服务端已预约')),
      ],
    );
    await tester.tap(button('刷新预约状态'));
    await tester.pumpAndSettle();
    expect(button('已预约'), findsOneWidget);
    expect(repository.reservations, hasLength(1));
  });
}
