import 'package:bilisail/app/shell.dart';
import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/presentation/messages_screen.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'message_fakes.dart';

void main() {
  for (final mode in WorkspaceNavigationMode.values) {
    testWidgets(
      'message title shares the back row and retains actions in $mode',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 850);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final auth = AuthFake();
        addTearDown(auth.stream.close);
        final repo = MessageRepositoryFake();
        final opened = <Uri>[];
        final scale = ValueNotifier(1.0);
        addTearDown(scale.dispose);
        final router = GoRouter(
          routes: [
            ShellRoute(
              builder: (context, state, child) => BiliAppShell(
                location: state.uri.toString(),
                navigationMode: mode,
                pageBuilder: (_, tab) => tab.isMessages
                    ? const MessagesScreen()
                    : const Center(child: Text('原来的页面')),
                child: child,
              ),
              routes: [
                for (final path in ['/', '/messages'])
                  GoRoute(
                    path: path,
                    builder: (_, _) => const SizedBox.shrink(),
                  ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(auth),
              messageRepositoryProvider.overrideWithValue(repo),
              externalLinkOpenerProvider.overrideWithValue((uri) async {
                opened.add(uri);
                return true;
              }),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              builder: (context, child) => ValueListenableBuilder<double>(
                valueListenable: scale,
                builder: (context, value, _) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(value)),
                  child: child!,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        router.go('/messages');
        await tester.pumpAndSettle();
        final refresh = find.byTooltip('刷新消息');
        final official = find.byTooltip('官方消息页');
        final title = find.descendant(
          of: find.byType(MessagesScreen),
          matching: find.text('我的消息'),
        );
        final back = find.byKey(const ValueKey('workspace-back'));
        final screen = tester.element(find.byType(MessagesScreen));
        final android = Theme.of(screen).platform == TargetPlatform.android;
        for (final width in [390.0, 320.0, 280.0, 240.0, 1280.0, 320.0]) {
          tester.view.physicalSize = Size(width, 850);
          for (final textScale in [1.0, 2.0]) {
            scale.value = textScale;
            await tester.pumpAndSettle();
            expect(tester.element(find.byType(MessagesScreen)), same(screen));
            expect(
              find.byKey(const ValueKey('workspace-page-back-header')),
              findsNothing,
            );
            final titleRect = tester.getRect(title);
            for (final action in [
              refresh,
              official,
              if (android && mode != WorkspaceNavigationMode.multipleTabs) back,
            ]) {
              final rect = tester.getRect(action);
              expect(rect.center.dy, closeTo(titleRect.center.dy, .01));
              expect(rect.width, greaterThanOrEqualTo(48));
              expect(rect.height, greaterThanOrEqualTo(48));
              expect(action.hitTestable(), findsOneWidget);
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(width));
            }
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: title, matching: find.byType(RichText)),
            );
            expect(paragraph.maxLines, 1);
            expect(paragraph.overflow, TextOverflow.ellipsis);
            expect(tester.takeException(), isNull);
          }
        }
        final reads = repo.reads;
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(repo.reads, reads + 1);
        await tester.tap(official);
        await tester.pumpAndSettle();
        expect(opened, [Uri.https('message.bilibili.com', '/')]);
        if (mode != WorkspaceNavigationMode.multipleTabs) {
          await tester.tap(find.text('测试会话'));
          await tester.pumpAndSettle();
          expect(
            tester.getCenter(back).dy,
            closeTo(tester.getCenter(title).dy, .01),
          );
          expect(find.byType(TextField), findsOneWidget);
          await tester.enterText(find.byType(TextField), '顶栏返回后保留草稿');
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/messages');
          expect(find.text('测试会话'), findsOneWidget);
          await tester.tap(find.text('测试会话'));
          await tester.pumpAndSettle();
          expect(find.text('顶栏返回后保留草稿'), findsOneWidget);
          await tester.tap(back);
          await tester.pumpAndSettle();
          if (android) {
            await auth.signOut();
            await tester.pumpAndSettle();
            expect(find.text('登录后查看我的消息'), findsOneWidget);
            expect(
              tester.getCenter(back).dy,
              closeTo(tester.getCenter(title).dy, .01),
            );
            await tester.tap(back);
            await tester.pumpAndSettle();
            expect(router.routeInformationProvider.value.uri.path, '/');
          }
        }
        expect(repo.sends, 0);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.windows,
      }),
    );
  }
}
