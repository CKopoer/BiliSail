import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bilisail/app/router.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/article_address.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/content_link.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/article/application/article_provider.dart';
import 'package:bilisail/features/article/domain/article_document.dart';
import 'package:bilisail/features/article/domain/article_repository.dart';
import 'package:bilisail/features/article/presentation/article_action_bar.dart';
import 'package:bilisail/features/article/presentation/article_screen.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/features/dynamic/application/dynamic_actions_controller.dart';
import 'package:bilisail/features/image_viewer/application/image_viewer_controller.dart';
import 'package:bilisail/features/image_viewer/domain/original_image.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/shared/ui/comments_panel.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/gestures.dart';
import 'package:bilisail/shared/ui/content_link_scope.dart';
import 'package:bilisail/shared/ui/dynamic_post_interactions.dart';
import 'package:bilisail/shared/ui/image_viewer.dart';
import 'package:bilisail/shared/ui/post_author_header.dart';
import 'package:bilisail/shared/ui/post_card_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/dynamic_fakes.dart';
import '../../support/input_test_app.dart';
import '../../support/material_tooltip_finder.dart';

const _column = ArticleAddress(ArticleKind.column, '789');
const _commentTarget = CommentTarget('789', CommentTargetType.article);
const _opus = ArticleAddress(ArticleKind.opus, '98765432101234567890');
const _settings = AppSettings.defaults(
  navigationMode: WorkspaceNavigationMode.singlePage,
);

void main() {
  test(
    'validates article destinations without interpreting dynamic IDs as cv IDs',
    () {
      for (final (value, expected) in [
        ('https://www.bilibili.com/read/cv789/?spm=x', _column),
        ('https://m.bilibili.com/mobile/opus/${_opus.id}', _opus),
        ('https://t.bilibili.com/789', null),
        ('https://evil.invalid/read/cv789', null),
        ('https://name@www.bilibili.com/read/cv789', null),
        ('https://www.bilibili.com:444/opus/789', null),
        ('https://www.bilibili.com/read/cv0789', null),
      ]) {
        expect(ArticleAddress.fromWebUri(Uri.parse(value)), expected);
      }
    },
  );

  testWidgets(
    'opens direct links, collections and their articles as retained pages',
    (tester) async {
      final auth = DynamicAuthFake(signedIn: false);
      addTearDown(auth.stream.close);
      final repository = _Repository((address, _) async {
        if (address == _column) {
          return _document(address, '旧文章', '旧文章正文', linkLabel: '阅读新版图文');
        }
        expect(address, _opus);
        return _document(address, '图文作品', '整篇图文正文');
      });
      final router = createBiliRouter(
        initialLocation: _column.location,
        playerBuilder: (_, _, _) => const SizedBox.shrink(),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            articleRepositoryProvider.overrideWithValue(repository),
            authRepositoryProvider.overrideWithValue(auth),
            settingsRepositoryProvider.overrideWithValue(const _Settings()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ArticleScreen), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, _column.location);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('旧文章正文').hitTestable(), findsOneWidget);
      await tester.tap(find.text('示例文集'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/article-list/12',
      );
      expect(find.text('文集目录'), findsOneWidget);
      final first = find.text('第一篇'), second = find.text('第二篇');
      expect(
        tester.getTopLeft(first).dy,
        lessThan(tester.getTopLeft(second).dy),
      );
      await tester.tap(findMaterialTooltip('切换为倒序'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(second).dy,
        lessThan(tester.getTopLeft(first).dy),
      );
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, _opus.location);
      expect(find.text('整篇图文正文').hitTestable(), findsOneWidget);
      await tester.tap(findMaterialTooltip('返回').hitTestable().last);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(second).dy,
        lessThan(tester.getTopLeft(first).dy),
      );
      await tester.tap(findMaterialTooltip('返回').hitTestable().last);
      await tester.pumpAndSettle();
      expect(find.text('旧文章正文').hitTestable(), findsOneWidget);
      await tester.tapAt(
        tester.getTopLeft(find.text('阅读新版图文')) + const Offset(12, 12),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, _opus.location);
      await tester.tap(findMaterialTooltip('返回').hitTestable().last);
      await tester.pumpAndSettle();
      await tester.tap(findMaterialTooltip('返回').hitTestable().last);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(repository.reads, [_column, _opus, _opus]);
    },
  );

  for (final fromFeed in [false, true]) {
    testWidgets(
      'article dynamic renders all body images in order (feed: $fromFeed)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final auth = DynamicAuthFake(signedIn: false);
        addTearDown(auth.stream.close);
        final images = [
          for (var i = 0; i < 6; i++)
            Uri.https('i0.hdslb.com', '/bfs/new_dyn/picture$i.png'),
        ];
        final summary = DynamicPost(
          id: _opus.id,
          text: '只有封面的摘要[图片]',
          articleAddress: _column,
          commentTarget: _commentTarget,
        );
        final dynamics = DynamicRepositoryFake()..loaded = summary;
        final articles = _Repository((address, _) async {
          expect(address, _column);
          return ArticleDocument(
            url: _opus.webUri,
            title: '图文动态',
            commentTarget: _commentTarget,
            blocks: [
              for (final (i, image) in images.indexed) ...[
                ArticleBlock(
                  ArticleBlockKind.paragraph,
                  text: [
                    (
                      text: '第 ${i + 1} 段',
                      link: null,
                      bold: false,
                      italic: false,
                      strike: false,
                    ),
                  ],
                ),
                ArticleBlock(
                  ArticleBlockKind.image,
                  image: image,
                  aspectRatio: 8,
                ),
              ],
            ],
          );
        });
        final router = createBiliRouter(
          initialLocation: '/dynamic/${_opus.id}',
          playerBuilder: (_, _, _) => const SizedBox.shrink(),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              articleRepositoryProvider.overrideWithValue(articles),
              authRepositoryProvider.overrideWithValue(auth),
              dynamicRepositoryProvider.overrideWithValue(dynamics),
              commentsRepositoryProvider.overrideWith(
                (_, _) => DynamicCommentsFake(),
              ),
              settingsRepositoryProvider.overrideWithValue(const _Settings()),
              originalImageRepositoryProvider.overrideWithValue(
                _Originals(
                  OriginalImage(
                    bytes: base64Decode(
                      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGMwCasA'
                      'IgYIBQAbNgQJ4mDIDgAAAABJRU5ErkJggg==',
                    ),
                    width: 2,
                    height: 2,
                  ),
                ),
              ),
            ],
            child: fromFeed
                ? MaterialApp(
                    home: Scaffold(
                      body: InteractiveDynamicPostCard(post: summary),
                    ),
                  )
                : MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        if (fromFeed) {
          expect(find.byType(ArticleScreen), findsNothing);
          await tester.tap(findMaterialTooltip('查看动态详情'));
          await tester.pumpAndSettle();
        }
        expect(articles.reads, [_column]);
        final reader = find.byType(ArticleScreen);
        expect(reader, findsOneWidget);
        expect(
          find.descendant(of: reader, matching: find.text(summary.text)),
          findsNothing,
        );
        final bodyImages = tester
            .widgetList<AppNetworkImage>(
              find.descendant(
                of: reader,
                matching: find.byType(AppNetworkImage),
              ),
            )
            .toList();
        expect(bodyImages.map((widget) => widget.viewerOriginal), images);
        expect(
          bodyImages.map((widget) => widget.fit),
          everyElement(BoxFit.contain),
        );
        for (var i = 1; i <= images.length; i++) {
          expect(
            tester.getTopLeft(find.text('第 $i 段')).dy,
            lessThan(tester.getTopLeft(find.bySemanticsLabel('查看图片 $i')).dy),
          );
        }
        await tester.tap(find.bySemanticsLabel('查看图片 4'));
        await tester.pumpAndSettle();
        final viewer = tester.widget<ImageViewer>(find.byType(ImageViewer));
        expect(viewer.request.images, images);
        expect(viewer.request.initialIndex, 3);
      },
    );
  }

  testWidgets('iOS Back retraces an article dialog comment thread', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = DynamicAuthFake();
    addTearDown(auth.stream.close);
    final comments = DynamicCommentsFake()
      ..items = const [
        CommentEntry(id: '50', author: '读者', message: '一级留言', replyCount: 3),
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          articleRepositoryProvider.overrideWithValue(
            _Repository((_, _) async => _longArticle()),
          ),
          dynamicRepositoryProvider.overrideWithValue(DynamicRepositoryFake()),
          commentsRepositoryProvider.overrideWith((_, _) => comments),
          settingsRepositoryProvider.overrideWithValue(const _Settings()),
        ],
        child: InputTestApp(
          home: Scaffold(
            body: InteractiveDynamicPostCard(
              post: DynamicPost(
                id: '100',
                text: '图文动态',
                commentCount: 1,
                commentTarget: _commentTarget,
                articleAddress: _column,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(findMaterialTooltip('查看评论'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('共 3 条回复 ›'));
    await tester.pumpAndSettle();
    expect(find.text('评论详情'), findsOneWidget);

    await tester.dragFrom(const Offset(5, 300), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(find.text('评论详情'), findsNothing);
    expect(find.text('一级留言').hitTestable(), findsOneWidget);

    await tester.dragFrom(const Offset(5, 300), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(find.text('专栏评论').hitTestable(), findsNothing);
    expect(find.byType(ArticleScreen), findsOneWidget);

    await tester.dragFrom(const Offset(5, 300), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(find.byType(ArticleScreen), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'account transitions cancel older reads and retry uses the current session',
    (tester) async {
      final auth = DynamicAuthFake();
      addTearDown(auth.stream.close);
      final old = Completer<ArticleDocument>();
      final current = Completer<ArticleDocument>();
      final attempts = <RequestCancellation>[];
      var epoch = 0;
      final repository = _Repository((address, cancellation) async {
        attempts.add(cancellation);
        return switch ((epoch, attempts.length)) {
          (0, _) => old.future,
          (1, 2) => current.future,
          _ => _document(address, '当前账号的正文', '完整正文'),
        };
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            articleRepositoryProvider.overrideWithValue(repository),
            authRepositoryProvider.overrideWithValue(auth),
            sessionEpochProvider.overrideWithValue(() => epoch),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ArticleScreen(
                address: _column,
                onOpenUser: (_) {},
                onOpenLink: (_) {},
                onOpenWeb: (_) {},
                onLogin: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('正在加载专栏…'), findsOneWidget);
      epoch++;
      auth.change(const AuthState(status: AuthStatus.guest));
      await tester.pump();
      expect(attempts.first.isCancelled, isTrue);
      old.complete(_document(_column, '旧账号的专栏', '旧账号内容'));
      current.completeError(
        const AppFailure(AppFailureKind.notFound, '专栏不存在或已被删除'),
      );
      await tester.pumpAndSettle();
      expect(find.text('旧账号内容'), findsNothing);
      expect(find.text('专栏不存在或已被删除'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('完整正文'), findsOneWidget);
    },
  );

  testWidgets(
    'consecutive identical article paragraphs keep their individual heights',
    (tester) async {
      const multiline = '第一行\n第二行\n第三行\n第四行';
      final blocks = [
        for (final words in ['\n', '\n', '重复正文', '重复正文', multiline, '文末'])
          ArticleBlock(
            ArticleBlockKind.paragraph,
            text: [
              (
                text: words,
                link: null,
                bold: false,
                italic: false,
                strike: false,
              ),
            ],
          ),
      ];
      await _mountReader(
        tester,
        comments: DynamicCommentsFake(),
        document: ArticleDocument(
          url: _opus.webUri,
          title: '图文',
          blocks: blocks,
        ),
        address: _opus,
      );

      final blanks = find.text('\n');
      final repeated = find.text('重复正文');
      expect(blanks, findsNWidgets(2));
      expect(repeated, findsNWidgets(2));
      expect(tester.getSize(blanks.first).height, greaterThan(0));
      expect(
        tester.getSize(blanks.last).height,
        tester.getSize(blanks.first).height,
      );
      expect(
        tester.getSize(repeated.last).height,
        tester.getSize(repeated.first).height,
      );
      expect(
        tester.getSize(find.text(multiline)).height,
        greaterThan(tester.getSize(repeated.first).height),
      );
      final paragraphs = [
        blanks.first,
        blanks.last,
        repeated.first,
        repeated.last,
        find.text(multiline),
        find.text('文末'),
      ];
      for (var i = 1; i < paragraphs.length; i++) {
        expect(
          tester.getTopLeft(paragraphs[i]).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(paragraphs[i - 1]).dy),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mouse thumb keeps a stable mapping across short and long article blocks',
    (tester) async {
      final blocks = List.generate(
        200,
        (i) => ArticleBlock(
          ArticleBlockKind.paragraph,
          text: [
            (
              text: List.filled(i % 80 < 30 ? 1 : 15, '正文第 $i 段').join('\n'),
              link: null,
              bold: false,
              italic: false,
              strike: false,
            ),
          ],
        ),
      );
      await _mountReader(
        tester,
        comments: DynamicCommentsFake(),
        document: ArticleDocument(
          url: _column.webUri,
          title: '文章',
          blocks: blocks,
          commentTarget: _commentTarget,
        ),
      );
      final reader = find.byKey(const PageStorageKey('article-reading'));
      final position = tester
          .widget<CustomScrollView>(reader)
          .controller!
          .position;
      final scrollbar = find
          .ancestor(of: reader, matching: find.byType(Scrollbar))
          .first;
      final painter = _scrollbarPainter(tester, scrollbar);
      final extent = position.maxScrollExtent;
      final viewport = position.viewportDimension;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final start = tester.getTopRight(reader) + const Offset(-5, 10);
      await mouse.addPointer(location: start);
      await tester.pumpAndSettle();
      await mouse.down(start);
      await tester.pump();
      expect(position.pixels, 0);
      for (final dy in [70.0, 120.0, 130.0, -60.0, -40.0]) {
        final before = position.pixels;
        final thumbBefore = painter.getThumbScrollOffset();
        await mouse.moveBy(Offset(0, dy));
        await tester.pumpAndSettle();
        expect(
          position.pixels,
          dy > 0 ? greaterThan(before) : lessThan(before),
        );
        expect(position.maxScrollExtent, closeTo(extent, .01));
        expect(position.viewportDimension, viewport);
        expect(painter.getThumbScrollOffset() - thumbBefore, closeTo(dy, 1));
      }
      await mouse.up();
      await mouse.removePointer();
    },
  );

  testWidgets(
    'wide article scrolls independently and keeps comments on resize',
    (tester) async {
      final comments = DynamicCommentsFake()
        ..items = [
          for (var i = 0; i < 60; i++)
            CommentEntry(id: '${i + 1}', author: '读者', message: '读者留言 $i'),
        ];
      await _mountReader(tester, comments: comments, document: _longArticle());
      final reading = find.byKey(const PageStorageKey('article-reading'));
      final view = tester.widget<CustomScrollView>(reading);
      final panel = find.byType(CommentsPanel, skipOffstage: false);
      final panelState = tester.state(panel);
      final rightList = find.descendant(
        of: panel,
        matching: find.byType(ListView),
      );
      final commentScroll = tester.widget<ListView>(rightList).controller!;
      final footer = find.byType(ArticleActionBar);
      final articleRect = tester.getRect(reading);
      final panelRect = tester.getRect(panel);
      expect(tester.getRect(footer).left, articleRect.left);
      expect(tester.getRect(footer).right, articleRect.right);
      expect(panelRect.bottom, articleRect.bottom);
      expect(tester.getRect(reading).right, tester.getRect(panel).left);
      expect(tester.widget<CommentsPanel>(panel).target, _commentTarget);
      expect(tester.widget<CommentsPanel>(panel).replyCount, 60);
      expect(find.text('正文第 239 段'), findsNothing);
      await tester.drag(reading, const Offset(0, -520));
      await tester.pumpAndSettle();
      expect(findMaterialTooltip('评论').hitTestable(), findsNothing);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(reading),
          scrollDelta: const Offset(0, -65),
        ),
      );
      await tester.pumpAndSettle();
      expect(findMaterialTooltip('评论').hitTestable(), findsOneWidget);
      final readingOffset = view.controller!.offset;
      expect(readingOffset, greaterThan(280));
      expect(commentScroll.offset, 0);

      await tester.drag(panel, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(commentScroll.offset, greaterThan(200));
      expect(view.controller!.offset, readingOffset);
      final commentOffset = commentScroll.offset;

      await tester.binding.setSurfaceSize(const Size(390, 750));
      await tester.pumpAndSettle();
      expect(tester.state(panel), same(panelState));
      expect(view.controller!.offset, closeTo(readingOffset, 1));
      expect(find.text('最热').hitTestable(), findsNothing);
      await tester.tap(findMaterialTooltip('评论').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('专栏评论').hitTestable(), findsOneWidget);
      expect(tester.state(panel), same(panelState));
      expect(commentScroll.offset, closeTo(commentOffset, 1));
      await tester.binding.setSurfaceSize(const Size(1280, 750));
      await tester.pumpAndSettle();
      expect(tester.getRect(panel), panelRect);
      expect(tester.getRect(reading), articleRect);
      expect(commentScroll.offset, closeTo(commentOffset, 1));
      await tester.tap(findMaterialTooltip('评论').hitTestable());
      await tester.pumpAndSettle();
      expect(commentScroll.offset, 0);
      expect(view.controller!.offset, closeTo(readingOffset, 1));
      expect(comments.reads, [_commentTarget.oid]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 1.25]) {
    testWidgets(
      'wide article resizes within 30 to 70 percent at scale $scale',
      (tester) async {
        final comments = DynamicCommentsFake()
          ..items = const [CommentEntry(id: '1', author: '读者', message: '留言')];
        await _mountReader(
          tester,
          size: const Size(900, 750),
          scale: scale,
          comments: comments,
          document: _longArticle(paragraphs: 20),
        );
        final reading = find.byKey(const PageStorageKey('article-reading'));
        final panel = find.byType(CommentsPanel);
        final panelState = tester.state(panel);
        final control = findMaterialTooltip('调节专栏与评论宽度');
        final slider = find.byType(Slider);

        void expectWidths(double articleWidth, double commentsWidth) {
          expect(tester.getSize(reading).width, closeTo(articleWidth, .001));
          expect(tester.getSize(panel).width, closeTo(commentsWidth, .001));
          expect(tester.getRect(reading).right, tester.getRect(panel).left);
          expect(tester.state(panel), same(panelState));
          expect(tester.takeException(), isNull);
        }

        expectWidths(486, 414);
        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(find.text('专栏 54% · 评论 46%'), findsOneWidget);

        final drag = await tester.startGesture(
          tester.getCenter(slider),
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveBy(const Offset(-220, 0));
        await tester.pumpAndSettle();
        expectWidths(270, 630);
        expect(find.text('专栏 30% · 评论 70%'), findsOneWidget);
        await drag.moveBy(const Offset(440, 0));
        await tester.pumpAndSettle();
        expectWidths(630, 270);
        expect(find.text('专栏 70% · 评论 30%'), findsOneWidget);
        await drag.up();
        expect(find.text('最热'), findsOneWidget);
        final latest = tester.getCenter(find.text('最新'));
        final refresh = tester.getCenter(findMaterialTooltip('刷新评论'));
        expect(latest.dy, closeTo(refresh.dy, 2));

        await tester.binding.setSurfaceSize(const Size(390, 750));
        await tester.pumpAndSettle();
        expect(control, findsNothing);
        expect(slider, findsNothing);
        expect(tester.getSize(reading).width, 390);

        await tester.binding.setSurfaceSize(const Size(1280, 750));
        await tester.pumpAndSettle();
        expectWidths(896, 384);
        expect(comments.reads, [_commentTarget.oid]);
      },
    );
  }

  testWidgets(
    'article width is saved on release and restored for a new reader',
    (tester) async {
      final settings = _WritableSettings();
      final comments = DynamicCommentsFake();
      await _mountReader(
        tester,
        size: const Size(900, 750),
        settings: settings,
        comments: comments,
        document: _longArticle(paragraphs: 1),
      );
      final control = findMaterialTooltip('调节专栏与评论宽度');
      final slider = find.byType(Slider);
      final reading = find.byKey(const PageStorageKey('article-reading'));
      await tester.tap(control);
      await tester.pumpAndSettle();
      final drag = await tester.startGesture(tester.getCenter(slider));
      await drag.moveBy(const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(reading).width, closeTo(630, .001));
      expect(settings.writes, isEmpty);
      await drag.up();
      await tester.pumpAndSettle();
      expect(settings.writes, [.7]);

      await tester.pumpWidget(const SizedBox.shrink());
      await _mountReader(
        tester,
        address: _opus,
        settings: settings,
        comments: comments,
        document: _document(_opus, '另一篇专栏', '正文'),
      );
      expect(find.text('另一篇专栏'), findsOneWidget);
      expect(tester.getSize(reading).width, closeTo(896, .001));
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(find.text('专栏 70% · 评论 30%'), findsOneWidget);

      settings.fail = true;
      await tester.drag(slider, const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(reading).width, closeTo(896, .001));
      expect(settings.writes, [.7]);
      expect(find.text('分栏比例保存失败，请重试'), findsOneWidget);
    },
  );

  testWidgets(
    'narrow article shows persistent progress and opens comments on demand',
    (tester) async {
      final comments = DynamicCommentsFake()..items = [];
      await _mountReader(
        tester,
        size: const Size(390, 750),
        platform: TargetPlatform.android,
        comments: comments,
        document: _longArticle(),
      );
      final action = findMaterialTooltip('评论').hitTestable();
      final reading = find.byKey(const PageStorageKey('article-reading'));
      final scrollbar = tester.widget<Scrollbar>(
        find.ancestor(of: reading, matching: find.byType(Scrollbar)).first,
      );
      expect(scrollbar.thumbVisibility, isTrue);
      expect(scrollbar.scrollbarOrientation, ScrollbarOrientation.right);
      final position = tester
          .widget<CustomScrollView>(reading)
          .controller!
          .position;
      expect(scrollbar.controller!.position, same(position));
      final painter = _scrollbarPainter(tester, find.byWidget(scrollbar));
      final thumbTop = Offset(tester.getSize(reading).width - 5, 10);
      expect(
        painter.hitTestOnlyThumbInteractive(thumbTop, PointerDeviceKind.mouse),
        isTrue,
      );
      expect(action, findsOneWidget);
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('正文第 239 段').hitTestable(), findsOneWidget);
      expect(
        painter.hitTestOnlyThumbInteractive(thumbTop, PointerDeviceKind.mouse),
        isFalse,
      );
      expect(
        painter.getThumbScrollOffset(),
        greaterThan(position.viewportDimension * .7),
      );
      expect(find.byType(CommentsPanel, skipOffstage: false), findsNothing);
      expect(comments.reads, isEmpty);
      expect(action, findsNothing);
      await tester.drag(reading, const Offset(0, 120));
      await tester.pumpAndSettle();
      final offset = position.pixels;
      expect(offset, greaterThan(0));
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('专栏评论').hitTestable(), findsOneWidget);
      expect(find.text('最热').hitTestable(), findsOneWidget);
      expect(find.byType(ArticleActionBar), findsNothing);
      await tester.tap(findMaterialTooltip('返回'));
      await tester.pumpAndSettle();
      expect(position.pixels, offset);
      expect(action, findsOneWidget);
      expect(comments.reads, [_commentTarget.oid]);
    },
  );

  testWidgets(
    'favorite uses the resolved CV address and dynamic actions use the post ID',
    (tester) async {
      final document = ArticleDocument(
        url: _column.webUri,
        title: '旧专栏',
        blocks: const [],
        dynamicId: _opus.id,
        stats: const ArticleStats(liked: false, favorited: false, favorites: 8),
      );
      final articles = _Repository((_, _) async => document);
      final dynamics = DynamicRepositoryFake();
      final auth = DynamicAuthFake();
      addTearDown(auth.stream.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            articleRepositoryProvider.overrideWithValue(articles),
            authRepositoryProvider.overrideWithValue(auth),
            dynamicRepositoryProvider.overrideWithValue(dynamics),
          ],
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: Scaffold(
              body: ArticleScreen(
                address: _opus,
                onOpenUser: (_) {},
                onOpenLink: (_) {},
                onOpenWeb: (_) {},
                onLogin: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      articles.pending = Completer<void>();
      await tester.tap(findMaterialTooltip('收藏'));
      await tester.tap(findMaterialTooltip('收藏'));
      await tester.pump();
      expect(articles.writes, [(_column, true)]);
      articles.pending!.complete();
      await tester.pumpAndSettle();
      expect(findMaterialTooltip('取消收藏'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      await tester.tap(findMaterialTooltip('点赞'));
      await tester.pumpAndSettle();
      expect(dynamics.likes, [(_opus.id, true)]);
      await tester.tap(findMaterialTooltip('转发'));
      await tester.pumpAndSettle();
      expect(dynamics.reposts, isEmpty);
      await tester.enterText(find.byType(TextField), '推荐阅读');
      await tester.tap(find.text('转发动态'));
      await tester.pumpAndSettle();
      expect(dynamics.reposts, [(_opus.id, '推荐阅读')]);
    },
  );

  test('favorite locks uncertain writes and discards a previous session completion', () async {
    final auth = DynamicAuthFake();
    addTearDown(auth.stream.close);
    final articles = _Repository((_, _) async => _longArticle());
    var epoch = 0;
    final container = ProviderContainer.test(
      overrides: [
        articleRepositoryProvider.overrideWithValue(articles),
        authRepositoryProvider.overrideWithValue(auth),
        sessionEpochProvider.overrideWithValue(() => epoch),
      ],
    );
    final provider = articleFavoriteProvider(_column);
    container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    articles.pending = Completer<void>();
    final result = controller.toggle(false, 4);
    articles.pending!.completeError(
      const AppFailure(AppFailureKind.timeout, '超时'),
    );
    expect(await result, contains('未确认'));
    expect(container.read(provider).uncertain, isTrue);
    await controller.toggle(false, 4);
    expect(articles.writes, hasLength(1));

    container.invalidate(provider);
    articles.pending = Completer<void>();
    final retry = container.read(provider.notifier).toggle(false, 4);
    epoch++;
    auth.change(const AuthState(status: AuthStatus.guest));
    expect(container.read(provider).favorite, isNull);
    articles.pending!.complete();
    expect(await retry, isNull);
    expect(container.read(provider).favorite, isNull);
    expect(articles.lastWrite!.isCancelled, isTrue);
  });

  testWidgets(
    'enlarged text uses the full width for both article and comments',
    (tester) async {
      UserId? openedAuthor;
      Uri? openedUrl;
      await _mountReader(
        tester,
        comments: DynamicCommentsFake()..items = [],
        document: _longArticle(paragraphs: 1, commentCount: 0),
        size: const Size(960, 820),
        scale: 2,
        onOpenUser: (id) => openedAuthor = id,
        onOpenWeb: (url) => openedUrl = url,
      );
      final card = find.byType(PostCardSurface);
      final author = find.byType(PostAuthorHeader);
      final title = find.text('专栏标题');
      final text = find.text('正文第 0 段');
      final panel = find.byType(CommentsPanel);
      expect(find.byType(Dialog), findsNothing);
      expect(find.descendant(of: card, matching: author), findsOneWidget);
      expect(
        tester.getBottomLeft(author).dy,
        lessThan(tester.getTopLeft(title).dy),
      );
      expect(text.hitTestable(), findsOneWidget);
      expect(panel, findsNothing);
      await tester.tap(findMaterialTooltip('评论'));
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, 960);
      await tester.tap(findMaterialTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('专栏作者'));
      expect(openedAuthor, const UserId('42'));
      await tester.tap(find.byIcon(Icons.open_in_new_outlined));
      expect(openedUrl, _column.webUri);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('guests can see empty comments and open login', (tester) async {
    var logins = 0;
    final comments = DynamicCommentsFake()..items = [];
    await _mountReader(
      tester,
      comments: comments,
      document: _longArticle(paragraphs: 1, commentCount: 0),
      onLogin: () => logins++,
    );
    expect(find.text('还没有评论，来聊聊吧'), findsOneWidget);
    expect(find.text('登录后参与评论'), findsOneWidget);
    await tester.tap(find.byType(TextField));
    expect(logins, 1);
    expect(comments.reads, [_commentTarget.oid]);
    expect(comments.writes, isEmpty);
  });

  testWidgets(
    'article loads a resized preview and opens the original in the viewer',
    (tester) async {
      final source = Uri.https('i0.hdslb.com', '/bfs/new_dyn/article.png');
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGMwCasA'
        'IgYIBQAbNgQJ4mDIDgAAAABJRU5ErkJggg==',
      );
      final previews = <Uri>[];
      final originals = _Originals(
        OriginalImage(bytes: bytes, width: 2, height: 2),
      );
      final cache = AppImageCache(
        ImageByteCache(
          directory: () async => throw const FileSystemException('optional'),
          loader: (uri, _) async {
            previews.add(uri);
            return bytes;
          },
        ),
      );
      try {
        await _mountReader(
          tester,
          comments: DynamicCommentsFake(),
          document: ArticleDocument(
            url: _column.webUri,
            title: '图文',
            blocks: [ArticleBlock(ArticleBlockKind.image, image: source)],
          ),
          imageCache: cache,
          originals: originals,
        );
        final pixels = find.descendant(
          of: find.byType(AppNetworkImage),
          matching: find.byType(RawImage),
        );
        for (
          var attempt = 0;
          attempt < 40 &&
              !tester
                  .widgetList<RawImage>(pixels)
                  .any((raw) => raw.image != null);
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(tester.widget<RawImage>(pixels).image, isNotNull);
        expect(previews, [Uri.parse('$source@1280w_1280h_0e.webp')]);
        await tester.tap(find.bySemanticsLabel('查看图片 1'));
        await tester.pumpAndSettle();
        final viewer = tester.widget<ImageViewer>(find.byType(ImageViewer));
        expect(viewer.request.images, [source]);
        expect(viewer.request.initialIndex, 0);
        expect(originals.sources, isEmpty);
        await tester.tap(find.text('查看原图'));
        await tester.pumpAndSettle();
        expect(originals.sources, [source]);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await cache.close();
      }
    },
  );

  for (final accessMessage in [null, '仅粉丝可见']) {
    testWidgets(
      'closed or restricted articles do not load comments ($accessMessage)',
      (tester) async {
        final comments = DynamicCommentsFake();
        await _mountReader(
          tester,
          comments: comments,
          document: _longArticle(
            paragraphs: 1,
            accessMessage: accessMessage,
            commentForbidden: true,
          ),
        );
        expect(find.byType(CommentsPanel), findsNothing);
        expect(find.text(accessMessage ?? '该专栏已关闭评论'), findsOneWidget);
        expect(
          findMaterialTooltip('调节专栏与评论宽度'),
          accessMessage == null ? findsOneWidget : findsNothing,
        );
        expect(comments.reads, isEmpty);
      },
    );
  }

  testWidgets('narrow long article reaches repeated comment links', (
    tester,
  ) async {
    final repository = _LocatedComments();
    final link = ValueNotifier(
      const ContentLink(comment: CommentLocation('50'), requestId: '1'),
    );
    addTearDown(link.dispose);
    await _mountReader(
      tester,
      comments: repository,
      document: _longArticle(),
      size: const Size(390, 750),
      scale: 1.8,
      link: link,
    );
    final target = find.text('锚点目标楼层').hitTestable();
    expect(target, findsOneWidget);
    await tester.tap(findMaterialTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('最热').hitTestable(), findsOneWidget);
    await tester.tap(findMaterialTooltip('返回'));
    await tester.pumpAndSettle();
    expect(target, findsNothing);
    link.value = const ContentLink(
      comment: CommentLocation('50'),
      requestId: '2',
    );
    await tester.pumpAndSettle();
    expect(target, findsOneWidget);
    expect(repository.locations, [
      const CommentLocation('50'),
      const CommentLocation('50'),
    ]);
    expect(tester.takeException(), isNull);
  });
}

ScrollbarPainter _scrollbarPainter(WidgetTester tester, Finder scrollbar) =>
    tester
        .widgetList<CustomPaint>(
          find.descendant(of: scrollbar, matching: find.byType(CustomPaint)),
        )
        .map((paint) => paint.foregroundPainter)
        .whereType<ScrollbarPainter>()
        .single;

Future<void> _mountReader(
  WidgetTester tester, {
  required CommentsRepository comments,
  required ArticleDocument document,
  ArticleAddress address = _column,
  SettingsRepository settings = const _Settings(),
  Size size = const Size(1280, 750),
  TargetPlatform platform = TargetPlatform.windows,
  double scale = 1,
  ValueNotifier<ContentLink>? link,
  VoidCallback? onLogin,
  ValueChanged<UserId>? onOpenUser,
  ValueChanged<Uri>? onOpenWeb,
  AppImageCache? imageCache,
  OriginalImageRepository? originals,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = DynamicAuthFake(signedIn: false);
  addTearDown(auth.stream.close);
  final reader = ArticleScreen(
    address: address,
    onOpenUser: onOpenUser ?? (_) {},
    onOpenLink: (_) {},
    onOpenWeb: onOpenWeb ?? (_) {},
    onLogin: onLogin ?? () {},
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        articleRepositoryProvider.overrideWithValue(
          _Repository((_, _) async => document),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        settingsRepositoryProvider.overrideWithValue(settings),
        if (originals != null)
          originalImageRepositoryProvider.overrideWithValue(originals),
        commentsRepositoryProvider(CommentTargetType.article)
            .overrideWithValue(comments),
      ],
      child: MaterialApp(
        theme: ThemeData(
          platform: platform,
          scrollbarTheme: const ScrollbarThemeData(
            thumbVisibility: WidgetStatePropertyAll(true),
            thickness: WidgetStatePropertyAll(10),
            mainAxisMargin: 0,
            crossAxisMargin: 0,
            minThumbLength: 18,
          ),
        ),
        builder: (context, child) => AppNoticeHost(
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: imageCache == null
                ? child!
                : AppImageCacheScope(cache: imageCache, child: child!),
          ),
        ),
        home: Scaffold(
          body: link == null
              ? reader
              : ValueListenableBuilder(
                  valueListenable: link,
                  builder: (_, link, child) =>
                      ContentLinkScope(link: link, child: child!),
                  child: reader,
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _Originals implements OriginalImageRepository {
  _Originals(this.image);
  final OriginalImage image;
  final sources = <Uri>[];

  @override
  Future<OriginalImage> load(
    Uri source,
    RequestCancellation cancellation,
  ) async {
    sources.add(source);
    return image;
  }
}

ArticleDocument _longArticle({
  int paragraphs = 240,
  int commentCount = 60,
  String? accessMessage,
  bool commentForbidden = false,
}) => ArticleDocument(
  url: _column.webUri,
  title: '专栏标题',
  author: '专栏作者',
  authorId: const UserId('42'),
  publishedAt: DateTime(2026, 11, 20),
  blocks: List.generate(
    paragraphs,
    (index) => ArticleBlock(
      ArticleBlockKind.paragraph,
      text: [
        (
          text: index % 6 == 4 ? '正文第 $index 段\n多行专栏正文\n末行' : '正文第 $index 段',
          link: null,
          bold: false,
          italic: false,
          strike: false,
        ),
      ],
    ),
  ),
  commentTarget: _commentTarget,
  commentCount: commentCount,
  commentForbidden: commentForbidden,
  accessMessage: accessMessage,
);

ArticleDocument _document(
  ArticleAddress address,
  String title,
  String text, {
  String? linkLabel,
}) => ArticleDocument(
  url: address.webUri,
  title: title,
  collection: linkLabel == null
      ? null
      : const (id: ArticleCollectionId('12'), name: '示例文集', count: '2篇'),
  blocks: [
    ArticleBlock(
      ArticleBlockKind.paragraph,
      text: [
        (text: text, link: null, bold: false, italic: false, strike: false),
      ],
    ),
    if (linkLabel != null)
      ArticleBlock(
        ArticleBlockKind.paragraph,
        text: [
          (
            text: linkLabel,
            link: _opus.webUri,
            bold: false,
            italic: false,
            strike: false,
          ),
        ],
      ),
  ],
);

final class _Settings implements SettingsRepository {
  const _Settings();

  @override
  Future<AppSettings> load() async => _settings;
  @override
  Future<void> save(AppSettings settings) async {}
}

final class _WritableSettings implements SettingsRepository {
  AppSettings _saved = _settings;
  final writes = <double?>[];
  bool fail = false;

  @override
  Future<AppSettings> load() async => _saved;

  @override
  Future<void> save(AppSettings settings) async {
    if (fail) throw StateError('save failed');
    _saved = settings;
    writes.add(settings.responsiveLayout.articleWidthFraction);
  }
}

final class _Repository extends Fake implements ArticleRepository {
  final writes = <(ArticleAddress, bool)>[];
  Completer<void>? pending;
  RequestCancellation? lastWrite;

  @override
  Future<void> setFavorite(
    ArticleAddress address,
    bool favorite,
    RequestCancellation cancellation,
  ) async {
    lastWrite = cancellation;
    writes.add((address, favorite));
    await pending?.future;
  }

  @override
  Future<ArticleStats> viewInfo(
    String cvId,
    RequestCancellation cancellation,
  ) async => const ArticleStats();

  @override
  Future<ArticleCollection> collection(
    ArticleCollectionId id,
    RequestCancellation cancellation,
  ) async {
    expect(id.value, '12');
    return const ArticleCollection(
      name: '文集目录',
      author: '作者',
      entries: [
        (address: _column, title: '第一篇', summary: '', cover: null, views: 1),
        (address: _opus, title: '第二篇', summary: '', cover: null, views: 2),
      ],
    );
  }

  _Repository(this.load);
  final Future<ArticleDocument> Function(ArticleAddress, RequestCancellation)
  load;
  final reads = <ArticleAddress>[];

  @override
  Future<ArticleDocument> read(
    ArticleAddress address,
    RequestCancellation cancellation,
  ) {
    reads.add(address);
    return load(address, cancellation);
  }
}

final class _LocatedComments
    implements CommentsRepository, CommentLocationRepository {
  final locations = <CommentLocation>[];

  @override
  String get accountScope => 'guest';

  @override
  int get sessionEpoch => 0;

  @override
  Future<CommentPage> load(
    String oid,
    int page,
    CommentSort sort,
    RequestCancellation cancellation, {
    String? cursor,
  }) async => const CommentPage(items: [], hasMore: false);

  @override
  Future<LocatedCommentThread> locate(
    String oid,
    CommentLocation location,
    RequestCancellation cancellation,
  ) async {
    locations.add(location);
    return const LocatedCommentThread(
      root: CommentEntry(id: '50', author: '读者', message: '锚点目标楼层'),
      page: CommentPage(items: [], hasMore: false),
      pageNumber: 1,
    );
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
