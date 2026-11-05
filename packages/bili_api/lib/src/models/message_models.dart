enum ApiInboxSection { private, replies, mentions, likes, system }

enum ApiMessageContentKind {
  text,
  image,
  share,
  notification,
  video,
  article,
  pictureCard,
  commonCard,
  autoReply,
  notice,
  voice,
  miniProgram,
  withdrawn,
  unsupported,
}

final class ApiMessageCard {
  const ApiMessageCard({
    this.title = '',
    this.description = '',
    this.imageUrl,
    this.targetUrl,
  });
  final String title, description;
  final Uri? imageUrl, targetUrl;
}

final class ApiMessageDetail {
  const ApiMessageDetail({required this.label, required this.value});
  final String label, value;
}

final class ApiMessageLink {
  const ApiMessageLink({required this.label, required this.url});
  final String label;
  final Uri url;
}

final class ApiMessageReplyContext {
  const ApiMessageReplyContext({
    required this.subjectId,
    required this.businessId,
    this.rootId,
    required this.parentId,
    required this.author,
    this.userMid,
  });
  final String subjectId, parentId, author;
  final int businessId;
  final String? rootId, userMid;
}

final class ApiMessageEmotePackage {
  const ApiMessageEmotePackage(this.name, this.items);
  final String name;
  final List<ApiMessageEmote> items;
}

final class ApiMessageEmote {
  const ApiMessageEmote(this.text, this.imageUrl);
  final String text;
  final Uri? imageUrl;
}

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
    this.readCursor,
    this.sourceText = '',
    this.sourceTitle = '',
    this.sourceImageUrl,
    this.pinned = false,
    this.muted = false,
    this.emotes = const {},
    this.replyContext,
  });
  final String id, title, text;
  final String? userMid, lastSequence, readCursor;
  final Uri? avatarUrl, targetUrl;
  final DateTime? time;
  final int? sessionType;
  final bool system;
  final int unread;
  final String sourceText, sourceTitle;
  final Uri? sourceImageUrl;
  final bool pinned, muted;
  final Map<String, Uri> emotes;
  final ApiMessageReplyContext? replyContext;
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
    this.kind = ApiMessageContentKind.text,
    this.title = '',
    this.subtitle = '',
    this.cards = const [],
    this.details = const [],
    this.links = const [],
    this.durationSeconds,
    this.imageAspectRatio,
    this.emotes = const {},
  });
  final String id, sequence, senderMid, text;
  final int type;
  final DateTime? time;
  final Uri? imageUrl, targetUrl;
  final ApiMessageContentKind kind;
  final String title, subtitle;
  final List<ApiMessageCard> cards;
  final List<ApiMessageDetail> details;
  final List<ApiMessageLink> links;
  final int? durationSeconds;
  final double? imageAspectRatio;
  final Map<String, Uri> emotes;
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
    this.bCoins,
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
  final num? coins, bCoins;
}
