import 'dart:async';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'message_client_test.dart' show cookies, response, wbiKeyData;

const _sessions = '/session_svr/v1/session_svr/get_sessions';
const _thread = '/svr_sync/v1/svr_sync/fetch_session_msgs';
const _cards = '/x/polymer/pc-electron/v1/user/cards';
const _nav = '/x/web-interface/nav';

void main() {
  test(
    'IM reads share WBI keys and sign exact cursors with message headers',
    () async {
      final now = DateTime.utc(2026, 11, 14);
      final transport = _Transport(
        (uri) async => response(
          uri.path == _thread
              ? {'messages': [], 'has_more': 0}
              : {'session_list': [], 'has_more': 0},
        ),
      );
      final api = BiliApiClient(
        transport: transport,
        cookieJar: cookies(),
        clock: () => now,
      );
      addTearDown(api.close);
      final client = MessageClient(api);
      await Future.wait([
        client.sessions(cursor: '1700000000000001'),
        client.thread('9007199254740993123', 1, cursor: '9007199254740993999'),
        MessageCenterClient(api).assistantSessions(fanGroups: true),
      ]);
      expect(transport.reads.where((r) => r.uri.path == _nav), hasLength(1));
      final signer = WbiSigner.fromUrls(
        'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
        'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
      );
      final reads = transport.reads.where((r) => r.uri.path != _nav).toList();
      expect(reads, hasLength(3));
      for (final read in reads) {
        expect(read.uri.host, 'api.vc.bilibili.com');
        expect(read.headers['Referer'], 'https://message.bilibili.com/');
        expect(read.headers['Origin'], 'https://message.bilibili.com');
        expect(read.headers['Cookie'], contains('SESSDATA=fixture'));
        final parameters = Map.of(read.uri.queryParameters)
          ..remove('w_rid')
          ..remove('wts');
        expect(read.uri.queryParameters, signer.sign(parameters, now));
      }
      final session = reads.singleWhere(
        (r) =>
            r.uri.queryParameters['session_type'] == '1' &&
            r.uri.path == _sessions,
      );
      expect(session.uri.queryParameters['end_ts'], '1700000000000001');
      final thread = reads.singleWhere((r) => r.uri.path == _thread);
      expect(thread.uri.queryParameters['end_seqno'], '9007199254740993999');
      expect(thread.uri.queryParameters['talker_id'], '9007199254740993123');
      expect(thread.uri.queryParameters['size'], '20');
      expect(thread.uri.queryParameters['sender_device_id'], '1');
    },
  );

  for (final thread in [false, true]) {
    test(
      'IM risk control stops retries and key refresh (thread=$thread)',
      () async {
        var now = DateTime.utc(2026, 11, 14);
        final transport = _Transport((_) async => response(null, code: -352));
        final api = BiliApiClient(transport: transport, clock: () => now);
        addTearDown(api.close);
        final client = MessageClient(api);
        Future<Object> read() =>
            thread ? client.thread('123', 1) : client.sessions();
        final limited = isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.rateLimited,
        );
        await expectLater(read(), throwsA(limited));
        await expectLater(read(), throwsA(limited));
        expect(
          transport.reads,
          hasLength(2),
        ); // One nav, one target, no replay.
        now = now.add(const Duration(seconds: 31));
        await expectLater(read(), throwsA(limited));
        expect(transport.reads, hasLength(3));
        expect(transport.reads.where((r) => r.uri.path == _nav), hasLength(1));
      },
    );
  }

  test(
    'card rate limits preserve sessions and suppress auxiliary requests during cooldown',
    () async {
      final transport = _Transport((uri) async {
        if (uri.path == _cards) {
          expect(uri.queryParameters, {
            'uids': '123',
            'build': '0',
            'mobi_app': 'web',
          });
          return response(null, status: 429);
        }
        return response({
          'has_more': 1,
          'session_list': [
            {
              'talker_id': '123',
              'session_type': 1,
              'session_ts': '1700000000000001',
              'unread_count': 2,
              'account_info': {
                'uname': '会话昵称',
                'pic_url': 'https://i0.hdslb.com/a.png',
              },
            },
          ],
        });
      });
      final api = BiliApiClient(
        transport: transport,
        clock: () => DateTime.utc(2026, 11, 14),
      );
      addTearDown(api.close);
      final client = MessageClient(api);
      for (var i = 0; i < 2; i++) {
        final page = await client.sessions();
        expect(page.items.single.title, '会话昵称');
        expect(page.items.single.avatarUrl?.path, '/a.png');
        expect(page.items.single.unread, 2);
        expect(page.nextCursor, '1700000000000001');
        expect(page.hasMore, isTrue);
      }
      expect(transport.reads.where((r) => r.uri.path == _cards), hasLength(1));
      expect(
        transport.reads.where((r) => r.uri.path == _sessions),
        hasLength(2),
      );
    },
  );

  for (final category in [
    ApiFailureCategory.cancelled,
    ApiFailureCategory.authentication,
    ApiFailureCategory.protocol,
  ]) {
    test('auxiliary $category failures remain failures', () async {
      final transport = _Transport((uri) async {
        if (uri.path == _cards) throw ApiFailure(category, 'message_users');
        return response({
          'has_more': 0,
          'session_list': [
            {'talker_id': '123', 'session_type': 1, 'session_ts': '1'},
          ],
        });
      });
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      await expectLater(
        MessageClient(api).sessions(),
        throwsA(
          isA<ApiFailure>().having((e) => e.category, 'category', category),
        ),
      );
    });
  }

  test(
    'an account change during shared signing cannot send a stale IM request',
    () async {
      final keys = Completer<ApiHttpResponse>();
      final transport = _Transport((_) async => response({}))
        ..keys = keys.future;
      final session = _Session();
      final api = BiliApiClient(transport: transport, sessionProvider: session);
      addTearDown(api.close);
      final result = MessageClient(
        api,
      ).sessions(context: const ApiRequestContext(sessionEpoch: 0));
      final assertion = expectLater(
        result,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.cancelled,
          ),
        ),
      );
      session.sessionEpoch++;
      keys.complete(response(wbiKeyData()));
      await assertion;
      expect(transport.reads, hasLength(1));
      expect(transport.reads.single.uri.path, _nav);
    },
  );
}

class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 0;
}

class _Transport implements ApiTransport {
  _Transport(this.handler);
  final Future<ApiHttpResponse> Function(Uri) handler;
  Future<ApiHttpResponse>? keys;
  final reads = <({Uri uri, Map<String, String> headers})>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    reads.add((uri: uri, headers: headers));
    if (uri.path == _nav) return keys ?? response(wbiKeyData());
    return handler(uri);
  }
}
