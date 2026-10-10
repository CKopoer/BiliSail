import 'dart:io';

import 'package:bili_api/bili_api.dart';

/// Explicit guest-only detail read. Never sends follow writes or account cookies.
Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  try {
    final video = await api.getVideoDetail(args.firstOrNull ?? 'BV1C4Hx6KEvf');
    print(
      'staff: count=${video.staff.length}, '
      'validIds=${video.staff.where((m) => m.mid != null).length}, '
      'avatars=${video.staff.where((m) => m.avatarUrl != null).length}, '
      'highlightedRoles=${video.staff.where((m) => m.highlightedRole).length}',
    );
    print('roles: ${video.staff.map((m) => m.title).join(', ')}');
    if (video.staff.isEmpty) exitCode = 1;
  } on ApiFailure catch (error) {
    print(
      'failure: ${error.category.name}, '
      'http=${error.httpStatus}, code=${error.businessCode}',
    );
    exitCode = 1;
  } finally {
    api.close();
  }
}
