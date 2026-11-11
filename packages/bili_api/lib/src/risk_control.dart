import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'transport.dart';

const webUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36';

/// Recognize challenges before DTO parsing, including successful envelopes.
ApiFailure? riskControlFailure(
  ApiHttpResponse response,
  String endpoint,
  DateTime now,
) {
  int? code;
  var verification = false;
  // Challenges are small. Do not duplicate large PGC/isolate decoding here.
  if (response.body.length <= 64 * 1024) {
    try {
      final root = jsonDecode(utf8.decode(response.body));
      if (root is Map<String, Object?>) {
        code = switch (root['code']) {
          final int value => value,
          final String value => int.tryParse(value),
          _ => null,
        };
        verification = hasRiskVoucher(root);
      }
    } on FormatException {
      // An HTTP 412 may contain an HTML challenge instead of JSON.
    }
  }
  if (!verification &&
      !const {-352, -412, -509, -799}.contains(code) &&
      !const {412, 429}.contains(response.statusCode)) {
    return null;
  }
  final raw = response.header('retry-after').firstOrNull;
  Duration? retryAfter;
  if (raw != null) {
    final seconds = int.tryParse(raw.trim());
    if (seconds != null && seconds >= 0) {
      // Bound untrusted integers before Duration arithmetic.
      retryAfter = Duration(seconds: seconds.clamp(0, 31536000));
    } else {
      try {
        final delay = HttpDate.parse(raw).difference(now.toUtc());
        retryAfter = delay.isNegative ? Duration.zero : delay;
      } on HttpException {
        // Invalid Retry-After falls back to a short local cooldown.
      }
    }
  }
  return ApiFailure(
    ApiFailureCategory.rateLimited,
    endpoint,
    httpStatus: response.statusCode,
    businessCode: code,
    retryAfter: retryAfter ?? const Duration(seconds: 30),
    requiresVerification: verification,
  );
}

bool hasRiskVoucher(Map<String, Object?> root) {
  bool contains(Map<String, Object?> value) => switch (value['v_voucher']) {
    final String voucher => voucher.isNotEmpty,
    _ => false,
  };
  if (contains(root)) return true;
  for (final key in ['data', 'result']) {
    if (root[key] case final Map<String, Object?> value) {
      if (contains(value)) return true;
    }
  }
  return false;
}

/// Cooldowns are scoped by session and destination, never by signed URLs.
final class ApiRiskControl {
  int? _epoch;
  final _cooldowns = <String, ({DateTime until, ApiFailure failure})>{};

  void check(Uri uri, String endpoint, int? epoch, DateTime now) {
    if (_epoch != epoch) {
      _epoch = epoch;
      _cooldowns.clear();
    }
    _cooldowns.removeWhere((_, value) => !value.until.isAfter(now));
    final value = _cooldowns['${uri.host}${uri.path}'];
    if (value == null) return;
    throw ApiFailure(
      ApiFailureCategory.rateLimited,
      endpoint,
      httpStatus: value.failure.httpStatus,
      businessCode: value.failure.businessCode,
      retryAfter: value.until.difference(now),
      requiresVerification: value.failure.requiresVerification,
    );
  }

  void inspect(
    Uri uri,
    String endpoint,
    ApiHttpResponse response,
    int? epoch,
    DateTime now,
  ) {
    final failure = riskControlFailure(response, endpoint, now);
    if (failure == null) return;
    if (_epoch != epoch) {
      _epoch = epoch;
      _cooldowns.clear();
    }
    if (_cooldowns.length >= 128) _cooldowns.remove(_cooldowns.keys.first);
    _cooldowns['${uri.host}${uri.path}'] = (
      until: now.add(failure.retryAfter!),
      failure: failure,
    );
    throw failure;
  }
}
