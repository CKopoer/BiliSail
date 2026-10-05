import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

Uint8List command(Object data) =>
    LivePacketCodec.encode(5, utf8.encode(jsonEncode(data)));
Uint8List compressed(Uint8List data) {
  final packet = LivePacketCodec.encode(5, ZLibEncoder().convert(data));
  ByteData.sublistView(packet).setUint16(6, 2);
  return packet;
}

Map<String, Object?> chat(int index) => {
  'cmd': 'DANMU_MSG:4:0:2',
  'info': [
    [0, 1, 36, 0x123456, 1791180000123 + index],
    '测试弹幕 $index',
    [123, '测试观众'],
  ],
};

void main() {
  test('raw merged packets preserve auth, heartbeat and chat metadata', () {
    final pop = Uint8List(4);
    ByteData.sublistView(pop).setUint32(0, 1250);
    final input = Uint8List.fromList([
      ...LivePacketCodec.encode(8, utf8.encode('{"code":0}')),
      ...LivePacketCodec.encode(3, pop),
      ...command(chat(0)),
    ]);
    final result = LivePacketCodec.decode(input);
    expect(result.authenticationCode, 0);
    expect(result.heartbeatReceived, true);
    final message =
        result.events.whereType<ApiLiveChatReceived>().single.message;
    expect(message.text, '测试弹幕 0');
    expect(message.color, 0xff123456);
    expect(message.fontSize, 36);
    expect(message.userId, '123');
    expect(message.timestamp?.millisecondsSinceEpoch, 1791180000123);
  });
  test(
    'socket chat keeps full UID, inline emotes and bounded sticker metadata',
    () {
      final flags = List<Object?>.filled(16, null);
      flags[4] = 1791180000;
      flags[13] = {
        'url': '//i0.hdslb.com/sticker.png',
        'width': 10000,
        'height': 0,
      };
      flags[15] = {
        'user': {'uid': '9007199254740993'},
        'extra': jsonEncode({
          'emots': {
            '[笑]': {
              'url': 'http://i0.hdslb.com/smile.png',
              'width': 30,
              'height': 24,
            },
            '[坏]': {'url': 'javascript:bad'},
            '[未使用]': {'url': 'https://i0.hdslb.com/unused.png'},
          },
        }),
      };
      final result = LivePacketCodec.decode(
        command({
          'cmd': 'DANMU_MSG',
          'info': [
            flags,
            '你好[笑][坏]',
            [123, '测试观众'],
          ],
        }),
      );
      final message = (result.events.single as ApiLiveChatReceived).message;
      expect(message.userId, '9007199254740993');
      expect(message.emotes.keys, ['[笑]']);
      expect(message.emotes['[笑]']?.url.scheme, 'https');
      expect(message.sticker?.width, 4096);
      expect(message.sticker?.height, 24);
      expect(() => message.emotes.clear(), throwsUnsupportedError);
    },
  );
  test(
    'malformed optional rich data preserves text and valid UID fallback',
    () {
      for (final extra in ['{invalid', 'x' * (64 * 1024 + 1), null]) {
        final flags = List<Object?>.filled(16, null);
        flags[13] = {'url': 'http://untrusted.example/sticker.png'};
        flags[15] = {
          'extra': extra,
          'user': {'uid': 0},
        };
        final result = LivePacketCodec.decode(
          command({
            'cmd': 'DANMU_MSG',
            'info': [
              flags,
              '普通文字',
              ['9007199254740993', '观众'],
            ],
          }),
        );
        final message = (result.events.single as ApiLiveChatReceived).message;
        expect(message.userId, '9007199254740993');
        expect(message.text, '普通文字');
        expect(message.sticker, isNull);
        expect(message.emotes, isEmpty);
      }
    },
  );
  test(
    'viewer messages use online display and never the ranked or popularity count',
    () {
      final result = LivePacketCodec.decode(
        Uint8List.fromList([
          ...command({
            'cmd': 'WATCHED_CHANGE',
            'data': {'num': 1200},
          }),
          ...command({
            'cmd': 'ONLINE_RANK_COUNT',
            'data': {
              'count': 8,
              'online_count': 23000,
              'online_count_text': '2.3万',
            },
          }),
          ...command({
            'cmd': 'ONLINE_RANK_COUNT',
            'data': {'online_count': 0},
          }),
          ...command({
            'cmd': 'ONLINE_RANK_COUNT',
            'data': {'count': 8},
          }),
          ...command({
            'cmd': 'WATCHED_CHANGE',
            'data': {'num': -1},
          }),
          ...command({
            'cmd': 'WATCHED_CHANGE',
            'data': {'text_small': 'bad'},
          }),
        ]),
      );
      expect(
        result.events.whereType<ApiLiveViewerCountChanged>().map(
          (e) => e.countText,
        ),
        ['1200', '2.3万', '0'],
      );
    },
  );
  test('zlib nested merged packets are decoded by their framing', () {
    final result = LivePacketCodec.decode(
      compressed(
        Uint8List.fromList([...command(chat(0)), ...command(chat(1))]),
      ),
    );
    expect(result.events.whereType<ApiLiveChatReceived>(), hasLength(2));
  });
  test('inline metadata retains at most fifty used emotes', () {
    final tokens = List.generate(60, (index) => '[$index]');
    final flags = List<Object?>.filled(16, null);
    flags[15] = {
      'extra': jsonEncode({
        'emots': {
          for (final token in tokens)
            token: {'url': '//i0.hdslb.com/fixture.png'},
        },
      }),
    };
    final result = LivePacketCodec.decode(
      command({
        'cmd': 'DANMU_MSG',
        'info': [
          flags,
          tokens.join(),
          [123, '观众'],
        ],
      }),
    );
    expect(
      (result.events.single as ApiLiveChatReceived).message.emotes.length,
      50,
    );
  });
  test('SC, deletion, status and unsupported commands have typed events', () {
    final result = LivePacketCodec.decode(
      Uint8List.fromList([
        ...command({
          'cmd': 'SUPER_CHAT_MESSAGE',
          'data': {
            'id': '9007199254740993',
            'uid': '9007199254740995',
            'price': 500,
            'message': '脱敏SC',
            'start_time': 1791180000,
            'end_time': 1791180060,
            'background_color': '#336699',
            'user_info': {'uname': '测试观众', 'face': '//i0.hdslb.com/test.jpg'},
          },
        }),
        ...command({
          'cmd': 'SUPER_CHAT_MESSAGE_DELETE',
          'data': {
            'ids': ['9007199254740993'],
          },
        }),
        ...command({'cmd': 'PREPARING'}),
        ...command({'cmd': 'UNKNOWN'}),
      ]),
    );
    expect(result.events, hasLength(3));
    expect(
      result.events.whereType<ApiLiveSuperChatReceived>().single.message.price,
      500,
    );
    expect(
      result.events.whereType<ApiLiveSuperChatReceived>().single.message.userId,
      '9007199254740995',
    );
    expect(result.events.whereType<ApiLiveSuperChatDeleted>().single.ids, [
      '9007199254740993',
    ]);
    expect(
      result.events.whereType<ApiLiveRoomStatusChanged>().single.isLive,
      false,
    );
  });
  test('truncation, illegal header and unknown compression fail closed', () {
    for (final bytes in [
      Uint8List(5),
      command(chat(0))..[5] = 0,
      command(chat(0))..[7] = 3,
    ]) {
      expect(() => LivePacketCodec.decode(bytes), throwsFormatException);
    }
    final packet = command(chat(0));
    expect(
      () => LivePacketCodec.decode(
        Uint8List.sublistView(packet, 0, packet.length - 1),
      ),
      throwsFormatException,
    );
  });
  test('expanded bytes and nested recursion are bounded', () {
    expect(
      () => LivePacketCodec.decode(
        compressed(Uint8List(LivePacketCodec.maxDecodedBytes + 1)),
      ),
      throwsFormatException,
    );
    var nested = command(chat(0));
    for (var i = 0; i <= LivePacketCodec.maxDepth; i++) {
      nested = compressed(nested);
    }
    expect(() => LivePacketCodec.decode(nested), throwsFormatException);
  });
  test('chat batch drops oldest messages and preserves control events', () {
    final input = Uint8List.fromList([
      for (var i = 0; i < 520; i++) ...command(chat(i)),
      ...command({'cmd': 'PREPARING'}),
    ]);
    final result = LivePacketCodec.decode(input);
    expect(result.events, hasLength(500));
    expect(result.events.last, isA<ApiLiveRoomStatusChanged>());
    expect(
      result.events.whereType<ApiLiveChatReceived>().first.message.text,
      '测试弹幕 21',
    );
  });
}
