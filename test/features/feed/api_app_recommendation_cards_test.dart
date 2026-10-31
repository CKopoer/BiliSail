import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/domain/app_session_credentials.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/feed/data/api_feed_repository.dart';
import 'package:bilisail/features/feed/data/app_recommendation_identity_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _device = 'fixture_device_0123456789';
Map<String, Object?> _entry(String type, {String param = '42', String? uri}) =>
    {
      'card_goto': type,
      'can_play': 1,
      'param': param,
      'title': '$type 推荐',
      'uri': uri,
      'player_args': {'aid': 170001, 'cid': 99, 'duration': 60},
      'desc_button': {'text': '系列作者'},
      'three_point_v2': [
        {
          'type': 'dislike',
          'reasons': [
            {'id': 1, 'name': '不感兴趣'},
          ],
        },
      ],
    };

void main() {
  late AppDatabase database;
  late StreamController<AuthState> changes;
  late AppRecommendationIdentityStore identity;
  late BiliApiClient api;
  late _Transport transport;
  late ApiFeedRepository repository;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.writeSetting('app-recommendation-device.v1', _device);
    changes = StreamController.broadcast();
    identity = AppRecommendationIdentityStore(
      database: database,
      credentials: _Secure(),
      accountScope: () => 'user:7',
      accountChanges: changes.stream,
      sessionCredentials: _Session(),
    );
    transport = _Transport();
    final requests = ApiRequests();
    api = BiliApiClient(transport: transport, sessionProvider: requests);
    repository = ApiFeedRepository(api, requests, appIdentity: identity);
  });
  tearDown(() async {
    api.close();
    await identity.close();
    await changes.close();
    await database.close();
  });

  test('different playable types keep distinct keys, destinations and feedback IDs', () async {
    transport.entries = [
      _entry('av'),
      _entry('bangumi'),
      _entry(
        'picture',
        param: '9007199254740993123',
        uri: 'bilibili://following/9007199254740993123',
      ),
      _entry(
        'vertical_av',
        uri: 'bilibili://video/170001?player_width=1080&player_height=1920',
      ),
      _entry('future_card'),
    ];
    final page = await repository.loadAppRecommendations(
      page: 1,
      cancellation: RequestCancellation(),
    );
    expect(page.items.length, 5);
    expect(page.items.map((item) => item.id).toSet().length, 5);
    expect(page.items.first.id, const VideoId('BV17x411w7KC'));
    expect(page.items.first.recommendationTarget, isNull);
    final episode = page.items[1];
    expect(episode.id.isValid, isFalse);
    expect(
      episode.recommendationTarget?.kind,
      RecommendationTargetKind.episode,
    );
    expect(episode.recommendationTarget?.id, '42');
    expect(episode.author, '系列作者');
    final dynamic = page.items[2].recommendationTarget;
    expect(dynamic?.kind, RecommendationTargetKind.dynamic);
    expect(
      dynamic?.url,
      Uri.parse('https://t.bilibili.com/9007199254740993123'),
    );
    expect(
      page.items[3].recommendationTarget?.kind,
      RecommendationTargetKind.video,
    );
    expect(page.items[3].recommendationTarget?.id, 'BV17x411w7KC');
    expect(
      page.items.last.recommendationTarget?.kind,
      RecommendationTargetKind.unsupported,
    );
    final feedback = episode.recommendationFeedback!;
    final selected = feedback.selectReason(feedback.reasons.single);
    expect(selected.goto, 'bangumi');
    expect(
      selected.aid,
      '42',
      reason: 'Feedback uses param, not player_args.aid',
    );
    await repository.rejectRecommendation(
      selected,
      cancellation: RequestCancellation(),
    );
    expect(transport.uris.last.queryParameters['id'], '42');
    expect(transport.uris.last.queryParameters['goto'], 'bangumi');
    await repository.undoRecommendationFeedback(
      selected,
      cancellation: RequestCancellation(),
    );
    expect(transport.uris.last.path, '/x/feed/dislike/cancel');
    expect(transport.uris.last.queryParameters['id'], '42');
    expect(transport.uris.last.queryParameters['goto'], 'bangumi');
  });

  test(
    'playable URI variants map without trusting malformed or non-public links',
    () async {
      final cases = [
        ('bilibili://bangumi/season/99', RecommendationTargetKind.season, '99'),
        (
          'bilibili://bangumi/play/ep123',
          RecommendationTargetKind.episode,
          '123',
        ),
        ('bilibili://live/777', RecommendationTargetKind.live, '777'),
        (
          'bilibili://video/BV17x411w7KC',
          RecommendationTargetKind.video,
          'BV17x411w7KC',
        ),
        (
          'https://www.bilibili.com/opus/42',
          RecommendationTargetKind.external,
          '',
        ),
        ('file:///C:/private', RecommendationTargetKind.unsupported, ''),
        ('https://evil.example/42', RecommendationTargetKind.unsupported, ''),
        (
          'https://name@www.bilibili.com/42',
          RecommendationTargetKind.unsupported,
          '',
        ),
        (
          'https://www.bilibili.com:444/42',
          RecommendationTargetKind.unsupported,
          '',
        ),
        (
          'bilibili://bangumi/season/invalid',
          RecommendationTargetKind.unsupported,
          '',
        ),
      ];
      transport.entries = [
        for (var i = 0; i < cases.length; i++)
          _entry('future_card', param: '${i + 1}', uri: cases[i].$1),
      ];
      final page = await repository.loadAppRecommendations(
        page: 1,
        cancellation: RequestCancellation(),
      );
      for (var i = 0; i < cases.length; i++) {
        final target = page.items[i].recommendationTarget;
        expect(target?.kind, cases[i].$2, reason: cases[i].$1);
        expect(target?.id, cases[i].$3, reason: cases[i].$1);
      }
    },
  );
}

final class _Session implements AppSessionCredentialsPort {
  @override
  AppSessionCredentials get appCredentials => AppSessionCredentials(
    mid: '7',
    accessToken: 'fixture-token',
    expiresAt: DateTime.utc(2099),
    buvid: _device,
  );
  @override
  Future<void> invalidateAppCredentials(AppSessionCredentials expected) async {}
}

final class _Secure implements CredentialStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}

final class _Transport implements ApiTransport {
  List<Map<String, Object?>> entries = [];
  final uris = <Uri>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    uris.add(uri);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'code': 0,
            'data': uri.path == '/x/v2/feed/index' ? {'items': entries} : null,
          }),
        ),
      ),
      const {},
    );
  }
}
