import 'package:bili_api/bili_api.dart';

/// Explicit, low-frequency guest-only read smoke. No credentials are loaded.
Future<void> main(List<String> args) async {
  final mid = args.isEmpty ? '2' : args.first;
  final api = BiliApiClient();
  final profile = ProfileClient(api);
  final operations = <String, Future<Object> Function()>{
    'profile': () async => (await profile.loadProfile(mid)).mid,
    'videos': () async => (await profile.loadVideos(mid, page: 1)).items.length,
    'dynamics': () async => (await profile.loadDynamics(mid)).items.length,
    'folders': () async =>
        (await profile.loadFolders(mid, page: 1)).items.length,
    'followings': () async => (await profile.loadRelations(
      mid,
      followers: false,
      page: 1,
    )).items.length,
    'followers': () async => (await profile.loadRelations(
      mid,
      followers: true,
      page: 1,
    )).items.length,
  };
  try {
    for (final operation in operations.entries) {
      try {
        print('${operation.key}: ${await operation.value()}');
      } on ApiFailure catch (e) {
        print(
          '${operation.key}: ${e.category.name}, HTTP ${e.httpStatus}, business ${e.businessCode}',
        );
      }
    }
  } finally {
    api.close();
  }
}
