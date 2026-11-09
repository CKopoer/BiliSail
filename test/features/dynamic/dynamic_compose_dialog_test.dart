import 'dart:async';
import 'dart:convert';

import 'package:bilisail/domain/local_image.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/dynamic/application/dynamic_composer_controller.dart';
import 'package:bilisail/features/dynamic/application/dynamic_topic_controller.dart';
import 'package:bilisail/features/dynamic/presentation/dynamic_topic_screen.dart';
import 'package:bilisail/shared/ui/dynamic_compose_dialog.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_composer_fakes.dart';
import '../../support/dynamic_fakes.dart';
import '../../support/dynamic_topic_fakes.dart';

void main() {
  late DynamicComposerFake repository;
  late DynamicTopicRepositoryFake topic;
  late DynamicAuthFake auth;
  var published = 0, logins = 0;
  setUp(() {
    repository = DynamicComposerFake();
    topic = DynamicTopicRepositoryFake();
    auth = DynamicAuthFake();
    published = 0;
    logins = 0;
  });
  tearDown(() => auth.stream.close());
  Future<void> show(
    WidgetTester tester, {
    double width = 1000,
    double scale = 1,
    bool topicPage = false,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          dynamicComposerRepositoryProvider.overrideWithValue(repository),
          dynamicTopicRepositoryProvider.overrideWithValue(topic),
          dynamicImagePickerProvider.overrideWithValue(
            (_) async => [
              LocalImage(
                base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
                ),
                'image/png',
              ),
            ],
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: AppNoticeHost(child: child!),
          ),
          home: Scaffold(
            body: topicPage
                ? const DynamicTopicScreen(id: '12')
                : Center(
                    child: DynamicComposeButton(
                      onLogin: () => logins++,
                      onPublished: () async {
                        published++;
                      },
                    ),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('dynamic-compose')));
    await tester.pumpAndSettle();
  }

  for (final (width, scale) in [(320.0, 2.0), (1280.0, 1.0)]) {
    testWidgets(
      'compose text, image and topic with no upload before publish at $width/$scale',
      (tester) async {
        await show(tester, width: width, scale: scale);
        await open(tester);
        await tester.enterText(
          find.byKey(const ValueKey('dynamic-compose-text')),
          '分享内容😀',
        );
        await tester.tap(find.byTooltip('添加图片'));
        await tester.pumpAndSettle();
        expect(repository.uploads, isEmpty);
        await tester.tap(find.byTooltip('选择话题'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('测试话题'));
        await tester.pumpAndSettle();
        expect(find.text('#测试话题#'), findsOneWidget);
        expect(repository.drafts, isEmpty);
        await tester.tap(find.byKey(const ValueKey('dynamic-compose-submit')));
        await tester.pumpAndSettle();
        expect(repository.drafts.single.text, '分享内容😀');
        expect(repository.drafts.single.topic?.id, '12');
        expect(repository.uploads, hasLength(1));
        expect(published, 1);
        expect(find.byType(DynamicComposeDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'closing retains one shared draft and account change clears text',
    (tester) async {
      await show(tester);
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('dynamic-compose-text')),
        '保留草稿',
      );
      await tester.tap(find.byTooltip('关闭并保留草稿'));
      await tester.pumpAndSettle();
      await open(tester);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('dynamic-compose-text')),
            )
            .controller!
            .text,
        '保留草稿',
      );
      repository.accountScope = 'user:8';
      repository.sessionEpoch++;
      auth.change(const AuthState(status: AuthStatus.signedIn, mid: '8'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('dynamic-compose-text')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(repository.drafts, isEmpty);
    },
  );

  testWidgets('busy submission disables publish and closing', (tester) async {
    await show(tester);
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('dynamic-compose-text')),
      '等待提交',
    );
    await tester.pump();
    repository.pendingCreate = Completer<String>();
    await tester.tap(find.byKey(const ValueKey('dynamic-compose-submit')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('dynamic-compose-submit')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '关闭并保留草稿',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(repository.drafts, hasLength(1));
    repository.pendingCreate!.complete('123');
    await tester.pumpAndSettle();
    expect(published, 1);
  });

  testWidgets(
    'guest entry requests login without opening or publishing a draft',
    (tester) async {
      auth.current = const AuthState();
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('dynamic-compose')));
      await tester.pumpAndSettle();
      expect(logins, 1);
      expect(find.byType(DynamicComposeDialog), findsNothing);
      expect(repository.drafts, isEmpty);
    },
  );

  testWidgets(
    'participating preselects the current topic and refreshes its posts after publication',
    (tester) async {
      await show(tester, topicPage: true);
      await open(tester);
      expect(find.text('#应用内话题#'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('dynamic-compose-text')),
        '话题新动态',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('dynamic-compose-submit')));
      await tester.pumpAndSettle();
      expect(repository.drafts.single.topic?.id, '12');
      expect(topic.details, hasLength(2));
      expect(topic.queries, hasLength(2));
    },
  );

  testWidgets('topic favorite and native report require explicit actions', (
    tester,
  ) async {
    await show(tester, topicPage: true);
    expect(find.text('发起人 发起'), findsOneWidget);
    expect(topic.favorites, isEmpty);
    expect(topic.reports, isEmpty);
    await tester.tap(find.byKey(const ValueKey('topic-favorite')));
    await tester.pumpAndSettle();
    expect(topic.favorites.single, ('12', true));
    expect(find.text('已收藏 1'), findsOneWidget);
    await tester.tap(find.byTooltip('话题操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('举报'));
    await tester.pumpAndSettle();
    expect(topic.reports, isEmpty);
    await tester.enterText(find.byType(TextField), '示例说明');
    await tester.tap(find.text('提交举报'));
    await tester.pumpAndSettle();
    expect(topic.reports.single, ('12', '话题引战：示例说明'));
    expect(find.text('举报已提交'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
