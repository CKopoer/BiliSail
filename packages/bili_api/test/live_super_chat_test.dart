import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

final class _Transport implements ApiTransport {
  _Transport(this.reply);

  final Object? Function(Uri) reply;
  Uri? requested;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    requested = uri;
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode(reply(uri)))),
      const {},
    );
  }
}

void main() {
  test('guest Web GET decodes SC fields without App signing', () async {
    final transport = _Transport(
      (_) => {
        'code': 0,
        'data': {
          'list': [
            {
              'id': '9007199254740993',
              'uid': '9007199254740995',
              'message': '脱敏醒目留言',
              'price': 50,
              'start_time': 1791180000,
              'end_time': 1791180060,
              'background_color': '#336699',
              'background_bottom_color': '#AA112233',
              'font_color': '#FFFFFF',
              'user_info': {'uname': '测试观众', 'face': '//i0.hdslb.com/test.jpg'},
            },
          ],
        },
      },
    );
    final result = await LiveClient(
      BiliApiClient(transport: transport),
    ).getSuperChats('7734200');

    expect(transport.requested?.host, 'api.live.bilibili.com');
    expect(transport.requested?.path, '/av/v1/SuperChat/getMessageList');
    expect(transport.requested?.queryParameters, {'room_id': '7734200'});
    expect(result.single.id, '9007199254740993');
    expect(result.single.userId, '9007199254740995');
    expect(result.single.userName, '测试观众');
    expect(result.single.text, '脱敏醒目留言');
    expect(result.single.price, 50);
    expect(result.single.displayDuration, const Duration(seconds: 60));
    expect(result.single.avatarUrl?.scheme, 'https');
    expect(
      result.single.startedAt,
      DateTime.fromMillisecondsSinceEpoch(1791180000 * 1000, isUtc: true),
    );
    expect(
      result.single.expiresAt,
      DateTime.fromMillisecondsSinceEpoch(1791180060 * 1000, isUtc: true),
    );
    expect(result.single.backgroundColor, 0xff336699);
    expect(result.single.backgroundBottomColor, 0xaa112233);
    expect(result.single.textColor, 0xffffffff);
  });

  test(
    'HTTP and socket SC share duration fallbacks and prefer server end',
    () async {
      final start = DateTime.fromMillisecondsSinceEpoch(
        1791180000 * 1000,
        isUtc: true,
      );
      final cases =
          <
            ({
              Map<String, Object?> fields,
              DateTime? start,
              DateTime? end,
              Duration? duration,
            })
          >[
            (
              fields: {'start_time': 1791180000, 'time': '60'},
              start: start,
              end: start.add(const Duration(seconds: 60)),
              duration: const Duration(seconds: 60),
            ),
            (
              fields: {
                'start_time': 1791180000,
                'end_time': 1791180005,
                'time': 60,
              },
              start: start,
              end: start.add(const Duration(seconds: 5)),
              duration: const Duration(seconds: 5),
            ),
            for (final invalid in [86401, 1.5, 'invalid'])
              (
                fields: {'start_time': 1791180000, 'time': invalid},
                start: start,
                end: null,
                duration: null,
              ),
          ];
      for (final sample in cases) {
        final entry = <String, Object?>{
          'id': '1',
          'price': 30,
          'message': '样本',
          'user_info': {'uname': '观众'},
          'ts': 1791180000,
          ...sample.fields,
        };
        final api = BiliApiClient(
          transport: _Transport(
            (_) => {
              'code': 0,
              'data': {
                'list': [entry],
              },
            },
          ),
        );
        addTearDown(api.close);
        final http = (await LiveClient(api).getSuperChats('6')).single;
        final socket =
            (LivePacketCodec.decode(
                      LivePacketCodec.encode(
                        5,
                        utf8.encode(
                          jsonEncode({
                            'cmd': 'SUPER_CHAT_MESSAGE',
                            'data': entry,
                          }),
                        ),
                      ),
                    ).events.single
                    as ApiLiveSuperChatReceived)
                .message;
        for (final message in [http, socket]) {
          expect(message.startedAt, sample.start);
          expect(message.expiresAt, sample.end);
          expect(message.displayDuration, sample.duration);
        }
      }
    },
  );

  test(
    'HTTP time is remaining at ts while socket time is the total lifetime',
    () async {
      Future<ApiLiveSuperChatMessage> snapshot(
        Map<String, Object?> fields,
      ) async {
        final api = BiliApiClient(
          transport: _Transport(
            (_) => {
              'code': 0,
              'data': {
                'list': [
                  {
                    'id': '1',
                    'price': 30,
                    'message': '样本',
                    'user_info': {'uname': '观众'},
                    ...fields,
                  },
                ],
              },
            },
          ),
        );
        addTearDown(api.close);
        return (await LiveClient(api).getSuperChats('6')).single;
      }

      final elapsed = await snapshot({
        'start_time': 1791180000,
        'ts': 1791180020,
        'time': 40,
      });
      expect(elapsed.expiresAt?.millisecondsSinceEpoch, 1791180060000);
      expect(elapsed.displayDuration, const Duration(seconds: 60));
      expect(elapsed.remainingDuration, isNull);
      final remaining = await snapshot({'start_time': 1791180000, 'time': 40});
      expect(remaining.expiresAt, isNull);
      expect(remaining.displayDuration, isNull);
      expect(remaining.remainingDuration, const Duration(seconds: 40));
      for (final expired in [0, -10]) {
        expect(
          (await snapshot({'time': expired})).remainingDuration,
          Duration.zero,
        );
      }
      final socket =
          (LivePacketCodec.decode(
                    LivePacketCodec.encode(
                      5,
                      utf8.encode(
                        jsonEncode({
                          'cmd': 'SUPER_CHAT_MESSAGE',
                          'data': {
                            'id': '1',
                            'price': 30,
                            'message': '样本',
                            'user_info': {'uname': '观众'},
                            'time': 40,
                          },
                        }),
                      ),
                    ),
                  ).events.single
                  as ApiLiveSuperChatReceived)
              .message;
      expect(socket.expiresAt, isNull);
      expect(socket.displayDuration, const Duration(seconds: 40));
      expect(socket.remainingDuration, isNull);
    },
  );

  test('null list is empty, list is bounded, malformed item fails', () async {
    final empty = LiveClient(
      BiliApiClient(
        transport: _Transport(
          (_) => {
            'code': 0,
            'data': {'list': null},
          },
        ),
      ),
    );
    expect(await empty.getSuperChats('6'), isEmpty);

    final bounded = LiveClient(
      BiliApiClient(
        transport: _Transport(
          (_) => {
            'code': 0,
            'data': {
              'list': List.generate(
                120,
                (index) => {
                  'id': index + 1,
                  'message': 'fixture',
                  'price': 30,
                  'user_info': {'uname': '观众'},
                },
              ),
            },
          },
        ),
      ),
    );
    expect(await bounded.getSuperChats('6'), hasLength(100));

    final malformed = LiveClient(
      BiliApiClient(
        transport: _Transport(
          (_) => {
            'code': 0,
            'data': {
              'list': [
                {
                  'id': 1,
                  'message': '缺价格',
                  'user_info': {'uname': '观众'},
                },
              ],
            },
          },
        ),
      ),
    );
    await expectLater(
      malformed.getSuperChats('6'),
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.category,
          'category',
          ApiFailureCategory.protocol,
        ),
      ),
    );
    expect(() => empty.getSuperChats('6&extra=1'), throwsArgumentError);
  });
}
