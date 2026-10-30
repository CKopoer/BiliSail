import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: dart run tool/validation/narrow_primary_switch_driver.dart '
      '<ws://VM-service/ws> <sample|snapshot|density|go|quit> [key=value]',
    );
    exitCode = 64;
    return;
  }
  final socket = Uri.parse(args[0]);
  final base = socket.replace(
    scheme: socket.scheme == 'wss' ? 'https' : 'http',
    path: socket.path.replaceFirst(RegExp(r'/ws/?$'), '/'),
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  Future<Map<String, Object?>> rpc(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    final request = await client.getUrl(
      base.resolve(method).replace(queryParameters: params),
    );
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (response.statusCode != HttpStatus.ok ||
        decoded is! Map<String, Object?> ||
        decoded['error'] != null ||
        decoded['result'] is! Map<String, Object?>) {
      throw StateError('VM service $method failed: $body');
    }
    return decoded['result']! as Map<String, Object?>;
  }

  try {
    final vm = await rpc('getVM');
    final isolates = vm['isolates'] as List<Object?>;
    final isolate =
        isolates.whereType<Map<String, Object?>>().firstWhere(
              (e) => e['name'] == 'main',
            )['id']!
            as String;
    Future<Object?> probe(
      String action, [
      Map<String, String> params = const {},
    ]) async {
      final r = await rpc('ext.bilisail.switchProbe', {
        'isolateId': isolate,
        'action': action,
        ...params,
      });
      return r['result'];
    }

    Object? result;
    if (args[1] == 'sample') {
      await probe('go', {'path': '/?channel=videoDynamic'});
      await Future<void>.delayed(const Duration(seconds: 1));
      await probe('go', {'path': '/me?section=watchLater'});
      await Future<void>.delayed(const Duration(seconds: 1));
      await probe('go', {'path': '/settings'});
      await Future<void>.delayed(const Duration(seconds: 1));
      await probe('go', {'path': '/'});
      await Future<void>.delayed(const Duration(seconds: 1));
      await probe('reset');
      final samples = <Object?>[];
      for (var round = 0; round < 8; round++) {
        for (final index in ['1', '2', '3', '0']) {
          samples.add(await probe('switch', {'index': index}));
        }
      }
      result = {'samples': samples, 'end': await probe('snapshot')};
    } else if (args[1] == 'rapid') {
      await probe('reset');
      final calls = <Future<Object?>>[];
      for (var round = 0; round < 8; round++) {
        for (final index in ['1', '2', '0']) {
          calls.add(probe('switch', {'index': index}));
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
      }
      await Future.wait(calls);
      result = {
        'capture': await probe('frames'),
        'end': await probe('snapshot'),
      };
    } else {
      result = await probe(args[1], {
        for (var i = 2; i < args.length; i++)
          args[i].split('=').first: args[i].substring(args[i].indexOf('=') + 1),
      });
    }
    final json = const JsonEncoder.withIndent('  ').convert(result);
    final output = Platform.environment['SWITCH_OUTPUT'];
    // Control commands must not overwrite a previously captured sample.
    if (output != null && (args[1] == 'sample' || args[1] == 'rapid')) {
      final file = File(output);
      await file.parent.create(recursive: true);
      await file.writeAsString(json);
      stdout.writeln('Saved $output');
    } else {
      stdout.writeln(json);
    }
  } finally {
    client.close(force: true);
  }
}
