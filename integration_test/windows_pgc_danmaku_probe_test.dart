import 'dart:convert';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Explicit local Windows read probe. Credentials stay in the system store and
/// the in-memory cookie jar; prints only public IDs, counts and error categories.
/// flutter test integration_test/windows_pgc_danmaku_probe_test.dart -d windows
///   --dart-define=BILI_PGC_SAVED_SESSION=true
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('read selected PGC comments with the saved Web session', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('BILI_PGC_SAVED_SESSION')) return;
    final transport = _ProbeTransport();
    final api = BiliApiClient(transport: transport);
    addTearDown(() {
      api.close();
      transport.inner.close();
    });
    final saved = await SystemCredentialStore().read();
    debugPrint(jsonEncode({'savedSessionAvailable': saved != null}));
    if (saved == null) return;
    final Object? decoded = jsonDecode(saved);
    if (decoded is! Map<String, Object?> ||
        decoded['version'] != 1 ||
        decoded['cookies'] is! Map<String, Object?>) {
      throw StateError('Unsupported secure session snapshot');
    }
    api.cookieJar.restoreFromSecureStorage(
      decoded['cookies'] as Map<String, Object?>,
    );
    final season = await PgcClient(api).getSeason(episodeId: '323085');
    var failures = 0;
    for (final episode in season.episodes.take(2)) {
      final cid = episode.cid;
      if (cid == null) continue;
      try {
        final comments = await api.getDanmakuSegment(cid, 1);
        debugPrint(
          jsonEncode({
            'episodeId': episode.episodeId,
            'cid': cid,
            'count': comments.length,
          }),
        );
      } on ApiFailure catch (error) {
        failures++;
        debugPrint(
          jsonEncode({
            'episodeId': episode.episodeId,
            'cid': cid,
            'endpoint': error.endpointId,
            'category': error.category.name,
            'businessCode': error.businessCode,
            'httpStatus': error.httpStatus,
          }),
        );
      }
    }
    expect(failures, 0, reason: 'Dense signed-in pools must remain readable');
  });
}

final class _ProbeTransport implements ApiTransport {
  final inner = DioApiTransport();
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final response = await inner.get(
      uri,
      headers: headers,
      timeout: timeout,
      cancellation: cancellation,
    );
    if (uri.path == '/x/v2/dm/web/seg.so') {
      debugPrint(
        jsonEncode({
          'endpoint': 'danmaku_segment',
          'status': response.statusCode,
          'bytes': response.body.length,
          ..._elementStats(response.body),
        }),
      );
    }
    return response;
  }
}

Map<String, int> _elementStats(List<int> body) {
  var offset = 0;
  var count = 0, maxBytes = 0;
  int varint() {
    var value = 0;
    for (var shift = 0; shift < 64 && offset < body.length; shift += 7) {
      final byte = body[offset++];
      value |= (byte & 127) << shift;
      if (byte & 128 == 0) return value;
    }
    throw StateError('Invalid Protobuf framing');
  }

  while (offset < body.length) {
    final tag = varint();
    switch (tag & 7) {
      case 0:
        varint();
      case 1:
        offset += 8;
      case 2:
        final length = varint();
        if (tag >> 3 == 1) {
          count++;
          if (length > maxBytes) maxBytes = length;
        }
        offset += length;
      case 5:
        offset += 4;
      default:
        throw StateError('Invalid Protobuf wire type');
    }
    if (offset > body.length) throw StateError('Truncated Protobuf');
  }
  return {'elements': count, 'maxElementBytes': maxBytes};
}
