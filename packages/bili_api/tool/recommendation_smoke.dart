import 'package:bili_api/bili_api.dart';

/// Guest-only read: no account store, credentials or signed URLs in output.
Future<void> main() async {
  final api = BiliApiClient();
  try {
    final page = await api.getRecommended();
    print('videos=${page.items.length}');
    print(
      'reasons=${page.items.map((video) => video.recommendationReason).whereType<String>().toList()}',
    );
  } on ApiFailure catch (e) {
    print(
      '${e.category.name}, HTTP ${e.httpStatus}, business ${e.businessCode}',
    );
  } finally {
    api.close();
  }
}
