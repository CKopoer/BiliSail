import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/live_models.dart';
import 'live_message_content.dart';

/// Bilibili packet framing inside a complete WebSocket binary message.
/// Version 3 is deliberately unsupported: this client negotiates raw/zlib (2).
final class LivePacketCodec {
  static const maxPacketBytes = 1024 * 1024;
  static const maxDecodedBytes = 8 * 1024 * 1024;
  static const maxDepth = 4;
  static const maxEvents = 500;
  static const maxPackets = 2000;

  static Uint8List encode(int operation, List<int> body) {
    if (body.length + 16 > maxPacketBytes) {
      throw const FormatException('Live packet exceeds limit');
    }
    final output = Uint8List(16 + body.length);
    final header = ByteData.sublistView(output);
    header.setUint32(0, output.length);
    header.setUint16(4, 16);
    header.setUint16(6, 1);
    header.setUint32(8, operation);
    header.setUint32(12, 1);
    output.setRange(16, output.length, body);
    return output;
  }

  static LivePacketBatch decode(Uint8List input) {
    if (input.length > maxPacketBytes) {
      throw const FormatException('Live message exceeds limit');
    }
    final decoder = _Decoder();
    decoder.read(input, 0);
    return LivePacketBatch(
      events: List.unmodifiable(decoder.events),
      authenticationCode: decoder.authenticationCode,
      heartbeatReceived: decoder.heartbeatReceived,
    );
  }
}

final class LivePacketBatch {
  const LivePacketBatch({
    this.events = const [],
    this.authenticationCode,
    this.heartbeatReceived = false,
  });
  final List<ApiLiveEvent> events;
  final int? authenticationCode;
  final bool heartbeatReceived;
}

final class _Decoder {
  final List<ApiLiveEvent> events = [];
  int? authenticationCode;
  bool heartbeatReceived = false;
  int decodedBytes = 0;
  int packets = 0;

  void read(Uint8List input, int depth) {
    if (depth > LivePacketCodec.maxDepth) {
      throw const FormatException('Live nesting exceeds limit');
    }
    var offset = 0;
    while (offset < input.length) {
      if (++packets > LivePacketCodec.maxPackets ||
          input.length - offset < 16) {
        throw const FormatException('Invalid live packet framing');
      }
      final header = ByteData.sublistView(input, offset, offset + 16);
      final length = header.getUint32(0);
      final headerLength = header.getUint16(4);
      final version = header.getUint16(6);
      final operation = header.getUint32(8);
      // Reading the sequence is part of validating the complete 16-byte header.
      header.getUint32(12);
      if (headerLength < 16 ||
          length < headerLength ||
          length > LivePacketCodec.maxPacketBytes ||
          length > input.length - offset) {
        throw const FormatException('Invalid live packet length');
      }
      final body = Uint8List.sublistView(
        input,
        offset + headerLength,
        offset + length,
      );
      offset += length;
      if (version == 2) {
        final sink = _LimitedSink(
          LivePacketCodec.maxDecodedBytes - decodedBytes,
        );
        final conversion = ZLibDecoder().startChunkedConversion(sink);
        for (var index = 0; index < body.length; index += 4096) {
          conversion.add(
            Uint8List.sublistView(
              body,
              index,
              (index + 4096).clamp(0, body.length),
            ),
          );
        }
        conversion.close();
        decodedBytes += sink.length;
        read(sink.bytes.takeBytes(), depth + 1);
        continue;
      }
      if (version != 0 && version != 1) {
        throw const FormatException('Unsupported live compression version');
      }
      if (operation == 3) {
        if (body.length < 4) throw const FormatException('Invalid heartbeat');
        heartbeatReceived = true;
        add(ApiLivePopularityChanged(ByteData.sublistView(body).getUint32(0)));
      } else if (operation == 8) {
        final data =
            body.isEmpty ? const <String, Object?>{'code': 0} : _json(body);
        final code = _int(data['code']);
        if (code == null) {
          throw const FormatException('Invalid live authentication reply');
        }
        authenticationCode = code;
      } else if (operation == 5) {
        final event = _parseCommand(_json(body));
        if (event != null) add(event);
      }
    }
  }

  void add(ApiLiveEvent event) {
    if (events.length >= LivePacketCodec.maxEvents) {
      final oldestChat = events.indexWhere(
        (item) => item is ApiLiveChatReceived,
      );
      if (oldestChat >= 0) {
        events.removeAt(oldestChat);
      } else if (event is ApiLiveChatReceived) {
        return;
      } else {
        events.removeAt(0);
      }
    }
    events.add(event);
  }
}

final class _LimitedSink implements Sink<List<int>> {
  _LimitedSink(this.limit);
  final int limit;
  final BytesBuilder bytes = BytesBuilder(copy: false);
  int length = 0;
  @override
  void add(List<int> data) {
    length += data.length;
    if (length > limit) {
      throw const FormatException('Live decompression exceeds limit');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}

Map<String, Object?> _json(Uint8List bytes) {
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, Object?>) {
    throw const FormatException('Invalid live JSON');
  }
  return value;
}

ApiLiveEvent? _parseCommand(Map<String, Object?> data) {
  final rawCommand = data['cmd'];
  if (rawCommand is! String) return null;
  final command = rawCommand.split(':').first;
  if (command == 'DANMU_MSG') {
    final info = _list(data['info']);
    if (info.length < 3) return null;
    final text = _text(info[1], 300);
    final user = _list(info[2]);
    final flags = _list(info[0]);
    if (text == null || user.length < 2) return null;
    final timestamp = flags.length > 4 ? _timestamp(flags[4]) : null;
    final name = _text(user[1], 100) ?? '';
    final metadata =
        flags.length > 15 ? _map(flags[15]) : const <String, Object?>{};
    final userId = _id(_map(metadata['user'])['uid']) ?? _id(user[0]);
    final extra = liveChatExtra(metadata['extra']);
    final color = flags.length > 3 ? _int(flags[3]) : null;
    final mode = flags.length > 1 ? _int(flags[1]) : null;
    final fontSize = flags.length > 2 ? _int(flags[2]) : null;
    return ApiLiveChatReceived(
      ApiLiveChatMessage(
        userName: name,
        userId: userId,
        text: text,
        timestamp: timestamp,
        id: 'live:${userId ?? '0'}:${timestamp?.millisecondsSinceEpoch ?? 0}:$text',
        color: color == null ? 0xffffffff : 0xff000000 | (color & 0xffffff),
        mode: mode ?? 1,
        fontSize: (fontSize ?? 24).clamp(12, 54),
        emotes: liveChatEmotes(extra['emots'], text),
        sticker: flags.length > 13 ? liveChatImage(flags[13]) : null,
      ),
    );
  }
  final payload = _map(data['data']);
  if (command == 'WATCHED_CHANGE') {
    final display = _countText(payload['text_small'], payload['num']);
    return display == null ? null : ApiLiveWatchedCountChanged(display);
  }
  if (command == 'ONLINE_RANK_COUNT') {
    // ONLINE_RANK_COUNT.count is the ranked audience, not the room's viewers.
    final display = _countText(
      payload['online_count_text'],
      payload['online_count'],
    );
    return display == null ? null : ApiLiveViewerCountChanged(display);
  }
  if (command == 'SUPER_CHAT_MESSAGE') {
    final user = _map(payload['user_info']);
    final id = _id(payload['id']);
    final price = _int(payload['price']);
    final text = _text(payload['message'], 2000);
    final name = _text(user['uname'], 100);
    if (id == null ||
        price == null ||
        price <= 0 ||
        text == null ||
        name == null) {
      return null;
    }
    return ApiLiveSuperChatReceived(
      ApiLiveSuperChatMessage(
        id: id,
        userName: name,
        userId: _id(payload['uid']),
        text: text,
        price: price,
        avatarUrl: _image(user['face']),
        startedAt: _seconds(payload['start_time']),
        expiresAt: _seconds(payload['end_time']),
        backgroundColor: _color(payload['background_color']),
        backgroundBottomColor: _color(payload['background_bottom_color']),
        textColor: _color(payload['font_color']),
      ),
    );
  }
  if (command == 'SUPER_CHAT_MESSAGE_DELETE') {
    return ApiLiveSuperChatDeleted(
      _list(payload['ids']).take(100).map(_id).whereType<String>(),
    );
  }
  if (command == 'LIVE') return const ApiLiveRoomStatusChanged(true);
  if (command == 'PREPARING') return const ApiLiveRoomStatusChanged(false);
  return null;
}

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : const {};
String? _countText(Object? display, Object? value) {
  if (display is String &&
      display.length <= 20 &&
      RegExp(r'^\d+(\.\d+)?[万亿]?$').hasMatch(display)) {
    return display;
  }
  final count = _int(value);
  return count != null && count >= 0 ? '$count' : null;
}

List<Object?> _list(Object? value) => value is List<Object?> ? value : const [];
int? _int(Object? value) =>
    value is int
        ? value
        : value is String
        ? int.tryParse(value)
        : null;
String? _id(Object? value) {
  final text =
      value is int
          ? '$value'
          : value is String
          ? value
          : null;
  return text != null && RegExp(r'^[1-9][0-9]*$').hasMatch(text) ? text : null;
}

String? _text(Object? value, int limit) =>
    value is String && value.isNotEmpty
        ? value.substring(0, value.length.clamp(0, limit))
        : null;
DateTime? _seconds(Object? value) {
  final seconds = _int(value);
  return seconds == null || seconds <= 0 || seconds > 253402300799
      ? null
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

DateTime? _timestamp(Object? value) {
  final number = _int(value);
  if (number == null || number <= 0) return null;
  final millis = number < 100000000000 ? number * 1000 : number;
  return millis > 253402300799000
      ? null
      : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}

int? _color(Object? value) {
  if (value is! String ||
      !RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(value)) {
    return null;
  }
  final color = int.parse(value.substring(1), radix: 16);
  return value.length == 7 ? 0xff000000 | color : color;
}

Uri? _image(Object? value) {
  if (value is! String || value.length > 2048) return null;
  final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  if (uri.scheme == 'https') return uri;
  if (uri.scheme == 'http' &&
      (uri.host == 'hdslb.com' || uri.host.endsWith('.hdslb.com'))) {
    return uri.replace(scheme: 'https');
  }
  return null;
}
