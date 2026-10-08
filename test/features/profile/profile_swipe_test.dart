import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilisail/core/presentation/app_image_provider.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';

const _id = UserId('7');
final _surface = find.byKey(const ValueKey('profile-section-swipe'));

void main() {
  late _Profile repository;
  late AuthFake auth;
  late ProviderContainer container;
  ProfileState state() => container.read(profileControllerProvider(_id));
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
    container.dispose();
    await auth.stream.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    AppImageCache? cache,
    bool active = true,
    bool disableAnimations = false,
    ProfileSection initialSection = ProfileSection.videos,
    double width = 375,
    double scale = 1,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget child = MaterialApp(
      theme: ThemeData(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          textScaler: TextScaler.linear(scale),
        ),
        child: child ?? const SizedBox(),
      ),
      home: Scaffold(
        body: WorkspaceActivity(
          active: active,
          child: ProfileScreen(
            id: _id,
            isSelf: true,
            initialSection: initialSection,
          ),
        ),
      ),
    );
    if (cache != null) child = AppImageCacheScope(cache: cache, child: child);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: child),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'touch paging visits each section lazily and stops at both ends',
    (tester) async {
      await mount(tester);
      expect(repository.calls, [ProfileSection.videos]);
      await tester.drag(_surface, const Offset(240, 0));
      await tester.pumpAndSettle();
      expect(state().section, ProfileSection.videos);
      for (final section in ProfileSection.values.skip(1)) {
        await tester.drag(_surface, const Offset(-240, 0));
        await tester.pumpAndSettle();
        expect(state().section, section);
      }
      await tester.drag(_surface, const Offset(-240, 0));
      await tester.pumpAndSettle();
      expect(state().section, ProfileSection.followers);
      for (final section in ProfileSection.values.reversed.skip(1)) {
        await tester.drag(_surface, const Offset(240, 0));
        await tester.pumpAndSettle();
        expect(state().section, section);
      }
      expect(repository.calls, ProfileSection.values);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('short, cancelled, mouse and tab-strip drags keep selection', (
    tester,
  ) async {
    await mount(tester, width: 320, scale: 2);
    await tester.timedDrag(
      _surface,
      const Offset(-45, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    final cancelled = await tester.startGesture(tester.getCenter(_surface));
    await cancelled.moveBy(const Offset(-240, 0));
    await tester.pump();
    await cancelled.cancel();
    await tester.pumpAndSettle();
    await tester.drag(
      _surface,
      const Offset(-240, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final strip = find.byType(SingleChildScrollView);
    await tester.drag(strip, const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(state().section, ProfileSection.videos);
    expect(repository.calls, [ProfileSection.videos]);
    await tester.tap(find.byKey(const ValueKey('profile-tab-followers')));
    await tester.pumpAndSettle();
    expect(state().section, ProfileSection.followers);
    expect(repository.calls, [ProfileSection.videos, ProfileSection.followers]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each section retains scroll, video filter and folder state', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), '关键词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final videos = _position(tester);
    videos.jumpTo(360);
    await tester.pumpAndSettle();
    await tester.drag(_surface, const Offset(-240, 0));
    await tester.pumpAndSettle();
    final dynamics = _position(tester);
    dynamics.jumpTo(270);
    await tester.pumpAndSettle();
    await tester.drag(_surface, const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(_position(tester), same(videos));
    expect(_position(tester).pixels, closeTo(360, .1));
    expect(state().keyword, '关键词');
    controller().select(ProfileSection.dynamics);
    await tester.pumpAndSettle();
    expect(_position(tester), same(dynamics));
    expect(_position(tester).pixels, closeTo(270, .1));
    controller().openFolder(
      const ProfileEntry(id: '42', kind: ProfileEntryKind.folder, title: '夹子'),
    );
    await tester.pumpAndSettle();
    final folder = _position(tester);
    folder.jumpTo(320);
    await tester.pumpAndSettle();
    await tester.drag(_surface, const Offset(-240, 0));
    await tester.pumpAndSettle();
    await tester.drag(_surface, const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(state().folderId, '42');
    expect(_position(tester), same(folder));
    expect(_position(tester).pixels, closeTo(320, .1));
    controller().select(ProfileSection.videos);
    await tester.pumpAndSettle();
    expect(_position(tester), same(videos));
    expect(_position(tester).pixels, closeTo(360, .1));
    videos.jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '关键词',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('external selection and hiding supersede a pending swipe', (
    tester,
  ) async {
    await mount(tester);
    final gesture = await tester.startGesture(tester.getCenter(_surface));
    await gesture.moveBy(const Offset(-240, 0));
    await tester.pump();
    controller().select(ProfileSection.folders);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state().section, ProfileSection.folders);
    expect(repository.calls, [ProfileSection.videos, ProfileSection.folders]);
    final hidden = await tester.startGesture(tester.getCenter(_surface));
    await hidden.moveBy(const Offset(-240, 0));
    await tester.pump();
    await mount(tester, active: false);
    await hidden.up();
    await tester.pumpAndSettle();
    expect(state().section, ProfileSection.folders);
    await tester.drag(_surface, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(state().section, ProfileSection.folders);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'session change disposes retained pages and resets their scroll',
    (tester) async {
      await mount(tester);
      await tester.enterText(find.byType(TextField), '旧账号关键词');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      final old = _position(tester);
      old.jumpTo(350);
      await tester.pumpAndSettle();
      controller().select(ProfileSection.following);
      await tester.pumpAndSettle();
      repository.accountScope = 'user:2';
      repository.sessionEpoch++;
      auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '2'));
      await tester.pumpAndSettle();
      expect(state().section, ProfileSection.videos);
      expect(_position(tester), isNot(same(old)));
      expect(_position(tester).pixels, 0);
      expect(state().lists.keys, [ProfileSection.videos]);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop lists keep scrollbars and reduced motion skips taps', (
    tester,
  ) async {
    await mount(
      tester,
      platform: TargetPlatform.windows,
      disableAnimations: true,
    );
    expect(find.byType(Scrollbar), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-tab-folders')));
    await tester.pump();
    await tester.pump();
    expect(state().section, ProfileSection.folders);
    expect(_position(tester).pixels, 0);
    expect(tester.takeException(), isNull);
  });

  for (final enabled in [true, false]) {
    for (final target in [ProfileSection.dynamics, ProfileSection.folders]) {
      testWidgets(
        'profile $target covers remain painted during paging with cache=$enabled',
        (tester) async {
          final bytes = await tester.runAsync(_png);
          if (bytes == null) throw StateError('Missing PNG');
          var downloads = 0;
          final cache = AppImageCache(
            ImageByteCache(
              enabled: enabled,
              directory: () async =>
                  throw const FileSystemException('optional'),
              loader: (_, _) async {
                downloads++;
                return bytes;
              },
            ),
          );
          repository.covers = true;
          await mount(tester, cache: cache);
          await _loaded(tester);
          final source = target == ProfileSection.dynamics
              ? ProfileSection.videos
              : ProfileSection.dynamics;
          if (source != ProfileSection.videos) {
            controller().select(source);
            await tester.pumpAndSettle();
            await _loaded(tester);
          }
          if (target == ProfileSection.folders) {
            controller().openFolder(
              const ProfileEntry(
                id: '42',
                kind: ProfileEntryKind.folder,
                title: '夹子',
              ),
            );
          } else {
            controller().select(target);
          }
          await tester.pumpAndSettle();
          await _loaded(tester);
          controller().select(source);
          await tester.pumpAndSettle();
          await _loaded(tester);
          final before = downloads;
          final outgoing = _currentList(tester);
          final gesture = await tester.startGesture(tester.getCenter(_surface));
          await gesture.moveBy(const Offset(-80, 0));
          await tester.pump();
          expect(tester.getRect(outgoing).left, closeTo(-80, 1));
          _expectPainted(tester);
          await gesture.moveBy(const Offset(-140, 0));
          await tester.pump();
          expect(state().section, source);
          _expectPainted(tester);
          await gesture.up();
          await tester.pump();
          for (var frame = 0; frame < 8; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            _expectPainted(tester);
          }
          await tester.pumpAndSettle();
          expect(state().section, target);
          _expectPainted(tester);
          final back = await tester.startGesture(tester.getCenter(_surface));
          await back.moveBy(const Offset(80, 0));
          await tester.pump();
          _expectPainted(tester);
          await back.cancel();
          await tester.pumpAndSettle();
          expect(state().section, target);
          _expectPainted(tester);
          expect(downloads, before);
          expect(
            repository.calls,
            ProfileSection.values.take(target.index + 1),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await cache.close();
        },
      );
    }
  }
}

Finder _currentList(WidgetTester tester) {
  final viewport = tester.getRect(_surface);
  final lists = find.byType(CustomScrollView).evaluate().where((element) {
    final rect = tester.getRect(find.byWidget(element.widget));
    return (rect.left - viewport.left).abs() < .1;
  });
  return find.byWidget(lists.single.widget);
}

ScrollPosition _position(WidgetTester tester) {
  final list = _currentList(tester);
  return tester
      .state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      )
      .position;
}

Iterable<Finder> _visibleCovers(WidgetTester tester) sync* {
  final viewport = tester.getRect(_surface);
  for (final element in find.byType(AppNetworkImage).evaluate()) {
    final cover = find.byElementPredicate((value) => identical(value, element));
    if (tester.getRect(cover).overlaps(viewport)) yield cover;
  }
}

void _expectPainted(WidgetTester tester) {
  final covers = _visibleCovers(tester).toList();
  expect(covers, isNotEmpty);
  for (final cover in covers) {
    final images = find.descendant(of: cover, matching: find.byType(RawImage));
    expect(
      images,
      findsOneWidget,
      reason: 'Visible profile cover lost its frame',
    );
    expect(tester.widget<RawImage>(images).image, isNotNull);
  }
}

Future<void> _loaded(WidgetTester tester) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final covers = _visibleCovers(tester).toList();
    if (covers.isNotEmpty &&
        covers.every((cover) {
          final images = tester.widgetList<RawImage>(
            find.descendant(of: cover, matching: find.byType(RawImage)),
          );
          return images.length == 1 && images.single.image != null;
        })) {
      return;
    }
  }
  fail('Profile covers did not load');
}

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 24, 24), Paint()..color = Colors.blue);
  final picture = recorder.endRecording();
  final image = await picture.toImage(24, 24);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) throw StateError('Missing PNG');
  return data.buffer.asUint8List();
}

final class _Profile implements ProfileRepository {
  @override
  String accountScope = 'user:1';
  @override
  int sessionEpoch = 1;
  bool covers = false;
  final calls = <ProfileSection>[];

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
    calls.add(section);
    return ProfilePage(
      items: [
        for (var i = 0; i < (covers ? 4 : 30); i++)
          _entry(section, i, folderId),
      ],
      hasMore: false,
    );
  }

  ProfileEntry _entry(ProfileSection section, int index, String? folderId) {
    if (section == ProfileSection.videos ||
        folderId != null ||
        (covers && section == ProfileSection.dynamics)) {
      final video = VideoSummary(
        id: VideoId('BV00000000$index'),
        title: '${section.name}-$index',
        author: 'UP',
        coverUrl: covers
            ? 'https://i0.hdslb.com/${section.name}-$index.jpg'
            : '',
        duration: const Duration(minutes: 1),
      );
      final post = section == ProfileSection.dynamics
          ? DynamicPost(id: '$index', authorName: 'UP', video: video)
          : null;
      return ProfileEntry(
        id: '$index',
        title: video.title,
        kind: post == null ? ProfileEntryKind.video : ProfileEntryKind.dynamic,
        video: post == null ? video : null,
        dynamicPost: post,
      );
    }
    return ProfileEntry(
      id: '$index',
      title: '${section.name}-$index',
      kind: section == ProfileSection.folders
          ? ProfileEntryKind.folder
          : ProfileEntryKind.user,
      userId: const UserId('8'),
    );
  }
}
