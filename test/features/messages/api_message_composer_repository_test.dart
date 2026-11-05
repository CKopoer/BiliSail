import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/messages/data/api_message_repository.dart';
import 'package:bilisail/features/messages/domain/message_composer.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Transport transport;
  late ApiRequests requests;
  late ApiMessageRepository repository;
  setUp(() {
    transport = _Transport();
    requests = ApiRequests();
    repository = ApiMessageRepository(
      MessageClient(
        BiliApiClient(
          transport: transport,
          sessionProvider: requests,
          cookieJar: ApiCookieJar()
            ..receive(Uri.https('api.bilibili.com', '/'), [
              'SESSDATA=fixture; Domain=.bilibili.com; Path=/; Secure',
              'bili_jct=csrf-fixture; Domain=.bilibili.com; Path=/; Secure',
            ]),
        ),
      ),
      requests,
      accountScope: () => 'user:1',
    );
  });
  const entry = InboxEntry(
    id: '1:2',
    title: '会话',
    text: '',
    userId: UserId('2'),
    sessionType: 1,
  );
  MessageLocalImage image() => MessageLocalImage(
    bytes: Uint8List.fromList([1, 2, 3]),
    mimeType: 'image/png',
  );

  test(
    'notification reply context and emotes cross the domain boundary together',
    () async {
      transport.data = {
        'items': [
          {
            'id': '9',
            'user': {'mid': '2', 'nickname': '用户'},
            'item': {
              'subject_id': '42',
              'business_id': 1,
              'source_id': '19',
              'root_id': '17',
              'source_content': '正文[doge]',
              'emoticon': {
                '[doge]': {'url': '//i0.hdslb.com/doge.png'},
              },
            },
          },
        ],
        'cursor': {'id': 9, 'time': 0, 'is_end': true},
      };
      final row = (await repository.inbox(
        InboxSection.replies,
        cancellation: RequestCancellation(),
      )).items.single;
      expect(row.replyContext?.subjectId, '42');
      expect(row.replyContext?.rootId, '17');
      expect(row.replyContext?.parentId, '19');
      expect(row.replyContext?.userId, const UserId('2'));
      expect(row.emotes['[doge]']?.path, '/doge.png');
    },
  );

  test(
    'message-specific emotes and IM panel retain their dedicated shape',
    () async {
      transport.data = {
        'messages': [
          {
            'msg_seqno': '1',
            'sender_uid': '2',
            'msg_type': 1,
            'content': jsonEncode({'content': '正文[doge]'}),
          },
        ],
        'e_infos': [
          {'text': '[doge]', 'url': '//i0.hdslb.com/doge.png'},
        ],
        'has_more': 0,
      };
      final message = (await repository.thread(
        entry,
        cancellation: RequestCancellation(),
      )).items.single;
      expect(message.emotes['[doge]']?.path, '/doge.png');
      transport.data = {
        'packages': [
          {
            'text': '默认',
            'emote': [
              {'text': '[doge]', 'url': '//i0.hdslb.com/doge.png'},
            ],
          },
        ],
      };
      final packages = await repository.emotes(
        cancellation: RequestCancellation(),
      );
      expect(packages.single.name, '默认');
      expect(packages.single.items.single.text, '[doge]');
    },
  );

  test(
    'upload success sends exactly one image into the captured conversation',
    () async {
      await repository.sendImage(
        entry,
        image(),
        cancellation: RequestCancellation(),
      );
      expect(transport.uploads, 1);
      expect(transport.sends, 1);
      expect(transport.fields['msg[sender_uid]'], '1');
      expect(transport.fields['msg[receiver_id]'], '2');
      expect(transport.fields['msg[msg_type]'], '2');
    },
  );

  test('cancellation and epoch change between upload and send prevent the second write', () async {
    for (final cancelByEpoch in [false, true]) {
      transport.uploadPending = Completer<ApiHttpResponse>();
      final cancellation = RequestCancellation();
      final sending = repository.sendImage(
        entry,
        image(),
        cancellation: cancellation,
      );
      final expectation = expectLater(
        sending,
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            AppFailureKind.cancelled,
          ),
        ),
      );
      if (cancelByEpoch) {
        requests.advanceSession();
      } else {
        cancellation.cancel();
      }
      transport.uploadPending!.complete(
        _response({
          'image_url': 'https://i0.hdslb.com/a.png',
          'image_width': 100,
          'image_height': 50,
        }),
      );
      await expectation;
      expect(transport.sends, 0);
    }
    expect(transport.uploads, 2);
  });
}

ApiHttpResponse _response(Object? data) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
  const {},
);

final class _Transport
    implements ApiTransport, ApiFormTransport, ApiMultipartTransport {
  Object? data = const {};
  Completer<ApiHttpResponse>? uploadPending;
  int uploads = 0, sends = 0;
  Map<String, String> fields = {};
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => _response(data);
  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    sends++;
    this.fields = fields;
    return _response({});
  }

  @override
  Future<ApiHttpResponse> postMultipart(
    Uri uri, {
    required Map<String, String> fields,
    required Uint8List bytes,
    required String mimeType,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    uploads++;
    return uploadPending?.future ??
        _response({
          'image_url': 'https://i0.hdslb.com/a.png',
          'image_width': 100,
          'image_height': 50,
        });
  }
}
