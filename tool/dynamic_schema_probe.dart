import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:bili_lite/app/dependencies.dart';

// Explicit Windows developer probe; never used by normal startup or CI.
// Reuses the application's secure-session boundary and prints schema only.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppDependencies.create();
  try {
    await dependencies.session.restore();
    for (final opusStyle in [false, true]) {
      final data = await dependencies.requests.run(
        (context) => dependencies.api.requestJson(
          Uri.https('api.bilibili.com', '/x/polymer/web-dynamic/v1/feed/all', {
            'type': 'all',
            'page': '1',
            if (opusStyle) 'features': 'itemOpusStyle',
          }),
          'dynamic_schema_probe',
          context: context,
        ),
      );
      final items = data['items'];
      if (items is! List<Object?>) continue;
      for (final item in items.take(3)) {
        if (item is! Map<String, Object?>) continue;
        final modules = item['modules'];
        if (modules is! Map<String, Object?>) continue;
        stdout.writeln(
          jsonEncode({
            'opusStyle': opusStyle,
            'contentSchema': _shape(modules['module_dynamic'], 0),
          }),
        );
      }
    }
  } catch (error) {
    stdout.writeln('Schema probe failed: ${error.runtimeType}');
    exitCode = 1;
  } finally {
    await dependencies.close();
  }
  exit(exitCode);
}

Object? _shape(Object? value, int depth) {
  if (value == null) return null;
  if (value is String) return 'String(${value.length})';
  if (value is num) return 'number';
  if (value is bool) return 'boolean';
  if (depth >= 8) return 'nested';
  if (value is List<Object?>) {
    return {
      'length': value.length,
      if (value.isNotEmpty) 'first': _shape(value.first, depth + 1),
    };
  }
  if (value is Map<String, Object?>) {
    return {
      for (final key in value.keys.take(40)) key: _shape(value[key], depth + 1),
    };
  }
  return 'unknown';
}
