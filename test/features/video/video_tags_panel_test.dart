import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/video/application/video_extras_controller.dart';
import 'package:bilisail/features/video/domain/video_extras_repository.dart';
import 'package:bilisail/features/video/presentation/video_tags_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loading, failure and retry stay within the tags panel', (
    tester,
  ) async {
    final repository = _TagsRepository();
    await tester.pumpWidget(_app(repository, const VideoId('BV1234567890')));
    await tester.pump();
    expect(find.text('正在加载标签…'), findsOneWidget);
    repository.requests.single.result.completeError(
      const AppFailure(AppFailureKind.network, '网络不可用'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('标签加载失败，点击重试'));
    await tester.pump();
    expect(repository.requests, hasLength(2));
    expect(repository.requests.first.signal.isCancelled, isTrue);
    repository.requests.last.result.complete(['编程']);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, '编程'), findsOneWidget);
    expect(find.text('标签加载失败，点击重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'video changes cancel old tags and ignore their late completion',
    (tester) async {
      final repository = _TagsRepository();
      await tester.pumpWidget(_app(repository, const VideoId('BV1234567890')));
      await tester.pump();
      final old = repository.requests.single;
      await tester.pumpWidget(_app(repository, const VideoId('BV0987654321')));
      await tester.pump();
      final current = repository.requests.last;
      expect(old.signal.isCancelled, isTrue);
      expect(current.id, const VideoId('BV0987654321'));
      current.result.complete(['新标签']);
      await tester.pumpAndSettle();
      old.result.complete(['旧标签']);
      await tester.pumpAndSettle();
      expect(find.text('新标签'), findsOneWidget);
      expect(find.text('旧标签'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(current.signal.isCancelled, isTrue);
    },
  );

  testWidgets('empty tags and cancellation hide the section without an error', (
    tester,
  ) async {
    final repository = _TagsRepository();
    await tester.pumpWidget(_app(repository, const VideoId('BV1234567890')));
    await tester.pump();
    repository.requests.single.result.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('标签'), findsNothing);
    await tester.pumpWidget(_app(repository, const VideoId('BV0987654321')));
    await tester.pump();
    repository.requests.last.result.completeError(
      const AppFailure(AppFailureKind.cancelled, '请求已取消'),
    );
    await tester.pumpAndSettle();
    expect(find.text('标签加载失败，点击重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long names wrap in narrow layouts with large text', (
    tester,
  ) async {
    final repository = _TagsRepository();
    await tester.pumpWidget(_app(repository, const VideoId('BV1234567890')));
    await tester.pump();
    repository.requests.single.result.complete([
      '这是一条非常长的视频标签用于检查小窗口与字体放大时的布局',
      'Flutter',
      '编程',
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(ActionChip), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}

Widget _app(_TagsRepository repository, VideoId id) => ProviderScope(
  overrides: [videoExtrasRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: SizedBox(
          width: 240,
          child: VideoTagsPanel(id: id, onSearch: (_) {}),
        ),
      ),
    ),
  ),
);

final class _TagRequest {
  _TagRequest(this.id, this.signal);
  final VideoId id;
  final RequestCancellation signal;
  final result = Completer<List<String>>();
}

final class _TagsRepository implements VideoExtrasRepository {
  final requests = <_TagRequest>[];

  @override
  Future<List<String>> loadTags(
    VideoId id, {
    required RequestCancellation cancellation,
  }) {
    final request = _TagRequest(id, cancellation);
    requests.add(request);
    return request.result.future;
  }

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
