import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

ApiLiveConnectionInfo _connectionInfo() => ApiLiveConnectionInfo(
  roomId: '123',
  token: 'fixture-token',
  buvid: 'fixture-device',
  userId: '0',
  hosts: [Uri.parse('wss://fixture.chat.bilibili.com:443/sub')],
);

final class _Socket implements LiveSocket {
  _Socket({this.replyToHeartbeat = true});

  final bool replyToHeartbeat;
  final StreamController<Uint8List> _incoming = StreamController();
  int closeCount = 0;
  final List<int> sentOperations = [];

  @override
  Stream<Uint8List> get messages => _incoming.stream;

  @override
  void send(Uint8List bytes) {
    final operation = ByteData.sublistView(bytes).getUint32(8);
    sentOperations.add(operation);
    if (_incoming.isClosed) throw StateError('Fixture socket is closed');
    if (operation == 7) {
      _incoming.add(LivePacketCodec.encode(8, utf8.encode('{"code":0}')));
    } else if (operation == 2 && replyToHeartbeat) {
      _incoming.add(LivePacketCodec.encode(3, [0, 0, 0, 1]));
    }
  }

  Future<void> disconnect() => _incoming.close();

  @override
  Future<void> close() {
    closeCount++;
    return _incoming.close();
  }
}

void main() {
  test('cancelling during worker startup observes every pending error', () async {
    final uncaught = <Object>[];
    final finished = Completer<void>();
    runZonedGuarded<void>(() {
      unawaited(
        () async {
          // The connector's timer runs after its completed Future is accepted but
          // while the newly spawned decoding isolate is still being initialized.
          for (var iteration = 0; iteration < 20; iteration++) {
            final socket = _Socket();
            late LiveChatSession session;
            final ended = Completer<void>();
            session = LiveChatSession(
              loadConnectionInfo: (_) async => _connectionInfo(),
              isCurrent: () => true,
              connector: (_, _) async {
                Timer.run(() => unawaited(session.close()));
                return socket;
              },
              retryDelay: (_) => Duration.zero,
              maxAttempts: 1,
            );
            final subscription = session.events.listen(
              (_) {},
              onDone: ended.complete,
            );
            try {
              await ended.future.timeout(const Duration(seconds: 3));
              expect(socket.closeCount, 1);
            } finally {
              await session.close();
              await subscription.cancel();
            }
          }
          // Let errors scheduled by the last worker cancellation reach the zone.
          await Future<void>.delayed(Duration.zero);
        }().then<void>(
          (_) => finished.complete(),
          onError:
              (Object error, StackTrace stack) =>
                  finished.completeError(error, stack),
        ),
      );
    }, (error, _) => uncaught.add(error));

    await finished.future.timeout(const Duration(seconds: 10));
    expect(uncaught, isEmpty);
  });

  test(
    'stable connection resets the budget once before discovery failures',
    () async {
      var discoveryCount = 0;
      var heartbeatReplies = 0;
      final socket = _Socket();
      final phases = <ApiLiveConnectionPhase>[];
      final ended = Completer<void>();
      final session = LiveChatSession(
        loadConnectionInfo: (_) async {
          discoveryCount++;
          if (discoveryCount != 4) {
            throw const ApiFailure(
              ApiFailureCategory.network,
              'fixture_discovery',
            );
          }
          return _connectionInfo();
        },
        isCurrent: () => true,
        connector: (_, _) async => socket,
        retryDelay: (_) => Duration.zero,
        stableConnectionDuration: Duration.zero,
        heartbeatInterval: const Duration(milliseconds: 5),
        heartbeatTimeout: const Duration(seconds: 1),
      );
      final subscription = session.events.listen((batch) {
        for (final event in batch) {
          if (event is ApiLiveConnectionChanged) phases.add(event.phase);
          if (event is ApiLivePopularityChanged && ++heartbeatReplies == 2) {
            unawaited(socket.disconnect());
          }
        }
      }, onDone: ended.complete);

      try {
        await ended.future.timeout(const Duration(seconds: 3));
        // Three initial failures, one stable connection, then four failed reads:
        // the stable connection's disconnect is the first new failed attempt.
        expect(discoveryCount, 8);
        expect(heartbeatReplies, greaterThanOrEqualTo(2));
        expect(
          phases.where((phase) => phase == ApiLiveConnectionPhase.connected),
          hasLength(1),
        );
        expect(phases.last, ApiLiveConnectionPhase.failed);
        expect(socket.closeCount, 1);
      } finally {
        await session.close();
        await subscription.cancel();
      }
    },
  );

  test(
    'brief authentication success cannot restart reconnects forever',
    () async {
      final sockets = <_Socket>[];
      final phases = <ApiLiveConnectionPhase>[];
      final ended = Completer<void>();
      var discoveryCount = 0;
      final session = LiveChatSession(
        loadConnectionInfo: (_) async {
          discoveryCount++;
          return _connectionInfo();
        },
        isCurrent: () => true,
        connector: (_, _) async {
          final socket = _Socket(replyToHeartbeat: false);
          sockets.add(socket);
          return socket;
        },
        retryDelay: (_) => Duration.zero,
        stableConnectionDuration: const Duration(days: 1),
      );
      final subscription = session.events.listen((batch) {
        for (final event in batch.whereType<ApiLiveConnectionChanged>()) {
          phases.add(event.phase);
          if (event.phase == ApiLiveConnectionPhase.connected) {
            unawaited(sockets.last.disconnect());
          }
        }
      }, onDone: ended.complete);

      try {
        await ended.future.timeout(const Duration(seconds: 3));
        expect(discoveryCount, 5);
        expect(sockets, hasLength(5));
        expect(
          phases.where((phase) => phase == ApiLiveConnectionPhase.connected),
          hasLength(5),
        );
        expect(phases.last, ApiLiveConnectionPhase.failed);
        expect(sockets.every((socket) => socket.closeCount == 1), isTrue);
      } finally {
        await session.close();
        await subscription.cancel();
      }
    },
  );

  test(
    'account cancellation closes a connected socket without reconnecting',
    () async {
      final account = ApiCancellation();
      final socket = _Socket();
      final ended = Completer<void>();
      var discoveryCount = 0;
      ApiCancellation? attemptSignal;
      final session = LiveChatSession(
        loadConnectionInfo: (signal) async {
          discoveryCount++;
          attemptSignal = signal;
          return _connectionInfo();
        },
        isCurrent: () => !account.isCancelled,
        connector: (_, _) async => socket,
        retryDelay: (_) => Duration.zero,
        heartbeatInterval: const Duration(milliseconds: 5),
      );
      // The owning account scope signals closure, just as repository lifetime
      // cancellation does; isCurrent also prevents late batches from escaping.
      unawaited(account.whenCancelled.then((_) => session.close()));
      final subscription = session.events.listen((batch) {
        if (batch.whereType<ApiLiveConnectionChanged>().any(
          (event) => event.phase == ApiLiveConnectionPhase.connected,
        )) {
          account.cancel();
        }
      }, onDone: ended.complete);

      try {
        await ended.future.timeout(const Duration(seconds: 3));
        final sendsAtClose = socket.sentOperations.length;
        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(socket.closeCount, 1);
        expect(attemptSignal?.isCancelled, isTrue);
        expect(discoveryCount, 1);
        expect(socket.sentOperations, hasLength(sendsAtClose));
      } finally {
        account.cancel();
        await session.close();
        await subscription.cancel();
      }
    },
  );

  test(
    'account switch closes a late connector result before authentication',
    () async {
      final opening = Completer<LiveSocket>();
      final connectorEntered = Completer<void>();
      final ended = Completer<void>();
      final socket = _Socket();
      var current = true;
      ApiCancellation? attemptSignal;
      final session = LiveChatSession(
        loadConnectionInfo: (_) async => _connectionInfo(),
        isCurrent: () => current,
        connector: (_, signal) {
          attemptSignal = signal;
          connectorEntered.complete();
          return opening.future;
        },
        retryDelay: (_) => Duration.zero,
      );
      final subscription = session.events.listen(
        (_) {},
        onDone: ended.complete,
      );
      try {
        await connectorEntered.future.timeout(const Duration(seconds: 3));
        current = false;
        await session.close();
        opening.complete(socket);
        await ended.future.timeout(const Duration(seconds: 3));
        await Future<void>.delayed(Duration.zero);
        expect(attemptSignal?.isCancelled, isTrue);
        expect(socket.closeCount, 1);
        expect(socket.sentOperations, isEmpty);
      } finally {
        if (!opening.isCompleted) opening.complete(socket);
        await session.close();
        await subscription.cancel();
      }
    },
  );
}
