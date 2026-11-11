/// Immutable Web vote response; option indices are server identities, not offsets.
final class ApiDynamicPollOptionResult {
  const ApiDynamicPollOptionResult({
    required this.index,
    required this.text,
    required this.count,
    this.imageUrl,
  });
  final int index, count;
  final String text;
  final Uri? imageUrl;
}

final class ApiDynamicPoll {
  ApiDynamicPoll({
    required this.id,
    required this.title,
    required this.description,
    required this.maxChoices,
    required this.endsAt,
    required this.joinCount,
    required List<ApiDynamicPollOptionResult> options,
    required Set<int> myVotes,
    this.authorId,
  }) : options = List.unmodifiable(options),
       myVotes = Set.unmodifiable(myVotes);
  final String id, title, description;
  final int maxChoices, joinCount;
  final DateTime endsAt;
  final List<ApiDynamicPollOptionResult> options;
  final Set<int> myVotes;
  final String? authorId;
}

final class ApiDynamicPollFollowee {
  const ApiDynamicPollFollowee(this.id, this.name, this.votes, this.avatar);
  final String id, name;
  final List<int> votes;
  final Uri? avatar;
}
