enum ApiMessageSetting {
  notification('msg_notify', {1, 3}),
  receiveUnfollowed('receive_unfollow_msg', {0, 1}),
  foldUnfollowed('show_unfollowed_msg', {0, 1}),
  reply('set_comment', {0, 1, 2}),
  mention('set_at', {0, 1, 2}),
  like('set_like', {0, 5}),
  smartIntercept('ai_intercept', {0, 1});

  const ApiMessageSetting(this.field, this.allowedValues);
  final String field;
  final Set<int> allowedValues;
}

final class ApiMessageCenterSettings {
  const ApiMessageCenterSettings(this.values);
  final Map<ApiMessageSetting, int> values;
}

final class ApiChatMessageSettings {
  const ApiChatMessageSettings({
    required this.contentPush,
    required this.showContentPush,
    required this.blocked,
  });
  final bool contentPush, showContentPush, blocked;
}

enum ApiMessagePeopleKind { fans, contacts, blocked }

final class ApiMessagePerson {
  const ApiMessagePerson({
    required this.mid,
    required this.name,
    this.sign = '',
    this.avatarUrl,
  });
  final String mid, name, sign;
  final Uri? avatarUrl;
}

final class ApiMessageBlockedWords {
  const ApiMessageBlockedWords(
    this.words, {
    required this.limit,
    required this.wordLength,
  });
  final List<String> words;
  final int limit, wordLength;
}
