import 'dart:convert';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Explicit, local read-only probe. Never run account writes or persist private fixtures.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows existing Web session can read account and message categories', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('消息只读验证'))),
    );
    final saved = await SystemCredentialStore().read();
    expect(
      saved,
      isNotNull,
      reason: 'Requires an existing account in the app secure store',
    );
    if (saved == null) return;
    final decoded = jsonDecode(saved);
    expect(decoded, isA<Map<String, Object?>>());
    final record = decoded as Map<String, Object?>;
    final transport = _SchemaTransport();
    final api = BiliApiClient(transport: transport);
    try {
      api.cookieJar.restoreFromSecureStorage(
        record['cookies'] as Map<String, Object?>,
      );
      await tester.runAsync(() async {
        final nav = await api.getNav();
        expect(nav.isLogin, true);
        final mid = nav.mid;
        expect(mid, isNotNull);
        if (mid == null) return;
        final overview = await AccountClient(api).overview(mid);
        debugPrint(
          'account_overview: level=${overview.level}, statisticsPresent=${overview.following != null && overview.followers != null && overview.dynamics != null}',
        );
        final client = MessageClient(api);
        final counts = await client.unread();
        debugPrint('message_unread: categories=${counts.length}');
        final sessions = await client.sessions();
        debugPrint(
          'message_sessions: count=${sessions.items.length}, hasMore=${sessions.hasMore}',
        );
        if (sessions.hasMore) {
          final next = await client.sessions(cursor: sessions.nextCursor);
          debugPrint('message_sessions_next: count=${next.items.length}');
        }
        final entry = sessions.items
            .where((e) => e.userMid != null && e.sessionType == 1)
            .firstOrNull;
        if (entry != null) {
          final messages = await client.thread(entry.userMid ?? '', 1);
          debugPrint(
            'message_thread: count=${messages.items.length}, hasMore=${messages.hasMore}',
          );
          if (messages.hasMore) {
            final next = await client.thread(
              entry.userMid ?? '',
              1,
              cursor: messages.nextCursor,
            );
            debugPrint('message_thread_next: count=${next.items.length}');
          }
        }
        for (final category in ApiInboxSection.values.where(
          (s) => s != ApiInboxSection.private,
        )) {
          final list = await client.notifications(category);
          debugPrint(
            'message_${category.name}: count=${list.items.length}, hasMore=${list.hasMore}',
          );
          if (list.hasMore) {
            final next = await client.notifications(
              category,
              cursor: list.nextCursor,
            );
            debugPrint(
              'message_${category.name}_next: count=${next.items.length}',
            );
          }
        }
      });
    } finally {
      api.close();
      transport.inner.close();
    }
  });
}

final class _SchemaTransport implements ApiTransport {
  final inner = DioApiTransport();
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final response = await inner.get(
      uri,
      headers: headers,
      timeout: timeout,
      cancellation: cancellation,
    );
    // Field names/types only. No account IDs, text, cookies, query or values.
    final Object? root = jsonDecode(utf8.decode(response.body));
    if (root is Map<String, Object?>) {
      debugPrint('schema ${uri.path}: ${_shape(root['data'], 2)}');
    }
    return response;
  }

  String _shape(Object? value, int depth) {
    if (value == null) return 'null';
    if (depth <= 0) {
      return value is List
          ? 'List'
          : value is Map
          ? 'Map'
          : value.runtimeType.toString();
    }
    if (value is List<Object?>) {
      return 'List(${value.length})[${value.isEmpty ? '' : _shape(value.first, depth - 1)}]';
    }
    if (value is Map<String, Object?>) {
      return '{${value.entries.map((e) => '${RegExp(r'^[0-9]+$').hasMatch(e.key) ? 'ID' : e.key}:${_shape(e.value, depth - 1)}').join(',')}}';
    }
    return value.runtimeType.toString();
  }
}
