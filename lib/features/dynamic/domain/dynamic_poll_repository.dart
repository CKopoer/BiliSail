import '../../../domain/request_cancellation.dart';
import 'dynamic_poll.dart';

abstract interface class DynamicPollRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<DynamicPoll> poll(String id, RequestCancellation cancellation);
  Future<DynamicPoll> vote(
    String id,
    String voterId,
    List<int> choices,
    bool anonymous,
    RequestCancellation cancellation, {
    String? dynamicId,
  });
}

abstract interface class DynamicPollSocialRepository {
  Future<List<DynamicPollFollowee>> followees(String id, RequestCancellation c);
}
