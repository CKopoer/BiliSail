import '../../../domain/request_cancellation.dart';

final class CollectionId {
  const CollectionId(this.value);
  final String value;

  @override
  bool operator ==(Object other) =>
      other is CollectionId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

abstract interface class CollectionSubscriptionRepository {
  String get accountScope;
  int get sessionEpoch;

  Future<bool> isSubscribed(CollectionId id, RequestCancellation cancellation);
  Future<void> setSubscribed(
    CollectionId id,
    bool subscribed,
    RequestCancellation cancellation,
  );
}
