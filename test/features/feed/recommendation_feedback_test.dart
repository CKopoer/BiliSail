import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/features/video/application/video_card_preview_playback.dart';
import 'package:bilisail/features/video/domain/video_card_interactions.dart';
import 'package:bilisail/features/video/domain/video_actions_repository.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_card_cover.dart';
import 'package:bilisail/shared/ui/video_card_interaction_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _video = VideoSummary(
  id: VideoId('BV1234567890'),
  title: '推荐视频',
  coverUrl: '',
  author: '测试作者',
  duration: Duration(seconds: 60),
  recommendationFeedback: RecommendationFeedback(
    aid: '42',
    goto: 'av',
    trackId: 'original-track',
    ownerMid: '7',
  ),
);
const _neighbor = VideoSummary(
  id: VideoId('BV1234567891'),
  title: '相邻视频',
  coverUrl: '',
  author: '测试作者',
  duration: Duration(seconds: 60),
);
final _undo = find.byKey(const ValueKey('video-card-feedback-undo'));

void main() {
  setUpAll(() async {
    await (FontLoader('HarmonyOS Sans')..addFont(
          rootBundle.load(
            'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
          ),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'feedback and undo retain both card positions and block duplicate undo',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(_feed(repository));
      await tester.pumpAndSettle();
      final first = find.byType(VideoCard).first;
      final neighbor = find.byType(VideoCard).last;
      final firstRect = tester.getRect(first);
      final neighborRect = tester.getRect(neighbor);
      await tester.tap(
        find.byKey(const ValueKey('video-card-title-menu')).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('不感兴趣'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('内容不感兴趣'), findsNothing);
      repository.writes.single.complete();
      await tester.pumpAndSettle();
      expect(find.text('内容不感兴趣'), findsOneWidget);
      expect(find.text('将减少此类内容推荐'), findsOneWidget);
      expect(tester.getRect(first), firstRect);
      expect(tester.getRect(neighbor), neighborRect);
      expect(find.byType(VideoCardCover), findsOneWidget);
      await tester.tap(_undo);
      await tester.pump();
      expect(tester.widget<TextButton>(_undo).onPressed, isNull);
      await tester.tap(_undo);
      expect(repository.undoCalls, 1);
      repository.writes.last.complete();
      await tester.pumpAndSettle();
      expect(find.text('内容不感兴趣'), findsNothing);
      expect(tester.getRect(first), firstRect);
      expect(tester.getRect(neighbor), neighborRect);
      expect(find.byType(VideoCardCover), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  for (final unknown in [false, true]) {
    testWidgets(
      'undo failure keeps overlay and disables only uncertain retries: $unknown',
      (tester) async {
        final repository = _Repository();
        await tester.pumpWidget(_feed(repository));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('video-card-title-menu')).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('不感兴趣'));
        await tester.pump(const Duration(milliseconds: 300));
        repository.writes.single.complete();
        await tester.pumpAndSettle();
        await tester.tap(_undo);
        await tester.pump();
        repository.writes.last.completeError(
          unknown
              ? const UnknownWriteOutcome()
              : const AppFailure(AppFailureKind.rateLimited, '撤销暂时失败'),
        );
        await tester.pump();
        expect(find.text('内容不感兴趣'), findsOneWidget);
        expect(
          tester.widget<TextButton>(_undo).onPressed,
          unknown ? isNull : isNotNull,
        );
        expect(
          find.text(unknown ? '撤销结果暂时无法确认，请稍后刷新核对' : '撤销暂时失败'),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('overlay consumes card taps and keyboard undo works', (
    tester,
  ) async {
    var opens = 0;
    var undos = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 324,
            child: VideoCard(
              video: _video,
              onTap: () => opens++,
              feedback: VideoCardFeedback(onUndo: () => undos++),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('内容不感兴趣'));
    expect(opens, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(undos, 1);
    expect(opens, 0);
  });

  testWidgets('feedback cancels pending hover preview', (tester) async {
    final operations = _Operations();
    Widget card(VideoCardFeedback? feedback) => MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(
        body: SizedBox(
          width: 324,
          child: VideoCardInteractionScope(
            interactions: operations,
            onNotice: (_, _) {},
            child: VideoCard(video: _video, onTap: () {}, feedback: feedback),
          ),
        ),
      ),
    );
    await tester.pumpWidget(card(null));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(VideoCardCover)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(operations.token, isNotNull);
    await tester.pumpWidget(card(VideoCardFeedback(onUndo: () {})));
    expect(operations.token?.isCancelled, true);
    operations.previewResult.complete(null);
    await tester.pump();
    expect(find.byType(VideoCardCover), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale) in [
    (324.0, 1.0),
    (140.0, 1.0),
    (210.0, 2.0),
    (140.0, 2.0),
  ]) {
    testWidgets('feedback stays usable at width $width and scale $scale', (
      tester,
    ) async {
      final boundary = GlobalKey();
      var undos = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'HarmonyOS Sans'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? const SizedBox.shrink(),
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RepaintBoundary(
                      key: boundary,
                      child: ColoredBox(
                        color: Colors.white,
                        child: VideoCard(
                          video: _video,
                          onTap: () {},
                          feedback: VideoCardFeedback(onUndo: () => undos++),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_undo.hitTestable(), findsOneWidget);
      await tester.tap(_undo);
      expect(undos, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final render = boundary.currentContext?.findRenderObject();
        if (render is! RenderRepaintBoundary) {
          throw StateError('Missing preview');
        }
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (bytes == null) throw StateError('Missing preview bytes');
        final dir = Directory('build/recommendation-feedback-preview');
        await dir.create(recursive: true);
        await File('${dir.path}/card-$width-$scale.png')
            .writeAsBytes(bytes.buffer.asUint8List());
      });
    });
  }
}

Widget _feed(_Repository repository) => ProviderScope(
  overrides: [feedRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    theme: ThemeData(
      platform: TargetPlatform.android,
      fontFamily: 'HarmonyOS Sans',
    ),
    home: const Scaffold(
      body: AppNoticeHost(child: FeedScreen(isSignedIn: true)),
    ),
  ),
);

final class _Repository extends Fake
    implements FeedRepository, RecommendationFeedbackRepository {
  @override
  String get feedbackScope => 'session:fixture';
  final writes = <Completer<void>>[];
  int undoCalls = 0;
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [_video, _neighbor], hasMore: false);
  @override
  Future<void> rejectRecommendation(
    RecommendationFeedback feedback, {
    required RequestCancellation cancellation,
  }) {
    final result = Completer<void>();
    writes.add(result);
    return result.future;
  }

  @override
  Future<void> undoRecommendationFeedback(
    RecommendationFeedback feedback, {
    required RequestCancellation cancellation,
  }) {
    undoCalls++;
    return rejectRecommendation(feedback, cancellation: cancellation);
  }
}

final class _Operations implements VideoCardOperations {
  RequestCancellation? token;
  final previewResult = Completer<VideoCardPreviewSession?>();
  @override
  Future<VideoCardPreviewSession?> preview(
    VideoId id,
    RequestCancellation cancellation, {
    String? cid,
  }) {
    token = cancellation;
    return previewResult.future;
  }

  @override
  bool isAdded(VideoId id) => false;
  @override
  bool isUncertain(VideoId id) => false;
  @override
  Future<WatchLaterResult> addWatchLater(VideoId id) async =>
      WatchLaterResult.added;
}
