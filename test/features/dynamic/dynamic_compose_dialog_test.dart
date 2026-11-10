import 'dart:async';
import 'dart:convert';

import 'package:bilisail/domain/local_image.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_draft.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/dynamic/application/dynamic_composer_controller.dart';
import 'package:bilisail/features/dynamic/application/dynamic_topic_controller.dart';
import 'package:bilisail/features/dynamic/presentation/dynamic_topic_screen.dart';
import 'package:bilisail/shared/ui/dynamic_compose_dialog.dart';
import 'package:bilisail/shared/ui/dynamic_publish_forms.dart';
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
    double height = 800,
    double keyboard = 0,
    bool dark = false,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
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
          theme: dark ? BiliTheme.dark() : BiliTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
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

  testWidgets(
    'Bili emotes replace the selection and publish as type 9 alongside identified mentions',
    (tester) async {
      await show(tester);
      await open(tester);
      final field = find.byKey(const ValueKey('dynamic-compose-text'));
      await tester.enterText(field, '前替换后');
      tester.widget<TextField>(field).controller!.selection =
          const TextSelection(baseOffset: 1, extentOffset: 3);
      await tester.tap(find.byTooltip('插入表情'));
      await tester.pumpAndSettle();
      expect(find.text('B站表情'), findsOneWidget);
      expect(find.text('小黄脸'), findsOneWidget);
      await tester.tap(find.text('[doge]'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '前[doge]后');
      await tester.tap(find.byTooltip('@用户'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试用户'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dynamic-compose-submit')));
      await tester.pumpAndSettle();
      expect(repository.drafts.single.text, '前[doge]@测试用户后');
      expect(repository.drafts.single.spans.map((s) => (s.kind, s.id)), [
        (DynamicTextKind.emote, ''),
        (DynamicTextKind.mention, '9007199254740993123'),
      ]);
    },
  );

  testWidgets(
    'emote load failure retries without discarding text or using Unicode substitutes',
    (tester) async {
      var attempts = 0;
      repository.onEmotes = (_) async {
        if (++attempts == 1) throw StateError('offline');
        return const [
          DynamicEmotePackage('小黄脸', [DynamicEmote('[微笑]', null)]),
        ];
      };
      await show(tester);
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('dynamic-compose-text')),
        '保留',
      );
      await tester.tap(find.byTooltip('插入表情'));
      await tester.pumpAndSettle();
      expect(find.text('表情加载失败，请重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('[微笑]'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('dynamic-compose-text')),
            )
            .controller!
            .text,
        '保留[微笑]',
      );
      expect(repository.drafts, isEmpty);
    },
  );

  for (final (size, scale, keyboard) in [
    (const Size(320, 568), 2.0, 200.0),
    (const Size(844, 390), 1.3, 140.0),
    (const Size(768, 1024), 1.5, 0.0),
    (const Size(1440, 900), 1.0, 0.0),
  ]) {
    testWidgets(
      'publishing and pickers fit $size at scale $scale with keyboard $keyboard',
      (tester) async {
        await show(
          tester,
          width: size.width,
          height: size.height,
          scale: scale,
          keyboard: keyboard,
          dark: size.width == 1440,
        );
        await open(tester);
        await tester.enterText(
          find.byKey(const ValueKey('dynamic-compose-text')),
          '自适应编辑',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final submit = tester.getRect(
          find.byKey(const ValueKey('dynamic-compose-submit')),
        );
        expect(submit.bottom, lessThanOrEqualTo(size.height - keyboard));
        for (final tooltip in ['插入表情', '@用户', '选择话题', '投票', '直播预约']) {
          await tester.tap(find.byTooltip(tooltip));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(
            tooltip == '插入表情' ? find.text('关闭') : find.byTooltip('关闭'),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('dynamic-compose-submit')));
        await tester.pumpAndSettle();
        expect(repository.drafts.single.text, '自适应编辑');
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.all(),
    );
  }

  testWidgets(
    'poll, reservation, title and reply settings remain local until explicit publication',
    (tester) async {
      await show(tester);
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('dynamic-compose-title')),
        '新标题',
      );
      await tester.tap(find.byTooltip('投票'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('dynamic-poll-title')),
        '选哪个',
      );
      await tester.enterText(
        find.byKey(const ValueKey('dynamic-poll-option-0')),
        '一',
      );
      await tester.enterText(
        find.byKey(const ValueKey('dynamic-poll-option-1')),
        '二',
      );
      await tester.tap(find.text('保存投票'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('直播预约'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('dynamic-reserve-title')),
        '一起看直播',
      );
      await tester.tap(find.text('保存预约'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('评论权限'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('评论权限'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('精选评论'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('可见范围'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('仅自己可见'));
      await tester.pumpAndSettle();
      expect(repository.polls, isEmpty);
      expect(repository.reserves, isEmpty);
      await tester.tap(find.byKey(const ValueKey('dynamic-compose-submit')));
      await tester.pumpAndSettle();
      expect(repository.polls.single.title, '选哪个');
      expect(repository.reserves.single.title, '一起看直播');
      expect(repository.drafts.single.title, '新标题');
      expect(
        repository.drafts.single.options.replyPolicy,
        DynamicReplyPolicy.selected,
      );
      expect(repository.drafts.single.options.onlySelf, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scheduling stays in the owning navigator and survives reopening the draft',
    (tester) async {
      await show(tester);
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('dynamic-compose-text')),
        '定时内容',
      );
      await tester.ensureVisible(find.text('定时发布'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('定时发布'));
      await tester.pumpAndSettle();
      expect(find.byType(DynamicDateTimePicker), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dynamic-time-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭并保留草稿'));
      await tester.pumpAndSettle();
      await open(tester);
      expect(find.widgetWithText(FilledButton, '定时发布'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dynamic-compose-submit')));
      await tester.pumpAndSettle();
      expect(repository.drafts.single.options.publishAt, isNotNull);
      expect(repository.drafts.single.options.onlySelf, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (size, scale, keyboard) in [
    (const Size(320, 568), 2.0, 200.0),
    (const Size(844, 390), 1.3, 140.0),
  ]) {
    testWidgets('date and time selection fit short viewport $size', (
      tester,
    ) async {
      await show(
        tester,
        width: size.width,
        height: size.height,
        scale: scale,
        keyboard: keyboard,
      );
      await open(tester);
      await tester.scrollUntilVisible(
        find.text('定时发布'),
        100,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('dynamic-compose-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('定时发布'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final confirm = find.byKey(const ValueKey('dynamic-time-confirm'));
      expect(
        tester.getRect(confirm).bottom,
        lessThanOrEqualTo(size.height - keyboard),
      );
      expect(confirm.hitTestable(), findsOneWidget);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byType(DynamicDateTimePicker), findsNothing);
      expect(tester.takeException(), isNull);
    });
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
    expect(find.byKey(const ValueKey('topic-favorite')), findsNothing);
    await tester.tap(find.byTooltip('话题操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(topic.favorites.single, ('12', true));
    await tester.tap(find.byTooltip('话题操作'));
    await tester.pumpAndSettle();
    expect(find.text('取消收藏'), findsOneWidget);
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
