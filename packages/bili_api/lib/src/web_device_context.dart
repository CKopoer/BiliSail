import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cookies.dart';
import 'models.dart';
import 'risk_control.dart';
import 'transport.dart';

final class _DeviceFlight {
  _DeviceFlight(this.epoch, this.generation);
  final int? epoch;
  final int generation;
  final cancellation = ApiCancellation();
  late final Future<void> result;
}

/// One server-issued Web identity, shared by concurrent callers.
final class WebDeviceContext {
  WebDeviceContext({
    required this.transport,
    required this.cookies,
    required this.epoch,
    required this.clock,
    required this.riskControl,
    required this.timeout,
    this.load,
    this.save,
  });

  final ApiTransport transport;
  final ApiCookieJar cookies;
  final int? Function() epoch;
  final DateTime Function() clock;
  final ApiRiskControl riskControl;
  final Duration timeout;
  final Future<Map<String, String>?> Function()? load;
  final Future<void> Function(Map<String, String>)? save;
  _DeviceFlight? _flight;
  ({int? epoch, int generation, String device})? _ready;
  bool _closed = false;
  static final origin = Uri.https('api.bilibili.com', '/');
  // SPI buvid4 uses Base64 characters, including '+', '/' and '='.
  static final _cookieValue = RegExp(r'^[A-Za-z0-9_+/.=-]{1,200}$');

  void close() {
    _closed = true;
    _flight?.cancellation.cancel();
  }

  Future<void> ensure(ApiRequestContext context) async {
    const endpoint = 'web_device';
    final currentEpoch = epoch();
    final generation = cookies.generation;
    void check() {
      if (_closed ||
          context.cancellation?.isCancelled == true ||
          epoch() != currentEpoch ||
          cookies.generation != generation ||
          (context.sessionEpoch != null &&
              context.sessionEpoch != currentEpoch)) {
        throw const ApiFailure(ApiFailureCategory.cancelled, endpoint);
      }
      if (!context.deadline!.isAfter(clock())) {
        throw const ApiFailure(ApiFailureCategory.timeout, endpoint);
      }
    }

    check();
    final device = _values(cookies.headerFor(origin, now: clock()));
    if (_ready ==
        (
          epoch: currentEpoch,
          generation: generation,
          device: '${device['buvid3']}:${device['buvid4']}',
        )) {
      return;
    }
    var flight = _flight;
    if (flight == null ||
        flight.epoch != currentEpoch ||
        flight.generation != generation) {
      flight?.cancellation.cancel();
      flight = _DeviceFlight(currentEpoch, generation);
      _flight = flight;
      final active = flight;
      active.result = _initialize(active)
          .timeout(
            timeout,
            onTimeout: () {
              active.cancellation.cancel();
              throw const ApiFailure(ApiFailureCategory.timeout, endpoint);
            },
          )
          .whenComplete(() {
            if (identical(_flight, active)) _flight = null;
          });
    }
    try {
      await Future.any<void>([
        flight.result,
        if (context.cancellation case final cancellation?)
          cancellation.whenCancelled.then(
            (_) =>
                throw const ApiFailure(ApiFailureCategory.cancelled, endpoint),
          ),
      ]).timeout(context.deadline!.difference(clock()));
      check();
    } on TimeoutException {
      throw const ApiFailure(ApiFailureCategory.timeout, endpoint);
    }
  }

  Future<void> _initialize(_DeviceFlight flight) async {
    const endpoint = 'web_device';
    final deadline = clock().add(timeout);
    void check() {
      if (_closed ||
          flight.cancellation.isCancelled ||
          flight.epoch != epoch() ||
          flight.generation != cookies.generation) {
        throw const ApiFailure(ApiFailureCategory.cancelled, endpoint);
      }
      if (!deadline.isAfter(clock())) {
        throw const ApiFailure(ApiFailureCategory.timeout, endpoint);
      }
    }

    // Persistence only sees device fields, never session credentials.
    riskControl.check(
      origin.replace(path: '/x/internal/gaia-gateway/ExClimbWuzhi'),
      endpoint,
      flight.epoch,
      clock(),
    );
    var device = _values(cookies.headerFor(origin, now: clock()));
    if (!_valid(device)) {
      final stored = await load?.call();
      check();
      if (stored != null && _valid(stored)) device = stored;
    }
    Future<Map<String, Object?>> send(
      Uri uri, {
      Map<String, Object?>? body,
    }) async {
      check();
      riskControl.check(uri, endpoint, flight.epoch, clock());
      final temporary = ApiCookieJar()
        ..restoreFromSecureStorage(
          cookies.exportForSecureStorage(),
          now: clock(),
        );
      temporary.receive(origin, _cookieLines(device), now: clock());
      final headers = {
        'User-Agent': webUserAgent,
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com',
        'Accept': 'application/json',
        'Cookie': ?temporary.headerFor(uri, now: clock()),
      };
      final remaining = deadline.difference(clock());
      try {
        final operation = body == null
            ? transport.get(
                uri,
                headers: headers,
                timeout: remaining,
                cancellation: flight.cancellation,
              )
            : transport is ApiJsonTransport
            ? (transport as ApiJsonTransport).postJson(
                uri,
                body: body,
                headers: headers,
                timeout: remaining,
                cancellation: flight.cancellation,
              )
            : throw const ApiFailure(ApiFailureCategory.unavailable, endpoint);
        final response = await Future.any<ApiHttpResponse>([
          operation,
          flight.cancellation.whenCancelled.then(
            (_) =>
                throw const ApiFailure(ApiFailureCategory.cancelled, endpoint),
          ),
        ]).timeout(remaining);
        check();
        riskControl.inspect(uri, endpoint, response, flight.epoch, clock());
        if (response.statusCode != 200 || response.body.length > 64 * 1024) {
          throw ApiFailure(
            ApiFailureCategory.http,
            endpoint,
            httpStatus: response.statusCode,
          );
        }
        final root = jsonDecode(utf8.decode(response.body));
        if (root is! Map<String, Object?> || root['code'] != 0) {
          throw const ApiFailure(ApiFailureCategory.unavailable, endpoint);
        }
        return root['data'] is Map<String, Object?>
            ? root['data'] as Map<String, Object?>
            : const {};
      } on TimeoutException {
        flight.cancellation.cancel();
        throw const ApiFailure(ApiFailureCategory.timeout, endpoint);
      } on FormatException {
        throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
    }

    if (!_valid(device)) {
      final data = await send(origin.replace(path: '/x/frontend/finger/spi'));
      device = {
        if (data['b_3'] case final String value) 'buvid3': value,
        if (data['b_4'] case final String value) 'buvid4': value,
        'b_nut': '${clock().millisecondsSinceEpoch ~/ 1000}',
      };
      if (!_valid(device)) {
        throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
    }
    if (!RegExp(r'^[0-9]{1,12}$').hasMatch(device['b_nut'] ?? '')) {
      device = {
        ...device,
        'b_nut': '${clock().millisecondsSinceEpoch ~/ 1000}',
      };
    }
    await send(
      origin.replace(path: '/x/internal/gaia-gateway/ExClimbWuzhi'),
      body: {
        'payload': jsonEncode({
          '3064': 1,
          '39c8': '333.1007.fp.risk',
          // Report the real OS; do not invent canvas/browser fingerprints.
          '3c43': {'adca': Platform.operatingSystem},
        }),
      },
    );
    check();
    final filtered = {
      for (final key in ['buvid3', 'buvid4', 'b_nut']) key: ?device[key],
    };
    await save?.call(filtered).timeout(deadline.difference(clock()));
    check();
    cookies.receive(origin, _cookieLines(filtered), now: clock());
    _ready = (
      epoch: flight.epoch,
      generation: flight.generation,
      device: '${device['buvid3']}:${device['buvid4']}',
    );
  }

  static bool _valid(Map<String, String> values) => [
    'buvid3',
    'buvid4',
  ].every((key) => _cookieValue.hasMatch(values[key] ?? ''));

  static Iterable<String> _cookieLines(Map<String, String> values) sync* {
    for (final key in ['buvid3', 'buvid4', 'b_nut']) {
      final value = values[key];
      if (value != null && _cookieValue.hasMatch(value)) {
        yield '$key=$value; Domain=.bilibili.com; Path=/; Secure';
      }
    }
  }

  static Map<String, String> _values(String? header) => {
    for (final pair in header?.split('; ') ?? <String>[])
      if (pair.indexOf('=') case final index when index > 0)
        pair.substring(0, index): pair.substring(index + 1),
  };
}
