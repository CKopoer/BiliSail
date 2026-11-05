import '../api_client.dart';
import '../models.dart';

final class MessageManagementClient {
  const MessageManagementClient(this.api);
  final BiliApiClient api;

  Future<void> setPinned(
    String talkerMid,
    bool pinned, {
    ApiRequestContext? context,
  }) async {
    _mid(talkerMid);
    await api.submitMessageForm(
      '/session_svr/v1/session_svr/set_top',
      'message_set_pinned',
      {
        'talker_id': talkerMid,
        'session_type': '1',
        'op_type': pinned ? '0' : '1',
        'build': '0',
        'mobi_app': 'web',
      },
      context: context,
    );
  }

  Future<void> setMuted(
    String ownMid,
    String talkerMid,
    bool muted, {
    ApiRequestContext? context,
  }) async {
    _mid(ownMid);
    _mid(talkerMid);
    await api.submitMessageForm(
      '/link_setting/v1/link_setting/set_msg_dnd',
      'message_set_muted',
      {
        'uid': ownMid,
        'dnd_uid': talkerMid,
        'setting': muted ? '1' : '0',
        'build': '0',
        'mobi_app': 'web',
      },
      context: context,
    );
  }

  Future<void> removeConversation(
    String talkerMid, {
    ApiRequestContext? context,
  }) async {
    _mid(talkerMid);
    await api.submitMessageForm(
      '/session_svr/v1/session_svr/remove_session',
      'message_remove_conversation',
      {
        'talker_id': talkerMid,
        'session_type': '1',
        'build': '0',
        'mobi_app': 'web',
      },
      context: context,
    );
  }

  void _mid(String value) {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
      throw ArgumentError('Invalid message user ID');
    }
  }
}
