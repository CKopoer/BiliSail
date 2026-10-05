import 'dart:convert';

import 'package:bili_api/bili_api.dart';
import 'package:bili_lite/core/storage/credential_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Explicit local read-only check; private content and credentials stay in memory.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows existing Web session reads all five favorite tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('收藏只读验证'))),
    );
    final saved = await SystemCredentialStore().read();
    expect(saved, isNotNull, reason: 'Requires an existing app Web session');
    if (saved == null) return;
    final decoded = jsonDecode(saved);
    expect(decoded, isA<Map<String, Object?>>());
    final record = decoded as Map<String, Object?>;
    final transport = DioApiTransport();
    final api = BiliApiClient(transport: transport);
    try {
      api.cookieJar.restoreFromSecureStorage(
        record['cookies'] as Map<String, Object?>,
      );
      await tester.runAsync(() async {
        final nav = await api.getNav();
        expect(nav.isLogin, isTrue);
        final mid = nav.mid;
        expect(mid, isNotNull);
        if (mid == null) return;
        final client = HomeClient(api);
        final failures = <String>[];
        for (final (section, label) in [
          ('默认收藏夹', 'default'),
          ('我创建的收藏夹', 'created'),
          ('我的收藏与订阅', 'collected'),
          ('我的追番', 'bangumi'),
          ('我的追剧', 'cinema'),
        ]) {
          try {
            final first = await client.load(
              channel: 'favorites',
              section: section,
              page: 1,
              mid: mid,
            );
            debugPrint(
              'favorites_$label: count=${first.items.length}, hasMore=${first.hasMore}',
            );
            if (first.hasMore) {
              final next = await client.load(
                channel: 'favorites',
                section: section,
                page: 2,
                mid: mid,
                cursor: first.nextCursor,
              );
              debugPrint(
                'favorites_${label}_next: count=${next.items.length}, hasMore=${next.hasMore}',
              );
            }
            for (final kind in [
              ApiHomeEntryKind.folder,
              ApiHomeEntryKind.collection,
            ]) {
              final folder = first.items
                  .where((e) => e.kind == kind)
                  .firstOrNull;
              if (folder == null) continue;
              final videos = await client.load(
                channel: 'favorites',
                section: section,
                page: 1,
                mid: mid,
                folderId: kind == ApiHomeEntryKind.collection
                    ? 'ugc:${folder.id}'
                    : folder.id,
              );
              debugPrint(
                'favorites_${label}_${kind.name}: count=${videos.items.length}, hasMore=${videos.hasMore}, playable=${videos.items.where((e) => e.bvid != null).length}',
              );
            }
          } on ApiFailure catch (error) {
            failures.add(label);
            debugPrint(
              'favorites_$label: failure=${error.category.name}, code=${error.businessCode}',
            );
          }
        }
        final profile = ProfileClient(api);
        final folders = await profile.loadFolders(mid, page: 1);
        final folder = folders.items.firstOrNull;
        if (folder != null) {
          final videos = await profile.loadFolderVideos(folder.id, page: 1);
          debugPrint(
            'profile_favorites: count=${videos.items.length}, playable=${videos.items.where((e) => e.video != null).length}',
          );
        }
        expect(
          failures,
          isEmpty,
          reason: 'All available tabs must parse through the Web client',
        );
      });
    } finally {
      api.close();
      transport.close();
    }
  });
}
