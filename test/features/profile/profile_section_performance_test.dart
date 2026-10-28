import 'dart:collection';

import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/dynamic/application/dynamic_actions_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:bilisail/features/profile/presentation/profile_video_card.dart';
import 'package:bilisail/shared/ui/dynamic_post_interactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';

const _id = UserId('7');

void main() {
  late AuthFake auth;
  late ProviderContainer container;
  late _Controller controller;

  Future<void> render(
    WidgetTester tester, {
    double width = 1600,
    double scale = 1,
    ThemeData? theme,
    ValueChanged<VideoSummary>? onOpenVideo,
    ValueChanged<UserId>? onOpenUser,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme ?? ThemeData(platform: TargetPlatform.windows),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child ?? const SizedBox(),
          ),
          home: Scaffold(
            body: ProfileScreen(
              id: _id,
              initialSection: controller.initial.section,
              isSelf: true,
              onOpenVideo: onOpenVideo,
              onOpenUser: onOpenUser,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester, {
    double width = 1600,
    ProfileSection section = ProfileSection.videos,
    required List<ProfileEntry> entries,
    bool dynamicProbe = false,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    auth = AuthFake();
    controller = _Controller(
      ProfileState(
        sessionGeneration: 1,
        profile: const UserProfile(id: _id, name: '主页'),
        section: section,
        lists: {
          section: ProfileListState(items: entries, page: 1, hasMore: false),
        },
      ),
    );
    container = ProviderContainer(
      overrides: [
        profileControllerProvider(_id).overrideWith(() => controller),
        authRepositoryProvider.overrideWithValue(auth),
        if (dynamicProbe)
          dynamicActionsProvider('entry-0')
              .overrideWith(_DynamicController.new),
      ],
    );
    addTearDown(() async {
      debugOnRebuildDirtyWidget = null;
      container.dispose();
      await auth.stream.close();
    });
    await render(tester, width: width);
  }

  for (final width in [375.0, 1600.0]) {
    for (final section in [ProfileSection.videos, ProfileSection.following]) {
      testWidgets('$section stable scroll delegates at width=$width', (
        tester,
      ) async {
        final entries = _Entries(_entries(section));
        await mount(tester, width: width, section: section, entries: entries);
        final mounted = tester
            .elementList(
              find.byType(
                section == ProfileSection.videos ? ProfileVideoCard : ListTile,
              ),
            )
            .toSet();
        expect(mounted.length, greaterThan(0));
        expect(mounted.length, lessThan(entries.length));
        var rebuilds = 0;
        entries.reset();
        debugOnRebuildDirtyWidget = (element, _) {
          if (mounted.contains(element)) rebuilds++;
        };
        final position = _position(tester);
        for (var frame = 0; frame < 30; frame++) {
          position.jumpTo(position.pixels + 1);
          await tester.pump(const Duration(milliseconds: 16));
        }
        debugOnRebuildDirtyWidget = null;
        debugPrint(
          'profile $section width=$width mounted=${mounted.length} '
          'scroll rebuilds=$rebuilds type scans=${entries.scans}',
        );
        expect(rebuilds, 0);
        expect(entries.scans, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final section in [ProfileSection.videos, ProfileSection.dynamics]) {
    testWidgets('$section ignores profile and other-list updates', (
      tester,
    ) async {
      final entries = _Entries(_entries(section));
      await mount(tester, section: section, entries: entries);
      final mounted = tester
          .elementList(
            find.byType(
              section == ProfileSection.videos
                  ? ProfileVideoCard
                  : InteractiveDynamicPostCard,
            ),
          )
          .toSet();
      var rebuilds = 0;
      entries.reset();
      debugOnRebuildDirtyWidget = (element, _) {
        if (mounted.contains(element)) rebuilds++;
      };
      controller.updateProfile();
      await tester.pumpAndSettle();
      controller.updateOtherList();
      await tester.pumpAndSettle();
      debugOnRebuildDirtyWidget = null;
      debugPrint(
        'profile $section mounted=${mounted.length} unrelated rebuilds=$rebuilds '
        'type scans=${entries.scans} entry reads=${entries.reads}',
      );
      expect(rebuilds, 0);
      expect(entries.scans, 0);
      expect(entries.reads, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('submissions update layout, style and current actions', (
    tester,
  ) async {
    final entries = _Entries(_entries(ProfileSection.videos));
    await mount(tester, width: 1800, entries: entries);
    final cards = find.byType(ProfileVideoCard);
    expect(
      tester.getTopLeft(cards.at(0)).dy,
      tester.getTopLeft(cards.at(2)).dy,
    );
    final wide = tester.getSize(cards.first);
    entries.reset();
    final firstActions = _Actions();
    await render(tester, width: 375, onOpenVideo: firstActions.openVideo);
    final narrow = tester.getSize(cards.first);
    expect(narrow.width, lessThan(wide.width));
    tester.widget<ProfileVideoCard>(cards.first).onTap();
    expect(firstActions.opened, ['0:entry 0']);
    firstActions.version = 1;
    await render(tester, width: 375, onOpenVideo: firstActions.openVideo);
    tester.widget<ProfileVideoCard>(cards.first).onTap();
    expect(firstActions.opened.last, '1:entry 0');
    final nextActions = _Actions();
    await render(
      tester,
      width: 375,
      scale: 2,
      theme: ThemeData(
        platform: TargetPlatform.windows,
        brightness: Brightness.dark,
        fontFamily: 'serif',
      ),
      onOpenVideo: nextActions.openVideo,
    );
    expect(tester.getSize(cards.first).height, greaterThan(narrow.height));
    final title = tester.widget<Text>(find.text('entry 0'));
    expect(title.style?.fontFamily, 'serif');
    expect(Theme.of(tester.element(cards.first)).brightness, Brightness.dark);
    tester.widget<ProfileVideoCard>(cards.first).onTap();
    expect(nextActions.opened, ['0:entry 0']);
    await PaintingBinding.instance.handleSystemMessage({'type': 'fontsChange'});
    await tester.pumpAndSettle();
    expect(entries.scans, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacement, paging status and append preserve list position', (
    tester,
  ) async {
    await mount(tester, entries: _entries(ProfileSection.videos));
    _position(tester).jumpTo(300);
    await tester.pumpAndSettle();
    final offset = _position(tester).pixels;
    final mounted = tester.elementList(find.byType(ProfileVideoCard)).toSet();
    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (mounted.contains(element)) rebuilds++;
    };
    controller.setLoading();
    await tester.pump();
    debugOnRebuildDirtyWidget = null;
    expect(rebuilds, 0);
    controller.replaceList(
      ProfileSection.videos,
      _entries(ProfileSection.videos, prefix: 'replacement'),
    );
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, offset);
    expect(find.textContaining('replacement'), findsWidgets);
    expect(find.textContaining('entry '), findsNothing);
    controller.replaceList(ProfileSection.videos, [
      ..._entries(ProfileSection.videos, prefix: 'replacement'),
      ..._entries(ProfileSection.videos, prefix: 'next'),
    ]);
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, offset);
    for (var i = 0; i < 3; i++) {
      _position(tester).jumpTo(_position(tester).maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(find.text('next 99'), findsOneWidget);
    expect(find.byType(ProfileVideoCard).evaluate().length, lessThan(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained dynamics accept provider updates and new callbacks', (
    tester,
  ) async {
    final entries = _Entries(_entries(ProfileSection.dynamics));
    await mount(
      tester,
      section: ProfileSection.dynamics,
      entries: entries,
      dynamicProbe: true,
    );
    entries.reset();
    final actions = container.read(
      dynamicActionsProvider('entry-0').notifier,
    ) as _DynamicController;
    actions.updateDetail();
    await tester.pumpAndSettle();
    expect(find.text('updated dynamic detail'), findsOneWidget);
    expect(entries.scans, 0);
    expect(entries.reads, 0);
    UserId? opened;
    await render(tester, onOpenUser: (id) => opened = id);
    tester
        .widget<InteractiveDynamicPostCard>(
          find.byType(InteractiveDynamicPostCard).first,
        )
        .onOpenUser
        ?.call(const UserId('99'));
    expect(opened, const UserId('99'));
    controller.replaceList(
      ProfileSection.dynamics,
      _entries(ProfileSection.dynamics, prefix: 'new post'),
    );
    await tester.pumpAndSettle();
    expect(find.text('new post 0'), findsOneWidget);
    expect(find.text('updated dynamic detail'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('relationship rows use replacement data and updated actions', (
    tester,
  ) async {
    await mount(
      tester,
      section: ProfileSection.following,
      entries: _entries(ProfileSection.following),
    );
    UserId? opened;
    await render(tester, onOpenUser: (id) => opened = id);
    await tester.tap(find.text('entry 0'));
    expect(opened, const UserId('8'));
    controller.replaceList(ProfileSection.following, const [
      ProfileEntry(
        id: 'another',
        kind: ProfileEntryKind.user,
        title: 'replacement author',
        userId: UserId('99'),
      ),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('replacement author'));
    expect(opened, const UserId('99'));
    expect(find.text('entry 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updating dynamics leaves the retained submissions unchanged', (
    tester,
  ) async {
    final entries = _Entries(_entries(ProfileSection.videos));
    await mount(tester, entries: entries);
    controller.replaceList(
      ProfileSection.dynamics,
      _entries(ProfileSection.dynamics),
    );
    controller.select(ProfileSection.dynamics);
    await tester.pumpAndSettle();
    final mounted = tester
        .elementList(find.byType(ProfileVideoCard, skipOffstage: false))
        .toSet();
    expect(mounted, isNotEmpty);
    entries.reset();
    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (mounted.contains(element)) rebuilds++;
    };
    controller.replaceList(
      ProfileSection.dynamics,
      _entries(ProfileSection.dynamics, prefix: 'changed'),
    );
    await tester.pumpAndSettle();
    debugOnRebuildDirtyWidget = null;
    expect(find.text('changed 0'), findsOneWidget);
    expect(rebuilds, 0);
    expect(entries.scans, 0);
    expect(entries.reads, 0);
  });
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

List<ProfileEntry> _entries(
  ProfileSection section, {
  String prefix = 'entry',
}) => [
  for (var i = 0; i < 100; i++)
    ProfileEntry(
      id: '$prefix-$i',
      kind: section == ProfileSection.videos
          ? ProfileEntryKind.video
          : section == ProfileSection.dynamics
          ? ProfileEntryKind.dynamic
          : ProfileEntryKind.user,
      title: '$prefix $i',
      userId: const UserId('8'),
      video: section == ProfileSection.videos
          ? VideoSummary(
              id: VideoId('BV${i.toString().padLeft(10, '0')}'),
              title: '$prefix $i',
              author: 'UP',
              coverUrl: '',
              duration: const Duration(minutes: 1),
            )
          : null,
      dynamicPost: section == ProfileSection.dynamics
          ? DynamicPost(id: '$prefix-$i', authorName: 'UP', text: '$prefix $i')
          : null,
    ),
];

final class _Entries extends ListBase<ProfileEntry> {
  _Entries(this.entries);
  final List<ProfileEntry> entries;
  int scans = 0, reads = 0;

  void reset() {
    scans = 0;
    reads = 0;
  }

  @override
  bool every(bool Function(ProfileEntry) test) {
    scans++;
    return super.every(test);
  }

  @override
  int get length => entries.length;
  @override
  set length(int _) => throw UnsupportedError('immutable');
  @override
  ProfileEntry operator [](int index) {
    reads++;
    return entries[index];
  }

  @override
  void operator []=(int index, ProfileEntry entry) =>
      throw UnsupportedError('immutable');
}

final class _Controller extends ProfileController {
  _Controller(this.initial) : super(_id);
  final ProfileState initial;

  @override
  ProfileState build() => initial;

  @override
  void select(ProfileSection section) => state = state.copy(section: section);

  void replaceList(ProfileSection section, List<ProfileEntry> entries) =>
      state = state.copy(
        lists: {
          ...state.lists,
          section: ProfileListState(items: entries, page: 1, hasMore: false),
        },
      );

  void setLoading() => state = state.copy(
    lists: {
      ...state.lists,
      state.section: ProfileListState(
        items: state.current.items,
        page: state.current.page,
        loading: true,
      ),
    },
  );

  void updateProfile() => state = state.copy(
    profile: const UserProfile(id: _id, name: '新资料'),
  );

  void updateOtherList() => state = state.copy(
    lists: {
      ...state.lists,
      ProfileSection.followers: const ProfileListState(page: 1, hasMore: false),
    },
  );
}

final class _Actions {
  int version = 0;
  final opened = <String>[];
  void openVideo(VideoSummary video) => opened.add('$version:${video.title}');
}

final class _DynamicController extends DynamicActionsController {
  _DynamicController() : super('entry-0');

  @override
  DynamicActionsState build() => const DynamicActionsState();

  void updateDetail() => state = state.copy(
    detail: DynamicPost(
      id: id,
      authorName: 'UP',
      text: 'updated dynamic detail',
    ),
  );
}
