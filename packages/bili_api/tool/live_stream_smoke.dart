// Explicit guest-only read. Never print signed URLs, queries or credentials.
import 'dart:io';
import 'package:bili_api/bili_api.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2 ||
      arguments.first != '--online' ||
      !RegExp(r'^[1-9][0-9]*$').hasMatch(arguments.last)) {
    stderr.writeln(
      'Usage: dart run tool/live_stream_smoke.dart --online <room>',
    );
    exitCode = 64;
    return;
  }
  final api = BiliApiClient();
  try {
    final client = LiveClient(api);
    for (final quality in [0, 400, 10000]) {
      final info = await client.getPlayInfo(arguments.last, qn: quality);
      stdout.writeln(
        'requestQn=$quality live=${info.liveStatus} combinations=${info.streams.length}',
      );
      for (final stream in info.streams) {
        stdout.writeln(
          '${stream.protocol}/${stream.format}/${stream.codec} qn=${stream.quality} lines=${stream.urls.length}',
        );
      }
    }
  } on ApiFailure catch (failure) {
    stderr.writeln(
      'live_stream: ${failure.category.name} http=${failure.httpStatus} code=${failure.businessCode}',
    );
    exitCode = 1;
  } finally {
    api.close();
  }
}
