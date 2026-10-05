import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

final info = ApiLiveConnectionInfo(
  roomId: '12',
  token: 'fixture-key',
  buvid: 'fixture-device',
  userId: '0',
  hosts: [Uri.parse('wss://fixture.chat.bilibili.com:2245/sub')],
);

final class _Socket implements LiveSocket {
  final input = StreamController<Uint8List>();
  final sent = <Uint8List>[];
  bool respond = true, closed = false;
  int code = 0;
  @override
  Stream<Uint8List> get messages => input.stream;
  @override
  void send(Uint8List bytes) {
    sent.add(bytes);
    final op = ByteData.sublistView(bytes).getUint32(8);
    if (op == 7) {
      input.add(LivePacketCodec.encode(8, utf8.encode('{"code":$code}')));
    }
    if (op == 2 && respond) input.add(LivePacketCodec.encode(3, [0, 0, 0, 1]));
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await input.close();
  }
}

Future<void> until(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('condition timed out');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  test('closing during backoff cancels the underlying retry timer', () async {
    Timer? retry;
    await runZoned(
      () async {
        final events = <ApiLiveEvent>[];
        final session = LiveChatSession(
          loadConnectionInfo: (_) async => info,
          isCurrent: () => true,
          connector:
              (_, _) async =>
                  throw const ApiFailure(ApiFailureCategory.network, 'fixture'),
          retryDelay: (_) => const Duration(seconds: 30),
        );
        final sub = session.events.listen(events.addAll);
        await until(
          () => events.whereType<ApiLiveConnectionChanged>().any(
            (event) => event.phase == ApiLiveConnectionPhase.reconnecting,
          ),
        );
        expect(retry?.isActive, true);
        await session.close();
        await sub.cancel();
        expect(retry?.isActive, false);
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = parent.createTimer(zone, duration, callback);
          if (duration == const Duration(seconds: 30)) retry = timer;
          return timer;
        },
      ),
    );
  });
  test(
    'auth negotiates protover 2 and heartbeat without HTTP credentials',
    () async {
      final socket = _Socket();
      final events = <ApiLiveEvent>[];
      final session = LiveChatSession(
        loadConnectionInfo: (_) async => info,
        isCurrent: () => true,
        connector: (_, _) async => socket,
      );
      final sub = session.events.listen((batch) => events.addAll(batch));
      await until(
        () => events.whereType<ApiLivePopularityChanged>().isNotEmpty,
      );
      final auth =
          jsonDecode(utf8.decode(socket.sent.first.sublist(16)))
              as Map<String, Object?>;
      expect(auth['protover'], 2);
      expect(auth['roomid'], 12);
      expect(auth['uid'], 0);
      socket.input.add(
        LivePacketCodec.encode(
          5,
          utf8.encode(
            jsonEncode({
              'cmd': 'DANMU_MSG',
              'info': [
                [0, 1, 24, 0xffffff, 1791180000],
                '脱敏弹幕',
                [1, '观众'],
              ],
            }),
          ),
        ),
      );
      await until(() => events.whereType<ApiLiveChatReceived>().isNotEmpty);
      await sub.cancel();
      expect(socket.closed, true);
    },
  );
  test(
    'untrusted hosts are rejected before socket connector receives token',
    () async {
      var calls = 0;
      final bad = ApiLiveConnectionInfo(
        roomId: '12',
        token: 'fixture',
        buvid: 'device',
        userId: '0',
        hosts: [Uri.parse('wss://outside.example/sub')],
      );
      final session = LiveChatSession(
        maxAttempts: 1,
        loadConnectionInfo: (_) async => bad,
        isCurrent: () => true,
        connector: (_, _) async {
          calls++;
          return _Socket();
        },
      );
      final result = await session.events.toList();
      expect(calls, 0);
      expect(
        result
            .expand((batch) => batch)
            .whereType<ApiLiveConnectionChanged>()
            .last
            .failure,
        ApiLiveConnectionFailure.protocol,
      );
    },
  );
  test('auth rejection and rate limiting stop automatic retries', () async {
    for (final limited in [true, false]) {
      var calls = 0;
      final socket = _Socket()..code = -101;
      final session = LiveChatSession(
        loadConnectionInfo: (_) async {
          calls++;
          if (limited) {
            throw const ApiFailure(ApiFailureCategory.rateLimited, 'fixture');
          }
          return info;
        },
        isCurrent: () => true,
        connector: (_, _) async => socket,
        retryDelay: (_) => Duration.zero,
      );
      final result = await session.events.toList();
      expect(calls, 1);
      expect(
        result
            .expand((batch) => batch)
            .whereType<ApiLiveConnectionChanged>()
            .last
            .phase,
        ApiLiveConnectionPhase.failed,
      );
    }
  });
  test(
    'connection failures fetch fresh info and exhaust exactly five attempts',
    () async {
      var calls = 0;
      final session = LiveChatSession(
        loadConnectionInfo: (_) async {
          calls++;
          return info;
        },
        isCurrent: () => true,
        connector:
            (_, _) async =>
                throw const ApiFailure(ApiFailureCategory.network, 'fixture'),
        retryDelay: (_) => Duration.zero,
      );
      await session.events.toList();
      expect(calls, 5);
    },
  );
  test(
    'stable connection resets budget once and later discovery failures remain bounded',
    () async {
      var calls = 0;
      final socket = _Socket();
      final events = <ApiLiveEvent>[];
      final session = LiveChatSession(
        loadConnectionInfo: (_) async {
          calls++;
          if (calls != 5) {
            throw const ApiFailure(ApiFailureCategory.network, 'fixture');
          }
          return info;
        },
        isCurrent: () => true,
        connector: (_, _) async => socket,
        retryDelay: (_) => Duration.zero,
        heartbeatInterval: const Duration(milliseconds: 5),
        heartbeatTimeout: const Duration(milliseconds: 100),
        stableConnectionDuration: const Duration(milliseconds: 8),
      );
      final done = Completer<void>();
      final sub = session.events.listen(
        (batch) => events.addAll(batch),
        onDone: done.complete,
      );
      await until(
        () => events.whereType<ApiLivePopularityChanged>().length >= 3,
      );
      await socket.close();
      await done.future;
      expect(calls, 9);
      await sub.cancel();
    },
  );
  test('missing heartbeat times out without reconnecting forever', () async {
    final socket = _Socket()..respond = false;
    final session = LiveChatSession(
      maxAttempts: 1,
      loadConnectionInfo: (_) async => info,
      isCurrent: () => true,
      connector: (_, _) async => socket,
      heartbeatInterval: const Duration(milliseconds: 5),
      heartbeatTimeout: const Duration(milliseconds: 12),
    );
    final result = await session.events.toList();
    expect(
      result
          .expand((batch) => batch)
          .whereType<ApiLiveConnectionChanged>()
          .last
          .failure,
      ApiLiveConnectionFailure.timeout,
    );
  });
  test(
    'cancellation during isolate startup closes transport without unhandled errors',
    () async {
      final socket = _Socket();
      final opened = Completer<void>();
      final session = LiveChatSession(
        loadConnectionInfo: (_) async => info,
        isCurrent: () => true,
        connector: (_, _) async {
          opened.complete();
          return socket;
        },
      );
      final sub = session.events.listen((_) {});
      await opened.future;
      await session.close();
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(socket.closed, true);
    },
  );
  test(
    'late connect completion after cancellation is closed and never authenticated',
    () async {
      final pending = Completer<LiveSocket>();
      final called = Completer<void>();
      final socket = _Socket();
      final session = LiveChatSession(
        loadConnectionInfo: (_) async => info,
        isCurrent: () => true,
        connector: (_, _) {
          called.complete();
          return pending.future;
        },
      );
      final sub = session.events.listen((_) {});
      await called.future;
      await session.close();
      pending.complete(socket);
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(socket.closed, true);
      expect(socket.sent, isEmpty);
    },
  );
}
