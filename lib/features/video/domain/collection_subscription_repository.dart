import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

final class CollectionId {
  const CollectionId(this.value);
  final String value;

  @override
  bool operator ==(Object other) =>
      other is CollectionId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A collection state read belongs to this video inside the collection.
final class CollectionSubscriptionTarget {
  const CollectionSubscriptionTarget({
    required this.collectionId,
    required this.videoId,
    this.aid,
  });

  final CollectionId collectionId;
  final VideoId videoId;
  final String? aid;

  @override
  bool operator ==(Object other) =>
      other is CollectionSubscriptionTarget &&
      other.collectionId == collectionId &&
      other.videoId == videoId &&
      other.aid == aid;

  @override
  int get hashCode => Object.hash(collectionId, videoId, aid);
}

abstract interface class CollectionSubscriptionRepository {
  String get accountScope;
  int get sessionEpoch;

  Future<bool> isSubscribed(
    CollectionSubscriptionTarget target,
    RequestCancellation cancellation,
  );
  Future<void> setSubscribed(
    CollectionSubscriptionTarget target,
    bool subscribed,
    RequestCancellation cancellation,
  );
}
