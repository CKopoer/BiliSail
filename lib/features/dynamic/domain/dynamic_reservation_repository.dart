import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';

abstract interface class DynamicReservationRepository {
  Future<DynamicReservation> reserve(
    String dynamicId,
    DynamicReservation reservation,
    RequestCancellation cancellation,
  );
}
