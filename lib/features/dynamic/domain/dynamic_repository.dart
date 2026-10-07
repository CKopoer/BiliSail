import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';

final class DynamicWriteUncertain implements Exception {
  const DynamicWriteUncertain();
}

abstract interface class DynamicRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<DynamicPost> detail(String id, RequestCancellation cancellation);
  Future<void> like(String id, bool liked, RequestCancellation cancellation);
  Future<String> repost(
    String id,
    String text,
    RequestCancellation cancellation,
  );
}
