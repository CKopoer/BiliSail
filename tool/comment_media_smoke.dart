import 'dart:convert';
import 'dart:io';

import 'package:bili_api/bili_api.dart';

Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  try {
    final emotes = await api.getCommentEmotes();
    stdout.writeln(
      jsonEncode({
        'emotePackages': emotes.length,
        'emotes': emotes.fold<int>(0, (n, p) => n + p.items.length),
      }),
    );
    if (args.isNotEmpty) {
      final page = await api.getVideoComments(args.first);
      final all = [...page.items, for (final c in page.items) ...c.replies];
      stdout.writeln(
        jsonEncode({
          'comments': all.length,
          'withLevel': all.where((c) => c.level != null).length,
          'withMedal': all.where((c) => c.medalName != null).length,
          'withEmotes': all.where((c) => c.emotes.isNotEmpty).length,
          'withPictures': all.where((c) => c.pictures.isNotEmpty).length,
        }),
      );
    }
  } on ApiFailure catch (e) {
    stdout.writeln(
      jsonEncode({
        'endpoint': e.endpointId,
        'category': e.category.name,
        'businessCode': e.businessCode,
      }),
    );
    exitCode = 1;
  } finally {
    api.close();
  }
}
