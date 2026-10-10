import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_feed_cards.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:bilisail/features/video/data/api_video_repository.dart';
import 'package:bilisail/features/video/presentation/video_access_notice.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_card_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = VideoId('BV1q6ad6NEVK');
const _access = VideoAccess(
  kind: VideoAccessKind.chargingExclusive,
  canWatch: false,
  canPreview: true,
);
const _video = VideoSummary(
  id: _id,
  title: '测试视频',
  coverUrl: '',
  author: 'UP',
  duration: Duration(minutes: 8),
  access: _access,
);

void main() {
  test(
    'detail and playback repositories explain the same charging entitlement',
    () async {
      final requests = ApiRequests();
      final api = BiliApiClient(
        transport: _Transport(),
        sessionProvider: requests,
      );
      addTearDown(api.close);
      final detail = await ApiVideoRepository(
        api,
        requests,
      ).loadDetail(_id, cancellation: RequestCancellation());
      expect(detail.summary.access.kind, VideoAccessKind.chargingExclusive);
      expect(detail.summary.access.canWatch, false);
      expect(detail.summary.access.canPreview, true);
      await expectLater(
        ApiPlaybackRepository(api, requests).resolve(
          _id,
          detail.parts.single.cid,
          quality: 32,
          cancellation: RequestCancellation(),
        ),
        throwsA(
          isA<AppFailure>()
              .having((e) => e.kind, 'kind', AppFailureKind.permission)
              .having(
                (e) => e.message,
                'message',
                allOf(contains('充电专属'), contains('对应充电档位'), contains('官网')),
              ),
        ),
      );
    },
  );

  test(
    'account changes during entitlement lookup suppress the stale paywall',
    () async {
      final requests = ApiRequests();
      final api = BiliApiClient(
        transport: _Transport(onDetail: requests.advanceSession),
        sessionProvider: requests,
      );
      addTearDown(api.close);
      await expectLater(
        ApiPlaybackRepository(api, requests).resolve(
          _id,
          '42328985110',
          quality: 32,
          cancellation: RequestCancellation(),
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            AppFailureKind.cancelled,
          ),
        ),
      );
    },
  );

  for (final kind in [
    VideoAccessKind.normal,
    VideoAccessKind.chargingExclusive,
    VideoAccessKind.paid,
  ]) {
    testWidgets('grid home and related covers share the access badge $kind', (
      tester,
    ) async {
      final access = VideoAccess(kind: kind);
      final video = VideoSummary(
        id: _id,
        title: '测试视频',
        coverUrl: '',
        author: 'UP',
        duration: const Duration(minutes: 8),
        access: access,
      );
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: VideoCard(video: video, onTap: () {}),
                    ),
                    SizedBox(
                      width: 140,
                      child: HomeVideoCard(
                        entry: HomeEntry(
                          id: _id.value,
                          title: '测试视频',
                          kind: HomeEntryKind.video,
                          bvid: _id.value,
                          access: access,
                        ),
                        onTap: () {},
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      height: 79,
                      child: VideoCardCover(
                        video: video,
                        child: const ColoredBox(color: Colors.black12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (access.label case final label?) {
          expect(find.text(label), findsNWidgets(3));
        } else {
          expect(find.text('充电专属'), findsNothing);
          expect(find.text('付费视频'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets(
    'access notice opens only the public video after an explicit gesture',
    (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            externalLinkOpenerProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return true;
            }),
          ],
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: const Scaffold(
              body: SizedBox(
                width: 300,
                child: VideoAccessNotice(video: _video),
              ),
            ),
          ),
        ),
      );
      expect(opened, isEmpty);
      expect(find.textContaining('指定的充电档位'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('video-access-official')));
      await tester.pump();
      expect(opened, [
        Uri.parse('https://www.bilibili.com/video/BV1q6ad6NEVK'),
      ]);
      expect(opened.single.hasQuery, false);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _Transport implements ApiTransport {
  _Transport({this.onDetail});
  final void Function()? onDetail;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final Object data;
    if (uri.path.endsWith('/nav')) {
      data = {
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
          'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
        },
      };
    } else if (uri.path.endsWith('/view')) {
      onDetail?.call();
      data = {
        'aid': '117358337201563',
        'bvid': _id.value,
        'title': '测试视频',
        'is_upower_exclusive': true,
        'is_upower_play': false,
        'is_upower_preview': true,
        'pages': [
          {'cid': '42328985110', 'page': 1, 'part': 'P1'},
        ],
      };
    } else if (uri.path.endsWith('/playurl')) {
      data = <String, Object?>{};
    } else {
      throw StateError('Unexpected endpoint ${uri.path}');
    }
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
