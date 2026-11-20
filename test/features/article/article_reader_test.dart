import 'dart:async';

import 'package:bilisail/app/router.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/article_address.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/content_link.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/article/application/article_provider.dart';
import 'package:bilisail/features/article/domain/article_document.dart';
import 'package:bilisail/features/article/domain/article_repository.dart';
import 'package:bilisail/features/article/presentation/article_screen.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/shared/ui/comments_panel.dart';
import 'package:bilisail/shared/ui/content_detail_page.dart';
import 'package:bilisail/shared/ui/content_link_scope.dart';
import 'package:bilisail/shared/ui/post_author_header.dart';
import 'package:bilisail/shared/ui/post_card_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/dynamic_fakes.dart';

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

  testWidgets('opens cv and opus bodies in their own workspace and returns', (
    tester,
  ) async {
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
    expect(find.text('旧文章正文'), findsOneWidget);
    await tester.tapAt(
      tester.getTopLeft(find.text('阅读新版图文')) + const Offset(12, 12),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, _opus.location);
    expect(find.text('整篇图文正文'), findsOneWidget);
    expect(find.text('旧文章正文'), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, _column.location);
    expect(find.text('旧文章正文'), findsOneWidget);
    expect(repository.reads, [_column, _opus]);
  });

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
    'wide article scrolls independently and keeps comments on resize',
    (tester) async {
      final comments = DynamicCommentsFake()
        ..items = [
          for (var i = 0; i < 60; i++)
            CommentEntry(id: '${i + 1}', author: '读者', message: '读者留言 $i'),
        ];
      await _mountReader(tester, comments: comments, document: _longArticle());
      final reading = find.byKey(
        const PageStorageKey('dynamic-detail-content'),
      );
      final view = tester.widget<CustomScrollView>(reading);
      final panel = find.byType(CommentsPanel, skipOffstage: false);
      final panelState = tester.state(panel);
      final nested = tester.state<NestedScrollViewState>(
        find.byType(NestedScrollView),
      );
      expect(tester.getRect(reading).right, tester.getRect(panel).left);
      expect(tester.widget<CommentsPanel>(panel).target, _commentTarget);
      expect(tester.widget<CommentsPanel>(panel).replyCount, 60);
      expect(find.text('正文第 239 段'), findsNothing);
      await tester.drag(reading, const Offset(0, -520));
      await tester.pumpAndSettle();
      final readingOffset = view.controller!.offset;
      expect(readingOffset, greaterThan(350));
      expect(nested.innerController.offset, 0);

      await tester.drag(panel, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(nested.innerController.offset, greaterThan(200));
      expect(view.controller!.offset, readingOffset);
      final commentOffset = nested.innerController.offset;

      await tester.binding.setSurfaceSize(const Size(390, 750));
      await tester.pumpAndSettle();
      expect(tester.state(panel), same(panelState));
      expect(nested.outerController.offset, closeTo(readingOffset, 1));
      expect(nested.innerController.offset, closeTo(commentOffset, 1));
      expect(find.text('正文第 239 段'), findsNothing);

      final detail = find.byType(NestedScrollView);
      // Lazy paragraphs refine the estimated extent as the end comes into view.
      await tester.drag(detail, const Offset(0, -12000));
      await tester.pumpAndSettle();
      await tester.drag(detail, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(nested.outerController.position.extentAfter, lessThan(1));
      expect(find.text('最热').hitTestable(), findsOneWidget);
      expect(comments.reads, [_commentTarget.oid]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shared post card stacks above comments at enlarged text', (
    tester,
  ) async {
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
    expect(find.byType(ContentDetailPage), findsOneWidget);
    expect(find.descendant(of: card, matching: author), findsOneWidget);
    expect(
      tester.getBottomLeft(author).dy,
      lessThan(tester.getTopLeft(title).dy),
    );
    expect(
      tester.getBottomLeft(text).dy,
      lessThan(tester.getTopLeft(panel).dy),
    );
    expect(tester.getSize(panel).width, 960);
    await tester.tap(find.text('专栏作者'));
    expect(openedAuthor, const UserId('42'));
    await tester.tap(find.byIcon(Icons.open_in_new_outlined));
    expect(openedUrl, _column.webUri);
    expect(tester.takeException(), isNull);
  });

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
    final nested = tester.state<NestedScrollViewState>(
      find.byType(NestedScrollView),
    );
    nested.outerController.jumpTo(0);
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

Future<void> _mountReader(
  WidgetTester tester, {
  required CommentsRepository comments,
  required ArticleDocument document,
  Size size = const Size(1280, 750),
  double scale = 1,
  ValueNotifier<ContentLink>? link,
  VoidCallback? onLogin,
  ValueChanged<UserId>? onOpenUser,
  ValueChanged<Uri>? onOpenWeb,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = DynamicAuthFake(signedIn: false);
  addTearDown(auth.stream.close);
  final reader = ArticleScreen(
    address: _column,
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
        commentsRepositoryProvider(CommentTargetType.article)
            .overrideWithValue(comments),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
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

final class _Repository implements ArticleRepository {
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
