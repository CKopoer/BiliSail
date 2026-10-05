import '../../../domain/request_cancellation.dart';
import 'search_result.dart';

abstract interface class SearchRepository {
  Future<SearchPage> search({
    required String query,
    required int page,
    required SearchCategory category,
    required SearchOrder order,
    required SearchDuration duration,
    required SearchUserType userType,
    required RequestCancellation cancellation,
  });
}
