import 'dart:typed_data';
import 'dart:io';

import 'package:bilisail/app/router.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/account_overview_controller.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/library/application/library_controller.dart';
import 'package:bilisail/features/library/domain/library_repository.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'input_test_app.dart';

/// Real router/shell/pages, deterministic data and decoded covers; no account IO.
class PrimarySwitchFixture {
  PrimarySwitchFixture(
    Uint8List png, {
    SwitchFeedRepository? feed,
    SwitchHomeRepository? home,
  }) : feed = feed ?? SwitchFeedRepository(),
       home = home ?? SwitchHomeRepository(),
       cache = AppImageCache(
         ImageByteCache(
           directory: () async =>
               throw const FileSystemException('memory only'),
           loader: (_, _) async => png,
         ),
       );

  final AppImageCache cache;
  final SwitchFeedRepository feed;
  final SwitchHomeRepository home;
  late final GoRouter router = createBiliRouter(
    playerBuilder: (_, _, _) => const SizedBox(),
    accountBuilder: (_) => const SizedBox(width: 24, height: 24),
  );

  Widget get app => ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(_Settings()),
      authControllerProvider.overrideWith(_Auth.new),
      sessionEpochProvider.overrideWithValue(() => 0),
      accountOverviewProvider.overrideWith((_) async => null),
      feedRepositoryProvider.overrideWithValue(feed),
      homeRepositoryProvider.overrideWithValue(home),
      libraryRepositoryProvider.overrideWithValue(_Library()),
    ],
    child: AppImageCacheScope(
      cache: cache,
      child: InputTestApp.router(
        theme: ThemeData(platform: TargetPlatform.android),
        routerConfig: router,
        builder: (context, child) => ScrollConfiguration(
          behavior: const SmoothScrollBehavior(),
          child: child!,
        ),
      ),
    ),
  );

  Future<void> dispose() async {
    router.dispose();
    await cache.close();
  }
}

class _Library implements LibraryRepository {
  @override
  String get accountScope => 'user:7';
  @override
  Future<WatchHistoryPage> loadHistory({
    String keyword = '',
    String? cursor,
    required RequestCancellation cancellation,
  }) async => const WatchHistoryPage([], hasMore: false);
}

class _Settings implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings.defaults(
    navigationMode: WorkspaceNavigationMode.singlePage,
  );
  @override
  Future<void> save(AppSettings settings) async {}
}

class _Auth extends AuthController {
  @override
  AuthState build() =>
      const AuthState(status: AuthStatus.signedIn, mid: '7', userName: '性能测试');
}

class SwitchFeedRepository implements FeedRepository {
  SwitchFeedRepository({this.covers = true});
  final bool covers;
  int reads = 0;
  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async {
    reads++;
    return PageResult(
      items: List.generate(
        300,
        (i) => VideoSummary(
          id: VideoId('BV1abc${i.toString().padLeft(6, '0')}'),
          title: '推荐视频 $i：窄屏页面切换与列表保留测试',
          author: '测试作者',
          coverUrl: covers ? 'https://i0.hdslb.com/switch-cover-$i.png' : '',
          duration: const Duration(minutes: 3),
        ),
      ),
      hasMore: false,
    );
  }

  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) => loadFeed(page: page, categoryId: null, cancellation: cancellation);
}

class SwitchHomeRepository implements HomeRepository {
  SwitchHomeRepository({this.covers = true});
  final bool covers;
  final reads = <String, int>{};
  @override
  String get accountScope => 'user:7';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    reads.update(query.channel.name, (v) => v + 1, ifAbsent: () => 1);
    return HomePage([
      for (var i = 0; i < 300; i++)
        HomeEntry(
          id: '$i',
          title: '${query.channel.label}视频 $i：有封面的真实列表布局',
          kind: HomeEntryKind.video,
          bvid: 'BV1abc${i.toString().padLeft(6, '0')}',
          coverUrl: covers
              ? Uri.parse('https://i0.hdslb.com/switch-cover-$i.png')
              : null,
          authorName: '测试作者',
          duration: const Duration(minutes: 3),
        ),
    ], hasMore: false);
  }
}
