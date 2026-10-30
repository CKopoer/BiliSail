import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../messages/message_fakes.dart';

const _id = UserId('7');
const _folder = ProfileEntry(
  id: '42',
  kind: ProfileEntryKind.folder,
  title: '收藏夹',
);

void main() {
  late _Profile repository;
  late AuthFake auth;
  late ProviderContainer container;
  ProfileController controller() =>
      container.read(profileControllerProvider(_id).notifier);

  setUp(() {
    repository = _Profile();
    auth = AuthFake();
    container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
  });

  tearDown(() async {
    debugOnRebuildDirtyWidget = null;
    container.dispose();
    await auth.stream.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    double width = 1600,
    double scale = 1,
    ValueChanged<VideoSummary>? onOpenVideo,
    ValueChanged<UserId>? onOpenUser,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child ?? const SizedBox(),
          ),
          home: Scaffold(
            body: ProfileScreen(
              id: _id,
              isSelf: true,
              initialSection: ProfileSection.folders,
              onOpenVideo: onOpenVideo,
              onOpenUser: onOpenUser,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [375.0, 1600.0]) {
    testWidgets('folder scrolling reuses mounted cards at width=$width', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, width: width);
      controller().openFolder(_folder);
      await tester.pumpAndSettle();
      final mounted = tester.elementList(find.byType(VideoCard)).toSet();
      expect(mounted.length, greaterThan(0));
      expect(mounted.length, lessThan(100));
      final position = _position(tester);
      var rebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (mounted.contains(element)) rebuilds++;
      };
      for (var frame = 0; frame < 30; frame++) {
        position.jumpTo(position.pixels + 1);
        await tester.pump(const Duration(milliseconds: 16));
      }
      debugOnRebuildDirtyWidget = null;
      debugPrint(
        'folder width=$width: mounted=${mounted.length}, '
        'rebuilds over 30 scroll frames=$rebuilds',
      );
      expect(rebuilds, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('folder pagination and profile loading reuse unchanged cards', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    controller().openFolder(_folder);
    await tester.pumpAndSettle();
    final mounted = tester.elementList(find.byType(VideoCard)).toSet();
    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (mounted.contains(element)) rebuilds++;
    };
    await controller().loadProfile();
    await tester.pumpAndSettle();
    final pending = Completer<ProfilePage>();
    repository.pending = pending;
    final loading = controller().load();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    debugOnRebuildDirtyWidget = null;
    debugPrint('folder state-only card rebuilds=$rebuilds');
    expect(rebuilds, 0);
    final offset = _position(tester).pixels;
    pending.complete(ProfilePage(items: _videos('next'), hasMore: false));
    await loading;
    await tester.pumpAndSettle();
    expect(
      container.read(profileControllerProvider(_id)).current.items,
      hasLength(200),
    );
    expect(_position(tester).pixels, offset);
    _position(tester).jumpTo(_position(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('next video 99'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'folder cards update after resize, text scaling and replacement',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      VideoSummary? opened;
      UserId? author;
      await mount(tester);
      controller().openFolder(_folder);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(VideoCard).first).width,
        closeTo(297.6, .01),
      );
      await mount(
        tester,
        width: 375,
        scale: 2,
        onOpenVideo: (video) => opened = video,
        onOpenUser: (id) => author = id,
      );
      expect(
        tester.getSize(find.byType(VideoCard).first).width,
        closeTo(343, .01),
      );
      final card = tester.widget<VideoCard>(find.byType(VideoCard).first);
      card.onTap();
      card.onOpenUser?.call(const UserId('8'));
      expect(opened?.title, '42 video 0');
      expect(author, const UserId('8'));
      repository.replacement = true;
      await controller().load(refresh: true);
      await tester.pumpAndSettle();
      expect(find.text('replacement video 0'), findsOneWidget);
      expect(find.text('42 video 0'), findsNothing);
      controller().openFolder(
        const ProfileEntry(
          id: '43',
          kind: ProfileEntryKind.folder,
          title: '另一个收藏夹',
        ),
      );
      repository.replacement = false;
      await controller().load(refresh: true);
      await tester.pumpAndSettle();
      expect(find.text('43 video 0'), findsOneWidget);
      expect(find.text('replacement video 0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

List<ProfileEntry> _videos(String prefix) => [
  for (var i = 0; i < 100; i++)
    ProfileEntry(
      id: '$prefix-$i',
      kind: ProfileEntryKind.video,
      title: '$prefix video $i',
      video: VideoSummary(
        id: VideoId('BV${i.toString().padLeft(10, '0')}'),
        title: '$prefix video $i',
        author: 'UP',
        authorId: const UserId('8'),
        coverUrl: '',
        duration: const Duration(minutes: 1),
      ),
    ),
];

final class _Profile implements ProfileRepository {
  @override
  String get accountScope => 'user:1';
  @override
  int get sessionEpoch => 1;
  Completer<ProfilePage>? pending;
  bool replacement = false;

  @override
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => UserProfile(id: id, name: '主页');

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
    required RequestCancellation cancellation,
  }) async {
    if (section != ProfileSection.folders || folderId == null) {
      return const ProfilePage(items: [_folder], hasMore: false);
    }
    if (pending case final request?) {
      pending = null;
      return request.future;
    }
    return ProfilePage(
      items: _videos(replacement ? 'replacement' : folderId),
      hasMore: page == 1,
    );
  }
}
