final class DynamicPollOption {
  const DynamicPollOption({
    required this.index,
    required this.text,
    required this.count,
    this.imageUrl,
  });
  final int index, count;
  final String text;
  final Uri? imageUrl;
}

final class DynamicPoll {
  DynamicPoll({
    required this.id,
    required this.title,
    required this.description,
    required this.maxChoices,
    required this.endsAt,
    required this.joinCount,
    required List<DynamicPollOption> options,
    required Set<int> myVotes,
  }) : options = List.unmodifiable(options),
       myVotes = Set.unmodifiable(myVotes);
  final String id, title, description;
  final int maxChoices, joinCount;
  final DateTime endsAt;
  final List<DynamicPollOption> options;
  final Set<int> myVotes;
  bool get hasVoted => myVotes.isNotEmpty;
  bool endedAt(DateTime now) => !endsAt.isAfter(now);
  int get totalVotes => options.fold(0, (sum, option) => sum + option.count);
}

/// Only recognized official vote pages open the native poll dialog.
String? dynamicPollIdFromUri(Uri uri) {
  if (!{'https', 'http'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      uri.host != 't.bilibili.com' ||
      !{'/vote/h5/index', '/vote/h5/index/'}.contains(uri.path)) {
    return null;
  }
  final ids = uri.queryParametersAll['vote_id'];
  if (ids == null || ids.length != 1) return null;
  final id = ids.single;
  return id.length <= 128 && RegExp(r'^[1-9][0-9]*$').hasMatch(id) ? id : null;
}
