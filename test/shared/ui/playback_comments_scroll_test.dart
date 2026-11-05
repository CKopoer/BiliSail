import 'package:bili_player/bili_player.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/features/pgc/application/pgc_controller.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/pgc/presentation/pgc_screen.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/application/video_extras_controller.dart';
import 'package:bilisail/features/video/presentation/video_screen.dart';
import 'package:bilisail/shared/ui/comments_panel.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/input_test_app.dart';
import '../../support/playback_layout_session_fake.dart';

const _target = CommentTarget('42', CommentTargetType.video);
const _player = ValueKey('player');
const _detail = VideoDetail(
  aid: '42',
  summary: VideoSummary(
    id: VideoId('BV1ab411c7mD'),
    title: '测试视频',
    coverUrl: '',
    author: 'UP',
    duration: Duration(minutes: 1),
  ),
  description: '',
  parts: [
    VideoPart(cid: '1', page: 1, title: 'P1', duration: Duration(minutes: 1)),
  ],
);
final _season = PgcSeason(
  id: PgcSeasonId('1'),
  title: '测试影视',
  description: '',
  episodes: const [
    PgcEpisode(
      id: PgcEpisodeId('1'),
      title: '1',
      aid: '42',
      bvid: 'BV1ab411c7mD',
      cid: '1',
    ),
  ],
);

void main() {
  for (final pgc in [false, true]) {
    testWidgets(
      '${pgc ? 'PGC' : 'video'} comments automatically paginate inside the nested player layout',
      (tester) async {
        final comments = _Comments(paginate: true);
        final container = await _mount(tester, pgc: pgc, comments: comments);
        expect(comments.pages, [1]);
        await tester.drag(_list(), const Offset(0, -16000));
        await tester.pumpAndSettle();
        expect(comments.pages, [1, 2]);
        expect(
          container.read(commentsProviderFor(_target)).items,
          hasLength(80),
        );
        expect(_height(tester), 390 * 9 / 16);
        expect(tester.takeException(), isNull);
      },
    );

    for (final (dimensions, expanded) in [
      (const VideoDimensions(1080, 1920), 520.0),
      (const VideoDimensions(1080, 1080), 390.0),
      (const VideoDimensions(1000, 1100), 429.0),
    ]) {
      testWidgets(
        '${pgc ? 'PGC' : 'video'} ${dimensions.width}x${dimensions.height} comments share player collapse and retain offsets',
        (tester) async {
          await _mount(tester, pgc: pgc, dimensions: dimensions);
          final player = tester.element(find.byKey(_player));
          expect(_height(tester), closeTo(expanded, .01));
          final list = _list();
          final scroll = tester.widget<ListView>(list).controller!;

          final gesture = await tester.startGesture(tester.getCenter(list));
          await gesture.moveBy(const Offset(0, -24));
          await tester.pump();
          final before = _height(tester);
          await gesture.moveBy(const Offset(0, -60));
          await tester.pump();
          expect(before - _height(tester), closeTo(60, .01));
          expect(scroll.offset, 0);
          await gesture.moveBy(const Offset(0, -420));
          await tester.pump();
          expect(_height(tester), 390 * 9 / 16);
          expect(scroll.offset, greaterThan(0));
          await gesture.up();
          await tester.pumpAndSettle();
          final saved = scroll.offset;

          // Re-expand through the intro while retaining the comment offset.
          await tester.tap(find.text('简介'));
          await tester.pumpAndSettle();
          tester
              .state<NestedScrollViewState>(find.byType(NestedScrollView))
              .outerController
              .jumpTo(0);
          await tester.pumpAndSettle();
          expect(scroll.offset, saved);
          await tester.tap(find.text('评论'));
          await tester.pumpAndSettle();
          expect(_height(tester), closeTo(expanded, .01));
          expect(scroll.offset, saved);

          final second = await tester.startGesture(tester.getCenter(list));
          await second.moveBy(const Offset(0, -24));
          await tester.pump();
          final secondBefore = _height(tester);
          await second.moveBy(const Offset(0, -60));
          await tester.pump();
          expect(secondBefore - _height(tester), closeTo(60, .01));
          expect(scroll.offset, saved);
          await second.up();
          await tester.pumpAndSettle();

          // Downward scrolling consumes the list before expanding the player.
          scroll.jumpTo(200);
          await tester.pumpAndSettle();
          final down = await tester.startGesture(tester.getCenter(list));
          await down.moveBy(const Offset(0, 60));
          await tester.pump();
          expect(scroll.offset, greaterThan(0));
          expect(_height(tester), 390 * 9 / 16);
          await down.moveBy(Offset(0, scroll.offset + 80));
          await tester.pump();
          expect(scroll.offset, 0);
          expect(_height(tester), greaterThan(390 * 9 / 16));
          await down.up();
          await tester.pumpAndSettle();
          expect(tester.element(find.byKey(_player)), same(player));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '${pgc ? 'PGC' : 'video'} replies share collapse and reset only their own list',
      (tester) async {
        final container = await _mount(tester, pgc: pgc);
        final controller = container.read(
          commentsProviderFor(_target).notifier,
        );
        final root = container.read(commentsProviderFor(_target)).items.first;
        final main = tester.widget<ListView>(_list()).controller!;
        main.jumpTo(200);
        await tester.pumpAndSettle();
        final heightBefore = _height(tester);
        await controller.openReplies(root);
        await tester.pumpAndSettle();
        expect(_height(tester), heightBefore);
        final replies = tester.widget<ListView>(_list()).controller!;
        expect(replies.keepScrollOffset, isFalse);
        expect(replies.offset, 0);
        await tester.drag(_list(), const Offset(0, 500));
        await tester.pumpAndSettle();
        expect(_height(tester), 520);
        await tester.drag(_list(), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(_height(tester), 390 * 9 / 16);
        expect(replies.offset, greaterThan(0));
        controller.closeReplies();
        await tester.pumpAndSettle();
        expect(main.offset, closeTo(200, .01));
        await controller.openReplies(root);
        await tester.pumpAndSettle();
        expect(tester.widget<ListView>(_list()).controller!.offset, 0);
        expect(_height(tester), 390 * 9 / 16);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${pgc ? 'PGC' : 'video'} comment wheel collapses player before scrolling',
      (tester) async {
        await _mount(tester, pgc: pgc);
        final list = _list();
        final scroll = tester.widget<ListView>(list).controller!;
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(list),
            scrollDelta: const Offset(0, 100),
          ),
        );
        await tester.pumpAndSettle();
        expect(_height(tester), closeTo(420, 1));
        expect(scroll.offset, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Finder _list() => find.descendant(
  of: find.byType(CommentsPanel),
  matching: find.byType(ListView),
);

double _height(WidgetTester tester) =>
    tester.getSize(find.byKey(_player)).height;

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required bool pgc,
  VideoDimensions dimensions = const VideoDimensions(1080, 1920),
  _Comments? comments,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = PlaybackLayoutSessionFake();
  addTearDown(session.dispose);
  session.snapshots.value = session.snapshots.value.copyWith(
    videoDimensions: dimensions,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playbackSessionProvider.overrideWithValue(session),
        authControllerProvider.overrideWith(_Guest.new),
        videoCommentsRepositoryProvider.overrideWithValue(
          comments ?? _Comments(),
        ),
        videoDetailProvider(_detail.summary.id)
            .overrideWith((_) async => _detail),
        relatedVideosProvider(_detail.summary.id).overrideWith((_) async => []),
        videoTagsProvider(_detail.summary.id).overrideWith((_) async => []),
        pgcRepositoryProvider.overrideWithValue(_Pgc()),
      ],
      child: InputTestApp(
        builder: (context, child) => ScrollConfiguration(
          behavior: const SmoothScrollBehavior(),
          child: child!,
        ),
        home: Scaffold(
          body: pgc
              ? PgcScreen(
                  seasonId: '1',
                  defaultShowComments: true,
                  playerBuilder: (context, _, _) => _buildPlayer(context),
                  commentsBuilder: (_, _, _) =>
                      const CommentsPanel(target: _target),
                )
              : VideoScreen(
                  id: _detail.summary.id,
                  defaultShowComments: true,
                  playerBuilder: (context, _, _) => _buildPlayer(context),
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(CommentsPanel)));
}

Widget _buildPlayer(BuildContext context) {
  ProviderScope.containerOf(context).read(playbackSessionProvider);
  return const SizedBox.expand(key: _player);
}

class _Guest extends AuthController {
  @override
  AuthState build() => const AuthState();
}

class _Comments extends Fake implements CommentsRepository {
  _Comments({this.paginate = false});
  final bool paginate;
  final pages = <int>[];
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
  }) async {
    pages.add(page);
    return CommentPage(
      items: List.generate(
        40,
        (index) => CommentEntry(
          id: '$page-$index',
          author: '用户 $index',
          message: '评论内容 $index',
          replyCount: 40,
        ),
      ),
      hasMore: paginate && page == 1,
    );
  }

  @override
  Future<CommentPage> replies(
    String oid,
    String rootId,
    int page,
    RequestCancellation cancellation,
  ) async => CommentPage(
    items: List.generate(
      40,
      (index) => CommentEntry(
        id: 'reply-$index',
        author: '回复用户',
        message: '回复内容 $index',
        rootId: rootId,
      ),
    ),
    hasMore: false,
  );
}

class _Pgc extends Fake implements PgcRepository {
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<PgcSeason> detail({
    PgcSeasonId? seasonId,
    PgcEpisodeId? episodeId,
    bool refresh = false,
    required RequestCancellation cancellation,
  }) async => _season;
}
