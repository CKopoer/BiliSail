import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models.dart';
import '../models/live_models.dart';
import 'live_packet_codec.dart';

abstract interface class LiveSocket {
  Stream<Uint8List> get messages;
  void send(Uint8List message);
  Future<void> close();
}

typedef LiveSocketConnector =
    Future<LiveSocket> Function(Uri uri, ApiCancellation cancellation);

/// Independently owns message transport; closing it never touches media playback.
final class LiveChatSession {
  LiveChatSession({
    required this.loadConnectionInfo,
    required this.isCurrent,
    LiveSocketConnector? connector,
    this.maxAttempts = 5,
    this.authenticationTimeout = const Duration(seconds: 12),
    this.heartbeatInterval = const Duration(seconds: 30),
    this.heartbeatTimeout = const Duration(seconds: 75),
    this.stableConnectionDuration = const Duration(seconds: 60),
    Duration Function(int)? retryDelay,
  }) : _connector = connector ?? connectLiveSocket,
       _retryDelay = retryDelay ?? _defaultDelay {
    _output = StreamController<List<ApiLiveEvent>>(
      onListen: () => unawaited(_run()),
      onCancel: close,
    );
  }

  final Future<ApiLiveConnectionInfo> Function(ApiCancellation)
  loadConnectionInfo;
  final bool Function() isCurrent;
  final LiveSocketConnector _connector;
  final Duration Function(int) _retryDelay;
  final int maxAttempts;
  final Duration authenticationTimeout, heartbeatInterval, heartbeatTimeout;
  final Duration stableConnectionDuration;
  late final StreamController<List<ApiLiveEvent>> _output;
  final Stopwatch _clock = Stopwatch()..start();
  ApiCancellation? _attemptSignal;
  LiveSocket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  _PacketWorker? _worker;
  Timer? _heartbeatTimer, _authenticationTimer, _backoffTimer;
  Completer<void>? _backoffDone;
  Completer<void>? _attemptDone;
  bool _closed = false;
  bool _authenticated = false;
  int _attemptGeneration = 0;
  Duration _lastHeartbeat = Duration.zero;
  Duration _connectedAt = Duration.zero;
  int _heartbeatReplies = 0;
  final Queue<Uint8List> _queued = Queue();
  int _queuedBytes = 0;
  bool _decoding = false;

  Stream<List<ApiLiveEvent>> get events => _output.stream;
  bool get _valid => !_closed && isCurrent();

  static Duration _defaultDelay(int failure) => Duration(
    milliseconds: min(
      30000,
      1000 * (1 << min(failure, 5)) + Random().nextInt(250),
    ),
  );

  void _emit(List<ApiLiveEvent> events) {
    if (_valid && !_output.isClosed && events.isNotEmpty) _output.add(events);
  }

  void _phase(
    ApiLiveConnectionPhase phase, {
    ApiLiveConnectionFailure? failure,
  }) => _emit([ApiLiveConnectionChanged(phase, failure: failure)]);

  Future<void> _run() async {
    var failures = 0;
    while (_valid && failures < maxAttempts) {
      try {
        await _connect(failures);
        // A disconnect is a failed attempt too; brief auth success cannot reset
        // the budget indefinitely and create a reconnect storm.
        throw const ApiFailure(ApiFailureCategory.network, 'live_socket');
      } on ApiFailure catch (error) {
        if (!_valid || error.category == ApiFailureCategory.cancelled) break;
        final failure = _classify(error.category);
        if (_stableConnection) failures = 0;
        await _releaseAttempt();
        if (error.category == ApiFailureCategory.rateLimited ||
            error.category == ApiFailureCategory.authentication ||
            error.category == ApiFailureCategory.permission) {
          _phase(ApiLiveConnectionPhase.failed, failure: failure);
          break;
        }
        failures++;
        if (failures >= maxAttempts) {
          _phase(ApiLiveConnectionPhase.failed, failure: failure);
          break;
        }
        _phase(ApiLiveConnectionPhase.reconnecting, failure: failure);
        await _backoff(failures - 1);
      } catch (_) {
        if (!_valid) break;
        if (_stableConnection) failures = 0;
        await _releaseAttempt();
        failures++;
        if (failures >= maxAttempts) {
          _phase(
            ApiLiveConnectionPhase.failed,
            failure: ApiLiveConnectionFailure.network,
          );
          break;
        }
        _phase(
          ApiLiveConnectionPhase.reconnecting,
          failure: ApiLiveConnectionFailure.network,
        );
        await _backoff(failures - 1);
      }
    }
    await _releaseAttempt();
    if (!_output.isClosed) await _output.close();
  }

  Future<T> _cancellable<T>(Future<T> operation, ApiCancellation signal) =>
      Future.any<T>([
        operation,
        signal.whenCancelled.then<T>(
          (_) =>
              throw const ApiFailure(
                ApiFailureCategory.cancelled,
                'live_socket',
              ),
        ),
      ]);

  Future<void> _backoff(int failure) async {
    if (!_valid) return;
    final done = Completer<void>();
    _backoffDone = done;
    _backoffTimer = Timer(_retryDelay(failure), done.complete);
    try {
      await done.future;
    } finally {
      _backoffTimer?.cancel();
      _backoffTimer = null;
      _backoffDone = null;
    }
  }

  bool get _stableConnection =>
      _authenticated &&
      _heartbeatReplies >= 2 &&
      _clock.elapsed - _connectedAt >= stableConnectionDuration;

  Future<void> _connect(int attempt) async {
    final generation = ++_attemptGeneration;
    final signal = ApiCancellation();
    _attemptSignal = signal;
    _phase(ApiLiveConnectionPhase.fetching);
    final info = await _cancellable(loadConnectionInfo(signal), signal);
    if (!_valid || generation != _attemptGeneration) return;
    if (info.hosts.isEmpty) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'live_socket');
    }
    final uri = info.hosts[attempt % info.hosts.length];
    if (!isTrustedLiveSocket(uri)) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'live_socket');
    }
    _phase(ApiLiveConnectionPhase.connecting);
    var accepted = true;
    final opening = _connector(uri, signal).then((socket) {
      if (!accepted || !_valid || generation != _attemptGeneration) {
        unawaited(socket.close());
        throw const ApiFailure(ApiFailureCategory.cancelled, 'live_socket');
      }
      return socket;
    });
    try {
      _socket = await _cancellable(
        opening.timeout(authenticationTimeout),
        signal,
      );
    } finally {
      accepted = false;
    }
    if (!_valid || generation != _attemptGeneration) return;
    _worker = _PacketWorker();
    await _worker?.start();
    if (!_valid || generation != _attemptGeneration) return;
    _authenticated = false;
    _heartbeatReplies = 0;
    _lastHeartbeat = _clock.elapsed;
    _attemptDone = Completer<void>();
    // Complete errors are always observed, including before the first await.
    final done = _attemptDone;
    unawaited(
      done?.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    _subscription = _socket?.messages.listen(
      (message) => _enqueue(message, generation),
      onError: (Object _, StackTrace _) => _fail(ApiFailureCategory.network),
      onDone: () => _fail(ApiFailureCategory.network),
      cancelOnError: true,
    );
    _phase(ApiLiveConnectionPhase.authenticating);
    final room = int.tryParse(info.roomId), uid = int.tryParse(info.userId);
    if (room == null || uid == null) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'live_socket');
    }
    _socket?.send(
      LivePacketCodec.encode(
        7,
        utf8.encode(
          jsonEncode({
            'uid': uid,
            'roomid': room,
            'protover': 2,
            'buvid': info.buvid,
            'platform': 'web',
            'type': 2,
            'key': info.token,
          }),
        ),
      ),
    );
    _authenticationTimer = Timer(
      authenticationTimeout,
      () => _fail(ApiFailureCategory.timeout),
    );
    if (done != null) await _cancellable(done.future, signal);
  }

  void _fail(ApiFailureCategory category) {
    final done = _attemptDone;
    if (done != null && !done.isCompleted) {
      done.completeError(ApiFailure(category, 'live_socket'));
    }
  }

  void _enqueue(Uint8List message, int generation) {
    if (!_valid || generation != _attemptGeneration) return;
    if (message.length > LivePacketCodec.maxPacketBytes ||
        _queued.length >= 8 ||
        _queuedBytes + message.length > 4 * 1024 * 1024) {
      _fail(ApiFailureCategory.protocol);
      return;
    }
    _queued.add(message);
    _queuedBytes += message.length;
    if (!_decoding) unawaited(_decodeQueue(generation));
  }

  Future<void> _decodeQueue(int generation) async {
    _decoding = true;
    try {
      while (_valid && generation == _attemptGeneration && _queued.isNotEmpty) {
        final message = _queued.removeFirst();
        _queuedBytes -= message.length;
        final worker = _worker;
        if (worker == null) break;
        final batch = await worker
            .decode(message)
            .timeout(const Duration(seconds: 5));
        if (!_valid || generation != _attemptGeneration) break;
        if (batch.authenticationCode case final code?) {
          if (code != 0) {
            _fail(ApiFailureCategory.authentication);
            return;
          }
          if (!_authenticated) {
            _authenticated = true;
            _connectedAt = _clock.elapsed;
            _authenticationTimer?.cancel();
            _authenticationTimer = null;
            _phase(ApiLiveConnectionPhase.connected);
            _socket?.send(LivePacketCodec.encode(2, const []));
            _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
              if (!_valid || generation != _attemptGeneration) return;
              if (_clock.elapsed - _lastHeartbeat > heartbeatTimeout) {
                _fail(ApiFailureCategory.timeout);
              } else {
                try {
                  _socket?.send(LivePacketCodec.encode(2, const []));
                } catch (_) {
                  _fail(ApiFailureCategory.network);
                }
              }
            });
          }
        }
        if (batch.heartbeatReceived) {
          _lastHeartbeat = _clock.elapsed;
          _heartbeatReplies++;
        }
        if (_authenticated) _emit(batch.events);
      }
    } catch (_) {
      if (_valid && generation == _attemptGeneration) {
        _fail(ApiFailureCategory.protocol);
      }
    } finally {
      if (generation == _attemptGeneration) _decoding = false;
    }
  }

  Future<void> _releaseAttempt() async {
    ++_attemptGeneration;
    _authenticated = false;
    _heartbeatReplies = 0;
    _connectedAt = Duration.zero;
    _attemptSignal?.cancel();
    _attemptSignal = null;
    _heartbeatTimer?.cancel();
    _authenticationTimer?.cancel();
    _heartbeatTimer = null;
    _authenticationTimer = null;
    _queued.clear();
    _queuedBytes = 0;
    _decoding = false;
    _worker?.close();
    _worker = null;
    final subscription = _subscription;
    _subscription = null;
    final socket = _socket;
    _socket = null;
    await subscription?.cancel();
    await socket?.close();
    _attemptDone = null;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _clock.stop();
    _backoffTimer?.cancel();
    _backoffTimer = null;
    final backoff = _backoffDone;
    if (backoff != null && !backoff.isCompleted) backoff.complete();
    await _releaseAttempt();
  }

  static ApiLiveConnectionFailure _classify(ApiFailureCategory category) =>
      switch (category) {
        ApiFailureCategory.authentication || ApiFailureCategory.permission =>
          ApiLiveConnectionFailure.authentication,
        ApiFailureCategory.rateLimited => ApiLiveConnectionFailure.limited,
        ApiFailureCategory.protocol => ApiLiveConnectionFailure.protocol,
        ApiFailureCategory.timeout => ApiLiveConnectionFailure.timeout,
        _ => ApiLiveConnectionFailure.network,
      };
}

bool isTrustedLiveSocket(Uri uri) =>
    uri.scheme == 'wss' &&
    uri.userInfo.isEmpty &&
    uri.query.isEmpty &&
    uri.fragment.isEmpty &&
    uri.path == '/sub' &&
    const {443, 2245}.contains(uri.port) &&
    uri.host.endsWith('.chat.bilibili.com');

/// Explicit no-redirect Upgrade prevents discovery tokens reaching another host.
/// HTTP Cookie headers are unnecessary here; auth uses scoped discovery data.
Future<LiveSocket> connectLiveSocket(
  Uri uri,
  ApiCancellation cancellation,
) async {
  if (!isTrustedLiveSocket(uri)) {
    throw const ApiFailure(ApiFailureCategory.protocol, 'live_socket');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  unawaited(cancellation.whenCancelled.then((_) => client.close(force: true)));
  try {
    final nonce = base64Encode(
      List.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final request = await client.getUrl(uri.replace(scheme: 'https'));
    request.followRedirects = false;
    request.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Key', nonce)
      ..set('Sec-WebSocket-Version', '13')
      ..set('Origin', 'https://live.bilibili.com')
      ..set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 BiliLite/0.1.0');
    final response = await request.close().timeout(const Duration(seconds: 12));
    final expected = base64Encode(
      sha1
          .convert(
            utf8.encode(
              '$nonce'
              '258EAFA5-E914-47DA-95CA-C5AB0DC85B11',
            ),
          )
          .bytes,
    );
    if (cancellation.isCancelled) {
      throw const ApiFailure(ApiFailureCategory.cancelled, 'live_socket');
    }
    if (response.statusCode != HttpStatus.switchingProtocols ||
        response.headers.value('Sec-WebSocket-Accept') != expected ||
        response.headers.value(HttpHeaders.upgradeHeader)?.toLowerCase() !=
            'websocket' ||
        !(response.headers[HttpHeaders.connectionHeader]?.any(
              (value) => value
                  .toLowerCase()
                  .split(',')
                  .map((part) => part.trim())
                  .contains('upgrade'),
            ) ??
            false)) {
      throw const ApiFailure(ApiFailureCategory.network, 'live_socket');
    }
    final socket = await response.detachSocket();
    return _IoLiveSocket(
      WebSocket.fromUpgradedSocket(
        socket,
        serverSide: false,
        compression: CompressionOptions.compressionOff,
        maxPayloadLength: LivePacketCodec.maxPacketBytes,
      ),
    );
  } on TimeoutException {
    throw const ApiFailure(ApiFailureCategory.timeout, 'live_socket');
  } finally {
    client.close(force: true);
  }
}

final class _IoLiveSocket implements LiveSocket {
  _IoLiveSocket(this.socket);
  final WebSocket socket;
  @override
  Stream<Uint8List> get messages => socket.map((value) {
    if (value is! List<int>) {
      throw const FormatException('Binary live message expected');
    }
    return value is Uint8List ? value : Uint8List.fromList(value);
  });
  @override
  void send(Uint8List message) => socket.add(message);
  @override
  Future<void> close() async {
    try {
      await socket.close().timeout(const Duration(seconds: 1));
    } catch (_) {
      // Socket shutdown is best effort and cannot retain the session timers.
    }
  }
}

final class _PacketWorker {
  final ReceivePort _receive = ReceivePort();
  Isolate? _isolate;
  StreamSubscription<Object?>? _subscription;
  final Completer<SendPort> _ready = Completer();
  Completer<LivePacketBatch>? _pending;
  bool _closed = false;

  Future<void> start() async {
    // Observe ready immediately: cancellation can race the Isolate.spawn await.
    final ready = _ready.future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _subscription = _receive.listen((message) {
      if (message is SendPort) {
        if (!_ready.isCompleted) _ready.complete(message);
      } else if (message is LivePacketBatch) {
        _pending?.complete(message);
        _pending = null;
      } else {
        _pending?.completeError(const FormatException('Invalid live packet'));
        _pending = null;
      }
    });
    final isolate = await Isolate.spawn(_decodeWorker, _receive.sendPort);
    if (_closed) {
      isolate.kill(priority: Isolate.immediate);
      await ready;
      return;
    }
    _isolate = isolate;
    await _ready.future;
  }

  Future<LivePacketBatch> decode(Uint8List bytes) async {
    if (_closed) throw const FormatException('Live decoder closed');
    final port = await _ready.future;
    final pending = Completer<LivePacketBatch>();
    _pending = pending;
    port.send(TransferableTypedData.fromList([bytes]));
    return pending.future;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _receive.close();
    unawaited(_subscription?.cancel());
    _pending?.completeError(const FormatException('Live decoder closed'));
    _pending = null;
    if (!_ready.isCompleted) {
      _ready.completeError(const FormatException('Live decoder closed'));
    }
  }
}

void _decodeWorker(SendPort target) {
  final input = ReceivePort();
  target.send(input.sendPort);
  input.listen((message) {
    if (message is! TransferableTypedData) return;
    try {
      target.send(LivePacketCodec.decode(message.materialize().asUint8List()));
    } catch (_) {
      target.send(false);
    }
  });
}
