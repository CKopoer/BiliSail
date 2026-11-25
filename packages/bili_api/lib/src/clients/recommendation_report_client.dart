import 'dart:convert';
import 'dart:typed_data';

import '../app_profile.dart';
import '../cookies.dart';
import '../models.dart';
import '../risk_control.dart' show webUserAgent;
import '../transport.dart';

final class ApiRecommendationEvent {
  const ApiRecommendationEvent({
    required this.click,
    required this.id,
    required this.goto,
    required this.trackId,
    required this.position,
    required this.row,
    required this.column,
    required this.timestamp,
    this.cid,
    this.cardType,
    this.cardGoto,
    this.freshType,
  });

  final bool click;
  final String id, goto, trackId;
  final int position, row, column, timestamp;
  final String? cid, cardType, cardGoto;
  final int? freshType;

  Map<String, Object?> _webFields(bool desktop) => {
    (click ? 'content_id' : 'id'): int.parse(id),
    'content_type_id': int.parse(id),
    'cid': ?int.tryParse(cid ?? ''),
    'track_id': trackId,
    'goto': goto,
    'location': position,
    'line_location': row,
    'column_location': column,
    'feed_version': desktop ? 'V1' : 'V8',
  };
}

/// The homepage reporter-pb and Android Neuron consume distinct wire formats.
final class RecommendationReportClient {
  RecommendationReportClient(this._transport, this._cookies, this._clock);
  final ApiTransport _transport;
  final ApiCookieJar _cookies;
  final DateTime Function() _clock;
  static final _contentId = RegExp(r'^[1-9][0-9]{0,19}$');
  int _sequence = 0;
  late final int _startedAt = _clock().millisecondsSinceEpoch;

  Future<void> send(
    List<ApiRecommendationEvent> events, {
    bool desktop = false,
    String? appBuvid,
    String? appMid,
    required ApiRequestContext context,
  }) async {
    const endpoint = 'recommendation_report';
    if (events.isEmpty) return;
    final transport = _transport;
    if (transport is! ApiBytesTransport) {
      throw const ApiFailure(ApiFailureCategory.unavailable, endpoint);
    }
    final mobile = appBuvid != null;
    if (events.length > 32 ||
        events.any(
          (e) =>
              !_contentId.hasMatch(e.id) ||
              (!mobile && int.tryParse(e.id) == null) ||
              e.row <= 0 ||
              e.column <= 0 ||
              e.position <= 0 ||
              e.trackId.length > 2048 ||
              e.goto.length > 64 ||
              (e.cardType?.length ?? 0) > 64 ||
              (e.cardGoto?.length ?? 0) > 64,
        )) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final uri = mobile
        ? Uri.parse(
            'https://dataflow.biliapi.com/log/pbmobile/unrealtime?android',
          )
        : Uri.https('data.bilibili.com', '/v2/log/web', {
            'content_type': 'pbrequest',
            'logid': '021436',
            'disable_compression': 'true',
          });
    final now = _clock();
    const limit = Duration(seconds: 3);
    final remaining = context.deadline?.difference(now) ?? limit;
    if (context.cancellation?.isCancelled == true ||
        remaining <= Duration.zero) {
      throw const ApiFailure(ApiFailureCategory.cancelled, endpoint);
    }
    final bytes = mobile
        ? _appBatch(events, appBuvid, appMid, now.millisecondsSinceEpoch)
        : _webBatch(events, desktop, uri, now);
    final response = await (transport as ApiBytesTransport).postBytes(
      uri,
      bytes: bytes,
      contentType: mobile ? 'application/octet-stream' : 'text/plain',
      headers: mobile
          ? {
              'Neuron-Events': '${events.length}',
              'User-Agent': AppProfile.userAgent,
            }
          : {
              'Origin': 'https://www.bilibili.com',
              'Referer': 'https://www.bilibili.com/',
              'User-Agent': webUserAgent,
            },
      timeout: remaining < limit ? remaining : limit,
      cancellation: context.cancellation,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiFailure(
        ApiFailureCategory.http,
        endpoint,
        httpStatus: response.statusCode,
      );
    }
  }

  Uint8List _webBatch(
    List<ApiRecommendationEvent> events,
    bool desktop,
    Uri uri,
    DateTime now,
  ) {
    // Only attribution values read by the web reporter belong in its body.
    final cookies = <String, String>{};
    final header = _cookies.headerFor(uri, now: now) ?? '';
    for (final pair in header.split('; ')) {
      final eq = pair.indexOf('=');
      if (eq > 0) cookies[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
    final info = _Message()
      ..number(1, 100)
      ..number(2, 5);
    if (cookies['buvid3'] case final buvid?) info.string(3, buvid);
    if (int.tryParse(cookies['DedeUserID'] ?? '') case final mid?
        when mid > 0) {
      info.number(4, mid);
    }
    final batch = _Message();
    var i = 0;
    while (i < events.length) {
      final e = events[i++];
      final name = '333.1007.tianma.feed-card.${e.click ? 'click' : 'show'}';
      final fields = <String, Object?>{'is_rec': 1, 'fresh_type': ?e.freshType};
      if (e.click) {
        fields.addAll(e._webFields(desktop));
      } else {
        final shown = [e._webFields(desktop)];
        while (i < events.length &&
            !events[i].click &&
            events[i].freshType == e.freshType) {
          shown.add(events[i++]._webFields(desktop));
        }
        fields.addAll({
          'card_num': shown.length,
          'showlist': jsonEncode(shown),
        });
      }
      final detail = _Message();
      for (final field in fields.entries) {
        detail.entry(e.click ? 4 : 1, field.key, '${field.value}');
      }
      final body = _Message()
        ..message(1, info)
        ..message(2, _Message()..string(2, 'https://www.bilibili.com/'))
        ..string(3, name)
        ..string(4, '333')
        ..number(5, ++_sequence)
        ..number(6, _startedAt)
        ..number(7, e.timestamp)
        ..number(8, now.millisecondsSinceEpoch)
        ..number(9, e.click ? 1 : 2)
        ..message(e.click ? 12 : 11, detail);
      batch.message(
        1,
        _Message()
          ..string(1, '021436')
          ..string(2, name)
          ..message(3, body),
      );
    }
    return batch.bytes.takeBytes();
  }

  Uint8List _appBatch(
    List<ApiRecommendationEvent> events,
    String buvid,
    String? mid,
    int now,
  ) {
    const logId = '001538';
    final app = _Message()
      ..number(1, 5)
      ..number(2, 3)
      ..string(3, buvid)
      ..string(4, 'master');
    final runtime = _Message()
      ..string(5, '2.0.1')
      ..string(6, AppProfile.build);
    final batch = BytesBuilder(copy: false);
    for (final e in events) {
      final name = e.click
          ? 'tm.recommend.main-card.0.click'
          : 'tm.recommend.feed-card.0.show';
      final body = _Message()
        ..string(1, name)
        ..message(2, app)
        ..message(3, runtime)
        ..string(4, mid ?? '0')
        ..number(5, e.timestamp)
        ..string(6, logId)
        ..number(8, ++_sequence)
        ..number(9, e.click ? 2 : 3)
        ..message(e.click ? 11 : 12, _Message())
        ..number(14, 1)
        ..number(15, _startedAt)
        ..number(16, now);
      final extended = {
        if (e.click) 'event': 'card_click',
        'param': e.id,
        'goto': e.click ? e.cardGoto ?? e.goto : e.goto,
        'card_goto': ?e.cardGoto,
        'card_type': ?e.cardType,
        'track_id': e.trackId,
        'position': '${e.position}',
      };
      for (final field in extended.entries) {
        body.entry(13, field.key, field.value);
      }
      _writeNeuronFrame(batch, body.bytes.takeBytes(), {
        'logId': logId,
        'eventId': name,
        'appId': '5',
        'appVersionCode': AppProfile.build,
        'platform': '3',
      });
    }
    return batch.takeBytes();
  }
}

/// Neuron prefixes each AppEvent with an RDIO frame. Integers in the frame
/// are big endian; the high length bit signals another metadata entry.
void _writeNeuronFrame(
  BytesBuilder batch,
  Uint8List body,
  Map<String, String> metadata,
) {
  final payload = BytesBuilder(copy: false);
  var remaining = metadata.length;
  for (final entry in metadata.entries) {
    final key = utf8.encode(entry.key), value = utf8.encode(entry.value);
    payload.addByte(key.length);
    payload.add(key);
    final length = value.length | (--remaining > 0 ? 0x80000000 : 0);
    payload.add((ByteData(4)..setUint32(0, length)).buffer.asUint8List());
    payload.add(value);
  }
  payload.add(body);
  final length = payload.length | 0x80000000;
  var checksum = 0;
  for (var shift = 0; shift < 32; shift += 8) {
    final index = checksum ^ ((length >> shift) & 255);
    checksum = _neuronChecksum[index];
  }
  batch.add(const [0x52, 0x44, 0x49, 0x4f]);
  batch.add((ByteData(4)..setUint32(0, length)).buffer.asUint8List());
  batch.addByte(checksum);
  batch.add(payload.takeBytes());
}

final _neuronChecksum = Uint8List.fromList(
  List.generate(256, (index) {
    var result = 0xea;
    var bit = 0x3e;
    for (var mask = 1; mask <= 128; mask <<= 1) {
      if (index & mask != 0) result ^= bit;
      bit = ((bit << 1) ^ (bit & 128 != 0 ? 0x65 : 0)) & 255;
    }
    return result;
  }),
);

final class _Message {
  final bytes = BytesBuilder();
  void _varint(int value) {
    while (value >= 128) {
      bytes.addByte((value & 127) | 128);
      value >>= 7;
    }
    bytes.addByte(value);
  }

  void number(int field, int value) {
    _varint(field << 3);
    _varint(value);
  }

  void _data(int field, List<int> data) {
    _varint((field << 3) | 2);
    _varint(data.length);
    bytes.add(data);
  }

  void string(int field, String value) => _data(field, utf8.encode(value));
  void message(int field, _Message value) =>
      _data(field, value.bytes.toBytes());
  void entry(int field, String key, String value) => message(
    field,
    _Message()
      ..string(1, key)
      ..string(2, value),
  );
}
