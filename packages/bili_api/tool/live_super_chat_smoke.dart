import 'package:bili_api/bili_api.dart';

/// Explicit guest-only probe; no message text, identities or credentials logged.
Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  try {
    final messages = await LiveClient(
      api,
    ).getSuperChats(args.isEmpty ? '7734200' : args.first);
    print('live_super_chat: success messages=${messages.length}');
  } on ApiFailure catch (error) {
    print(
      'live_super_chat: ${error.category.name} '
      'http=${error.httpStatus} code=${error.businessCode}',
    );
  } finally {
    api.close();
  }
}
