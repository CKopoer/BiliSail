enum ApiInboxSection { private, replies, mentions, likes, system }

final class ApiInboxEntry {
  const ApiInboxEntry({
    required this.id,
    required this.title,
    required this.text,
    this.userMid,
    this.avatarUrl,
    this.time,
    this.targetUrl,
    this.sessionType,
    this.system = false,
    this.unread = 0,
    this.lastSequence,
  });
  final String id, title, text;
  final String? userMid, lastSequence;
  final Uri? avatarUrl, targetUrl;
  final DateTime? time;
  final int? sessionType;
  final bool system;
  final int unread;
}

final class ApiPrivateMessage {
  const ApiPrivateMessage({
    required this.id,
    required this.sequence,
    required this.senderMid,
    required this.text,
    required this.type,
    this.time,
    this.imageUrl,
    this.targetUrl,
  });
  final String id, sequence, senderMid, text;
  final int type;
  final DateTime? time;
  final Uri? imageUrl, targetUrl;
}

final class ApiAccountOverview {
  const ApiAccountOverview({
    required this.mid,
    this.level,
    this.currentExperience,
    this.nextExperience,
    this.levelExperience,
    this.following,
    this.followers,
    this.dynamics,
    this.vipLabel,
    this.coins,
  });
  final String mid;
  final int? level,
      currentExperience,
      nextExperience,
      levelExperience,
      following,
      followers,
      dynamics;
  final String? vipLabel;
  final num? coins;
}
