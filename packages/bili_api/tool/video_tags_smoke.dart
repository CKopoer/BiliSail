import 'package:bili_api/bili_api.dart';

/// Developer-invoked public read; no account credentials or content are printed.
Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  try {
    final tags = await api.getVideoTags(
      args.isEmpty ? 'BV1cGbK6hEQK' : args.first,
    );
    print(
      'video tags: count=${tags.length}, nonEmpty=${tags.every((e) => e.isNotEmpty)}',
    );
  } finally {
    api.close();
  }
}
