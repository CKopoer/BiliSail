import '../../../domain/user.dart';
import 'dynamic_link.dart';

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
  bool openAt(DateTime now) => !endedAt(now) && !hasVoted;
  double fraction(int index) => totalVotes == 0
      ? 0
      : (options.firstWhere((o) => o.index == index).count / totalVotes).clamp(
          0,
          1,
        );
}

final class DynamicPollFollowee {
  const DynamicPollFollowee(this.id, this.name, this.votes, this.avatar);
  final UserId id;
  final String name;
  final List<int> votes;
  final Uri? avatar;
}

/// Only recognized official vote pages open the native poll dialog.
String? dynamicPollIdFromUri(Uri uri) {
  return dynamicPollId(uri);
}
