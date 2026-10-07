import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/profile/data/api_profile_repository.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const id = UserId('9007199254740993123');

void main() {
  test(
    'live lookup maps an offline room without losing its string ID',
    () async {
      final requests = ApiRequests();
      final api = BiliApiClient(
        sessionProvider: requests,
        transport: _Transport((uri) {
          expect(uri.queryParameters['mid'], id.value);
          return {
            'code': 0,
            'data': {
              'roomStatus': 1,
              'roomid': '9007199254740993123',
              'liveStatus': 0,
            },
          };
        }),
      );
      addTearDown(api.close);
      final repository = ApiProfileRepository(
        ProfileClient(api),
        requests,
        accountScope: () => 'guest',
      );
      final room = await repository.loadLiveRoom(
        id,
        cancellation: RequestCancellation(),
      );
      expect(room?.id, const RoomId('9007199254740993123'));
      expect(room?.isLive, false);
    },
  );
  test('live lookup failure is not a successful absent room', () async {
    final requests = ApiRequests();
    final api = BiliApiClient(
      sessionProvider: requests,
      transport: _Transport((_) => {'code': -101}),
    );
    addTearDown(api.close);
    final repository = ApiProfileRepository(
      ProfileClient(api),
      requests,
      accountScope: () => 'guest',
    );
    await expectLater(
      repository.loadLiveRoom(id, cancellation: RequestCancellation()),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.authentication,
        ),
      ),
    );
  });
  test('live lookup is cancelled when the account session changes', () async {
    final requests = ApiRequests();
    final pending = Completer<Object>();
    final api = BiliApiClient(
      sessionProvider: requests,
      transport: _Transport((_) => pending.future),
    );
    addTearDown(api.close);
    final repository = ApiProfileRepository(
      ProfileClient(api),
      requests,
      accountScope: () => 'guest',
    );
    final read = repository.loadLiveRoom(
      id,
      cancellation: RequestCancellation(),
    );
    final assertion = expectLater(
      read,
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.cancelled,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    requests.advanceSession();
    pending.complete({
      'code': 0,
      'data': {'roomStatus': 1, 'roomid': 1024, 'liveStatus': 1},
    });
    await assertion;
  });
  for (final section in [ProfileSection.following, ProfileSection.followers]) {
    final followers = section == ProfileSection.followers;
    for (final hidden in [false, true]) {
      test('${section.name} honors its privacy flag: $hidden', () async {
        final paths = <String>[];
        final requests = ApiRequests();
        final api = BiliApiClient(
          sessionProvider: requests,
          transport: _Transport((uri) {
            paths.add(uri.path);
            if (uri.path == '/x/space/setting') {
              expect(uri.queryParameters['mid'], id.value);
              return {
                'code': 0,
                'data': {
                  'privacy': {
                    'disable_following': followers || hidden ? 1 : 0,
                    'disable_show_fans': !followers || hidden ? 1 : 0,
                  },
                },
              };
            }
            expect(
              uri.path,
              '/x/relation/${followers ? 'followers' : 'followings'}',
            );
            expect(uri.queryParameters['vmid'], id.value);
            expect(uri.queryParameters['pn'], '2');
            return {
              'code': 0,
              'data': {
                'total': 90,
                'list': [
                  {'mid': '9', 'uname': '用户甲'},
                ],
              },
            };
          }),
        );
        addTearDown(api.close);
        final repository = ApiProfileRepository(
          ProfileClient(api),
          requests,
          accountScope: () => 'guest',
        );
        final page = await repository.loadEntries(
          id,
          section,
          page: 2,
          cancellation: RequestCancellation(),
        );
        expect(page.isHidden, hidden);
        expect(page.hasMore, !hidden);
        expect(page.items, hidden ? isEmpty : hasLength(1));
        expect(paths.length, hidden ? 1 : 2);
        if (hidden) expect(page.cursor, isNull);
      });
    }
    test('the owner can view their own ${section.name}', () async {
      final requests = ApiRequests();
      final api = BiliApiClient(
        sessionProvider: requests,
        transport: _Transport((uri) {
          expect(
            uri.path,
            '/x/relation/${followers ? 'followers' : 'followings'}',
          );
          return {
            'code': 0,
            'data': {'total': 0, 'list': []},
          };
        }),
      );
      addTearDown(api.close);
      final repository = ApiProfileRepository(
        ProfileClient(api),
        requests,
        accountScope: () => 'user:${id.value}',
      );
      final page = await repository.loadEntries(
        id,
        section,
        page: 1,
        cancellation: RequestCancellation(),
      );
      expect(page.isHidden, isFalse);
      expect(page.items, isEmpty);
    });
  }
  for (final (code, kind) in [
    (-101, AppFailureKind.authentication),
    (-352, AppFailureKind.rateLimited),
    (12345, AppFailureKind.playback),
  ]) {
    test('public lists preserve genuine failures: $code', () async {
      final requests = ApiRequests();
      final api = BiliApiClient(
        sessionProvider: requests,
        transport: _Transport(
          (uri) => uri.path == '/x/space/setting'
              ? {
                  'code': 0,
                  'data': {
                    'privacy': {'disable_following': 0, 'disable_show_fans': 0},
                  },
                }
              : {'code': code},
        ),
      );
      addTearDown(api.close);
      final repository = ApiProfileRepository(
        ProfileClient(api),
        requests,
        accountScope: () => 'guest',
      );
      await expectLater(
        repository.loadEntries(
          id,
          ProfileSection.following,
          page: 1,
          cancellation: RequestCancellation(),
        ),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', kind)),
      );
    });
  }
  test(
    'account change during privacy read cancels before loading relations',
    () async {
      final pending = Completer<Object>();
      final requests = ApiRequests();
      var reads = 0;
      final api = BiliApiClient(
        sessionProvider: requests,
        transport: _Transport((uri) {
          reads++;
          expect(uri.path, '/x/space/setting');
          return pending.future;
        }),
      );
      addTearDown(api.close);
      final repository = ApiProfileRepository(
        ProfileClient(api),
        requests,
        accountScope: () => 'guest',
      );
      final read = repository.loadEntries(
        id,
        ProfileSection.following,
        page: 1,
        cancellation: RequestCancellation(),
      );
      final assertion = expectLater(
        read,
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            AppFailureKind.cancelled,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      requests.advanceSession();
      pending.complete({
        'code': 0,
        'data': {
          'privacy': {'disable_following': 0, 'disable_show_fans': 0},
        },
      });
      await assertion;
      expect(reads, 1);
    },
  );
}

final class _Transport implements ApiTransport {
  _Transport(this.handler);
  final FutureOr<Object> Function(Uri) handler;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
    200,
    Uint8List.fromList(utf8.encode(jsonEncode(await handler(uri)))),
    const {},
  );
}
