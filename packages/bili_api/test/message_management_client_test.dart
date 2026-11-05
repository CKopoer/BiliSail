import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'message_client_test.dart' show Transport, response, cookies;

void main() {
  late Transport transport;
  late MessageManagementClient client;
  setUp(() {
    transport = Transport();
    client = MessageManagementClient(
      BiliApiClient(transport: transport, cookieJar: cookies()),
    );
  });

  test(
    'pin and unpin use official op_type and destination scoped CSRF',
    () async {
      await client.setPinned('9007199254740993123', true);
      expect(transport.uri?.host, 'api.vc.bilibili.com');
      expect(transport.uri?.path, '/session_svr/v1/session_svr/set_top');
      expect(transport.fields['talker_id'], '9007199254740993123');
      expect(transport.fields['session_type'], '1');
      expect(transport.fields['op_type'], '0');
      expect(transport.fields['csrf'], 'csrf-fixture');
      expect(transport.fields['csrf_token'], 'csrf-fixture');
      expect(transport.headers['Origin'], 'https://message.bilibili.com');
      await client.setPinned('123', false);
      expect(transport.fields['op_type'], '1');
      expect(transport.posts, 2);
    },
  );

  test('mute is DND, separate from content-push preferences', () async {
    await client.setMuted('123', '456', true);
    expect(transport.uri?.path, '/link_setting/v1/link_setting/set_msg_dnd');
    expect(transport.fields['uid'], '123');
    expect(transport.fields['dnd_uid'], '456');
    expect(transport.fields['setting'], '1');
    await client.setMuted('123', '456', false);
    expect(transport.fields['setting'], '0');
  });

  test('remove uses exact private-session identity', () async {
    await client.removeConversation('456');
    expect(transport.uri?.path, '/session_svr/v1/session_svr/remove_session');
    expect(transport.fields['talker_id'], '456');
    expect(transport.fields['session_type'], '1');
  });

  test('failed management posts are never replayed', () async {
    transport.postResult = response(null, status: 503);
    await expectLater(
      client.setPinned('456', true),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      client.setMuted('123', '456', true),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      client.removeConversation('456'),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.posts, 3);
  });

  test('wrong-host credentials and cancelled operations never send', () async {
    final scoped = MessageManagementClient(
      BiliApiClient(
        transport: transport,
        cookieJar: cookies(domain: 'api.bilibili.com'),
      ),
    );
    await expectLater(
      scoped.removeConversation('456'),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      client.setPinned(
        '456',
        true,
        context: ApiRequestContext(cancellation: ApiCancellation()..cancel()),
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.posts, 0);
  });

  test('invalid IDs are rejected before any mutation', () async {
    await expectLater(client.setPinned('1.2e18', true), throwsArgumentError);
    await expectLater(client.setMuted('0', '456', true), throwsArgumentError);
    await expectLater(client.removeConversation('-1'), throwsArgumentError);
    expect(transport.posts, 0);
  });
}
