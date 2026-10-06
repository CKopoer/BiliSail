import 'dart:io';

import 'package:bili_api/bili_api.dart';

/// Manual guest-only GET smoke. Does not load credentials or submit history.
Future<void> main() async {
  final api = BiliApiClient();
  final context = ApiRequestContext(
    deadline: DateTime.now().add(const Duration(seconds: 20)),
  );
  try {
    final video = await api.getVideoDetail('BV17x411w7KC', context: context);
    final position = await PlaybackHistoryClient(
      api,
    ).read(video.bvid, video.pages.first.cid, context: context);
    print('guest_progress: code=0 hasProgress=${position != null}');
  } on ApiFailure catch (failure) {
    print(
      'guest_progress: category=${failure.category.name} businessCode=${failure.businessCode}',
    );
    exitCode = 1;
  } finally {
    api.close();
  }
}
