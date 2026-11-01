import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/search/application/search_controller.dart';
import 'package:bilisail/features/search/domain/search_repository.dart';
import 'package:bilisail/features/search/domain/search_result.dart';
import 'package:bilisail/features/search/presentation/search_category_bar.dart';
import 'package:bilisail/features/search/presentation/search_screen.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/application/video_extras_controller.dart';
import 'package:bilisail/features/video/domain/video_extras_repository.dart';
import 'package:bilisail/features/video/domain/video_repository.dart';
import 'package:bilisail/features/video/presentation/video_screen.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_grid.dart';
import 'package:bilisail/shared/ui/responsive_card_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_dock_navi/liquid_dock_navi.dart';

import 'input_test_app.dart';

const dpiDetailTitle =
    '这是一段用于检查播放详情标题自动换行的长标题，包含中文、English、2026 和标点：'
    '改变 DPI 或文字大小后不能截断标题，也不能让旧播放器重新创建。';

final dpiVideos = [
  for (var index = 0; index < 4; index++)
    VideoSummary(
      id: VideoId('BV1abc1234$index'),
      title: index == 0
          ? '短标题'
          : '长标题 $index：中文 English 2026，检查两行文字完整高度、超长省略与作者行之间的空间。'
                '这是额外的长文本，用于确保各种窗口尺寸都能覆盖标题省略。',
      coverUrl: '',
      author: '测试作者 $index',
      duration: const Duration(minutes: 123, seconds: 45),
      playCount: 1234567,
      danmakuCount: 12345,
      recommendationReason: '3万点赞',
    ),
];

Future<void> loadDpiTestFonts() async {
  final fonts = FontLoader('HarmonyOS Sans');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    fonts.addFont(
      rootBundle.load(
        'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_$weight.ttf',
      ),
    );
  }
  await fonts.load();
}

Widget dpiBrowserApp({
  bool search = false,
  bool sliver = false,
  TransitionBuilder? builder,
}) => ProviderScope(
  overrides: [
    if (search)
      searchRepositoryProvider.overrideWithValue(const _SearchRepository()),
  ],
  child: MaterialApp(
    theme: BiliTheme.light(),
    builder: builder,
    home: BiliAppShell(
      navigationMode: WorkspaceNavigationMode.dualTabs,
      location: search ? '/search' : '/',
      child: search
          ? const Column(
              children: [
                SearchCategoryBar(),
                Expanded(child: SearchScreen(query: '标题')),
              ],
            )
          : sliver
          ? CustomScrollView(
              slivers: [
                SliverCardGridPadding(
                  sliver: SliverVideoGrid(
                    items: dpiVideos,
                    onOpen: (_) {},
                    showRecommendationReason: true,
                    menuFor: (_) => const VideoCardMenu(
                      actions: [VideoCardMenuAction.watchLater],
                    ),
                  ),
                ),
              ],
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: VideoGrid(
                  items: dpiVideos,
                  onOpen: (_) {},
                  showUpBadge: true,
                  showRecommendationReason: true,
                  menuFor: (_) => const VideoCardMenu(
                    actions: [VideoCardMenuAction.watchLater],
                  ),
                ),
              ),
            ),
    ),
  ),
);

Widget dpiDetailApp({TransitionBuilder? builder}) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(_GuestAuth.new),
    videoRepositoryProvider.overrideWithValue(const _VideoRepository()),
    videoExtrasRepositoryProvider.overrideWithValue(const _Extras()),
  ],
  child: InputTestApp(
    theme: BiliTheme.light(),
    builder: builder,
    home: Scaffold(
      body: VideoScreen(
        id: const VideoId('BV1abc123456'),
        playerBuilder: (_, _, _) => const ColoredBox(
          color: Colors.black,
          key: ValueKey('audit-player'),
        ),
      ),
    ),
  ),
);

void expectDpiCards(WidgetTester tester) {
  final cards = tester.widgetList<VideoCard>(find.byType(VideoCard)).toList();
  expect(cards, isNotEmpty);
  for (final widget in cards) {
    final video = widget.video;
    final cardFinder = find.byWidget(widget);
    final title = find.descendant(
      of: cardFinder,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data ?? widget.textSpan?.toPlainText()) == video.title,
      ),
    );
    final paragraph = dpiParagraph(tester, title);
    expectDpiParagraphHeight(paragraph);
    final card = tester.getRect(cardFinder);
    final author = tester.getRect(
      find.descendant(of: cardFinder, matching: find.text(video.author)),
    );
    final titleRect = tester.getRect(title);
    expect(titleRect.bottom, lessThanOrEqualTo(author.top + .1));
    expect(author.bottom, lessThanOrEqualTo(card.bottom + .1));
    final cover = tester.getSize(
      find.descendant(of: cardFinder, matching: find.byType(AspectRatio)).first,
    );
    expect(cover.aspectRatio, closeTo(16 / 9, .001));
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: title, matching: find.byType(Tooltip)).first,
    );
    expect(tooltip.message, paragraph.didExceedMaxLines ? video.title : '');
  }
}

void expectDpiDetail(WidgetTester tester) {
  final paragraph = dpiParagraph(tester, find.text(dpiDetailTitle));
  expect(paragraph.didExceedMaxLines, isFalse);
  expectDpiParagraphHeight(paragraph);
  expect(find.byKey(const ValueKey('audit-player')), findsOneWidget);
}

void expectDpiBottomNavigation(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('workspace-bottom-navigation'));
  final navigation = tester.widget<LiquidDockNavi>(finder);
  expect(navigation.items.map((item) => item.label), [
    '首页',
    '动态',
    '我的',
    '历史',
    '下载',
    '设置',
  ]);
  final bounds = tester.getRect(finder);
  for (final label in ['首页', '动态', '我的', '历史', '下载', '设置']) {
    final text = find.descendant(of: finder, matching: find.text(label));
    final rect = tester.getRect(text);
    expect(rect.left, greaterThanOrEqualTo(bounds.left));
    expect(rect.right, lessThanOrEqualTo(bounds.right));
    expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
    expectDpiParagraphHeight(dpiParagraph(tester, text));
  }
}

RenderParagraph dpiParagraph(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)).first,
    );

void expectDpiParagraphHeight(RenderParagraph paragraph) {
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textAlign: paragraph.textAlign,
    textScaler: paragraph.textScaler,
    maxLines: paragraph.maxLines,
    ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '\u2026' : null,
    locale: paragraph.locale,
    strutStyle: paragraph.strutStyle,
    textWidthBasis: paragraph.textWidthBasis,
    textHeightBehavior: paragraph.textHeightBehavior,
  )..layout(maxWidth: paragraph.size.width);
  try {
    expect(painter.height, lessThanOrEqualTo(paragraph.size.height + .1));
  } finally {
    painter.dispose();
  }
}

final class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthState();
}

final class _VideoRepository implements VideoRepository {
  const _VideoRepository();

  @override
  Future<VideoDetail> loadDetail(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async => VideoDetail(
    summary: VideoSummary(
      id: id,
      title: dpiDetailTitle,
      coverUrl: '',
      author: '测试作者',
      duration: const Duration(minutes: 6),
    ),
    description: 'DPI 离线布局检查',
    parts: const [
      VideoPart(
        cid: '1',
        page: 1,
        title: '第一集',
        duration: Duration(minutes: 6),
      ),
    ],
  );
}

final class _Extras implements VideoExtrasRepository {
  const _Extras();

  @override
  Future<List<String>> loadTags(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async => const [];

  @override
  Future<List<VideoSummary>> loadRelated(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async => const [];

  @override
  Future<VideoCommentsPage> loadComments(
    VideoId id, {
    required int page,
    required RequestCancellation cancellation,
  }) async => const VideoCommentsPage(comments: [], hasMore: false);
}

final class _SearchRepository implements SearchRepository {
  const _SearchRepository();

  @override
  Future<SearchPage> search({
    required String query,
    required int page,
    required SearchCategory category,
    required SearchOrder order,
    required SearchDuration duration,
    required SearchUserType userType,
    required RequestCancellation cancellation,
  }) async => SearchPage(
    items: [for (final video in dpiVideos) SearchVideoEntry(video)],
    hasMore: false,
  );
}
