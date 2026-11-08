import 'dart:async';

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/image_viewer/application/image_viewer_controller.dart';
import 'package:bilisail/features/image_viewer/domain/original_image.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_header.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/shared/ui/image_viewer.dart';
import 'package:bilisail/shared/ui/season_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';

const _id = UserId('1');
const _video = VideoSummary(
  id: VideoId('BV1234567890'),
  title: '合集中的投稿',
  coverUrl: '',
  author: '测试 UP',
  duration: Duration(seconds: 60),
);
const _collection = ProfileEntry(
  id: 'season:12',
  kind: ProfileEntryKind.collection,
  title: '自然观察合集',
  count: 3,
  collection: ProfileCollectionId('12', isSeries: false),
);

void main() {
  late _Library repository;
  late AuthFake auth;
  late ProviderContainer container;
  late _Images images;
  final external = <Uri>[];
  setUp(() {
    repository = _Library();
    auth = AuthFake();
    images = _Images();
    external.clear();
    container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(auth),
        originalImageRepositoryProvider.overrideWithValue(images),
        externalLinkOpenerProvider.overrideWithValue((uri) async {
          external.add(uri);
          return true;
        }),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });
  ProfileController controller() =>
      container.read(profileControllerProvider(_id).notifier);
  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    ProfileSection section = ProfileSection.collections,
    ValueChanged<String>? onSeason,
    ValueChanged<VideoSummary>? onVideo,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: BiliTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: AppNoticeHost(child: child ?? const SizedBox()),
          ),
          home: Scaffold(
            body: ProfileScreen(
              id: _id,
              isSelf: true,
              initialSection: section,
              onOpenSeason: onSeason,
              onOpenVideo: onVideo,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 600.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'collection opens archives and returns without losing favorites at $width/$scale',
        (tester) async {
          VideoSummary? opened;
          await mount(
            tester,
            width: width,
            scale: scale,
            onVideo: (v) => opened = v,
          );
          final collection = find.byKey(
            const ValueKey('profile-library-collection-season:12'),
          );
          await tester.ensureVisible(collection);
          await tester.tap(collection);
          await tester.pumpAndSettle();
          expect(repository.reads.last.$2, _collection.collection);
          expect(find.text('合集中的投稿'), findsOneWidget);
          await tester.tap(find.text('合集中的投稿'));
          expect(opened?.id, _video.id);
          controller().select(ProfileSection.folders);
          await tester.pumpAndSettle();
          await tester.tap(find.text('公开收藏夹'));
          await tester.pumpAndSettle();
          expect(container.read(profileControllerProvider(_id)).folderId, '55');
          controller().select(ProfileSection.collections);
          await tester.pumpAndSettle();
          expect(find.text('合集中的投稿'), findsOneWidget);
          await tester.tap(find.byTooltip('返回合集'));
          await tester.pumpAndSettle();
          expect(find.text('自然观察合集'), findsOneWidget);
          expect(container.read(profileControllerProvider(_id)).folderId, '55');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final section in [ProfileSection.bangumi, ProfileSection.cinema]) {
    testWidgets(
      '${section.name} uses internal season navigation and retains its loaded list',
      (tester) async {
        String? season;
        await mount(tester, section: section, onSeason: (id) => season = id);
        expect(find.byType(SeasonCard), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SeasonCard),
            matching: find.text(
              section == ProfileSection.bangumi ? '追番' : '追剧',
            ),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .getSize(
                find.descendant(
                  of: find.byType(SeasonCard),
                  matching: find.byType(AspectRatio),
                ),
              )
              .aspectRatio,
          closeTo(3 / 4, .01),
        );
        await tester.tap(find.text('番剧与影视'));
        expect(season, '9007199254740993123');
        final before = repository.reads.where((r) => r.$1 == section).length;
        controller().select(ProfileSection.dynamics);
        await tester.pumpAndSettle();
        controller().select(section);
        await tester.pumpAndSettle();
        expect(repository.reads.where((r) => r.$1 == section).length, before);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'details arriving later retain header geometry and exact counts',
    (tester) async {
      final details = repository.details = Completer<ProfileSpaceDetails>();
      await mount(tester);
      final rect = tester.getRect(find.byType(ProfileSectionNavigation));
      details.complete(
        const ProfileSpaceDetails(gender: '保密', birthday: '02-03'),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(ProfileSectionNavigation)), rect);
      await tester.tap(find.byKey(const ValueKey('profile-details')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('123456789'), findsOneWidget);
      expect(find.text('02-03'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('自然观察合集'), findsOneWidget);
    },
  );
  testWidgets(
    'more menu copies canonical UID/link and opens only the public homepage',
    (tester) async {
      final copies = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copies.add(
              (call.arguments as Map<Object?, Object?>)['text'] as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester);
      for (final text in ['复制 UID', '复制主页链接', '在浏览器打开']) {
        await tester.tap(find.byKey(const ValueKey('profile-more')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(text));
        await tester.pumpAndSettle();
      }
      expect(copies, ['1', 'https://space.bilibili.com/1']);
      expect(external, [Uri.parse('https://space.bilibili.com/1')]);
    },
  );
  testWidgets(
    'wide layout uses allocated pane width and changes without rereading lists',
    (tester) async {
      await mount(tester, width: 1440);
      expect(find.byKey(const ValueKey('profile-header-wide')), findsOneWidget);
      final before = repository.reads.length;
      tester.view.physicalSize = const Size(500, 1000);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-header-narrow')),
        findsOneWidget,
      );
      expect(repository.reads.length, before);
      expect(tester.takeException(), isNull);
    },
  );
  for (final target in ['avatar', 'banner']) {
    testWidgets(
      'profile $target opens the shared viewer with the original source',
      (tester) async {
        repository.images = true;
        await mount(tester);
        await tester.tap(find.byKey(ValueKey('profile-$target')));
        await tester.pumpAndSettle();
        expect(find.byType(ImageViewer), findsOneWidget);
        expect(images.sources, [
          Uri.parse('https://i0.hdslb.com/$target.png@1280w_1280h_0e.webp'),
        ]);
        await tester.tap(find.byTooltip('关闭图片'));
        await tester.pumpAndSettle();
        expect(find.byType(ImageViewer), findsNothing);
        expect(find.text('自然观察合集'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _Library implements ProfileRepository, ProfileDetailsRepository {
  bool images = false;
  Completer<ProfileSpaceDetails>? details;
  final reads = <(ProfileSection, ProfileCollectionId?, String?)>[];
  @override
  String get accountScope => 'user:1';
  @override
  int get sessionEpoch => 0;
  @override
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => UserProfile(
    id: id,
    name: '测试 UP 的主页',
    avatarUrl: images ? Uri.parse('https://i0.hdslb.com/avatar.png') : null,
    signature: '记录自然与日常生活',
    followerCount: 123456789,
    followingCount: 12,
    likeCount: 456789,
    videoCount: 60,
  );
  @override
  Future<ProfileSpaceDetails> loadDetails(
    UserId id, {
    required RequestCancellation cancellation,
  }) async =>
      details?.future ??
      ProfileSpaceDetails(
        gender: '保密',
        bannerUrl: images ? Uri.parse('https://i0.hdslb.com/banner.png') : null,
      );
  @override
  Future<ProfileLiveRoom?> loadLiveRoom(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => null;
  @override
  Future<ProfilePage> loadEntries(
    UserId id,
    ProfileSection section, {
    required int page,
    String? cursor,
    String order = 'pubdate',
    String keyword = '',
    String? folderId,
    ProfileCollectionId? collection,
    required RequestCancellation cancellation,
  }) async {
    reads.add((section, collection, folderId));
    final items = switch (section) {
      ProfileSection.collections when collection == null => const [_collection],
      ProfileSection.collections || ProfileSection.videos => const [
        ProfileEntry(
          id: 'BV1234567890',
          kind: ProfileEntryKind.video,
          title: '合集中的投稿',
          video: _video,
        ),
      ],
      ProfileSection.folders when folderId == null => const [
        ProfileEntry(id: '55', kind: ProfileEntryKind.folder, title: '公开收藏夹'),
      ],
      ProfileSection.bangumi || ProfileSection.cinema => const [
        ProfileEntry(
          id: '9007199254740993123',
          seasonId: '9007199254740993123',
          kind: ProfileEntryKind.season,
          title: '番剧与影视',
          subtitle: '全 12 集',
        ),
      ],
      _ => const <ProfileEntry>[],
    };
    return ProfilePage(items: List.unmodifiable(items), hasMore: false);
  }
}

class _Images implements OriginalImageRepository {
  final sources = <Uri>[];
  @override
  Future<OriginalImage> load(
    Uri source,
    RequestCancellation cancellation,
  ) async {
    sources.add(source);
    throw const AppFailure(AppFailureKind.network, '离线预览测试');
  }
}
