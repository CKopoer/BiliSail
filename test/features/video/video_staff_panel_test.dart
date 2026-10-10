import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/video/application/video_author_controller.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/application/video_extras_controller.dart';
import 'package:bilisail/features/video/domain/video_author_repository.dart';
import 'package:bilisail/features/video/domain/video_extras_repository.dart';
import 'package:bilisail/features/video/domain/video_repository.dart';
import 'package:bilisail/features/video/presentation/video_author_header.dart';
import 'package:bilisail/features/video/presentation/video_screen.dart';
import 'package:bilisail/shared/ui/user_follow_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('VIDEO_STAFF_PREVIEW')) return;
    for (final font in [
      (
        'HarmonyOS Sans',
        'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
      ),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'staff folds, opens exact user and follows explicitly in ${brightness.name}',
      (tester) async {
        final repo = _Authors();
        UserId? opened;
        await tester.pumpWidget(
          _app(
            repo,
            brightness: brightness,
            child: VideoAuthorHeader(
              video: _video(),
              onOpenUser: (id) => opened = id,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('创作团队'), findsOneWidget);
        expect(find.text('7人'), findsOneWidget);
        expect(find.byType(UserFollowButton), findsNWidgets(5));
        expect(repo.reads, ['42', '43', '44', '45', '46']);
        expect(repo.writes, isEmpty);
        await _snapshot(tester, '${brightness.name}-collapsed');
        await tester.tap(find.text('成员 1'));
        expect(opened, const UserId('43'));
        final follow = find.descendant(
          of: find.byKey(const ValueKey('video-staff-1-43')),
          matching: find.byType(IconButton),
        );
        repo.pending = Completer<void>();
        await tester.tap(follow);
        await tester.pump();
        await tester.tap(follow);
        expect(repo.writes, [('43', true)]);
        expect(opened, const UserId('43'));
        repo.pending!.complete();
        await tester.pumpAndSettle();
        final following = find.descendant(
          of: find.byKey(const ValueKey('video-staff-1-43')),
          matching: find.byType(PopupMenuButton<String>),
        );
        await tester.tap(following);
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消关注'));
        await tester.pumpAndSettle();
        expect(repo.writes, [('43', true), ('43', false)]);
        await tester.tap(find.byKey(const ValueKey('video-staff-toggle')));
        await tester.pumpAndSettle();
        expect(find.byType(UserFollowButton), findsNWidgets(7));
        expect(repo.reads, containsAll(['47', '48']));
        await _snapshot(tester, '${brightness.name}-expanded');
        await tester.tap(find.byKey(const ValueKey('video-staff-toggle')));
        await tester.pumpAndSettle();
        expect(find.byType(UserFollowButton), findsNWidgets(5));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'guest follow opens login and credits without IDs stay noninteractive',
    (tester) async {
      final repo = _Authors();
      var logins = 0;
      await tester.pumpWidget(
        _app(
          repo,
          signedIn: false,
          child: VideoAuthorHeader(
            video: _video(
              members: const [
                VideoStaffMember(id: UserId('42'), name: 'UP', title: 'UP主'),
                VideoStaffMember(name: '未知成员', title: '参演'),
                VideoStaffMember(name: '未知成员', title: '协作'),
              ],
            ),
            onLogin: () => logins++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UserFollowButton), findsOneWidget);
      expect(repo.reads, ['42']);
      await tester.tap(find.byType(IconButton));
      expect(logins, 1);
      expect(repo.writes, isEmpty);
    },
  );

  for (final width in [220.0, 390.0, 1100.0]) {
    testWidgets(
      'team expansion preserves the player at width $width and large text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var created = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(_SignedIn.new),
              videoAuthorRepositoryProvider.overrideWithValue(_Authors()),
              videoRepositoryProvider.overrideWithValue(_Videos()),
              videoExtrasRepositoryProvider.overrideWithValue(_Extras()),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: VideoScreen(
                  id: const VideoId('BV1234567890'),
                  playerBuilder: (_, _, _) =>
                      _Player(onCreate: () => created++),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final player = tester.state(find.byType(_Player));
        await tester.tap(find.byKey(const ValueKey('video-staff-toggle')));
        await tester.pumpAndSettle();
        expect(find.byType(UserFollowButton), findsNWidgets(7));
        expect(tester.state(find.byType(_Player)), same(player));
        expect(created, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('ordinary video retains the existing author statistics', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _Authors(),
        child: VideoAuthorHeader(video: _video(members: const [])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('创作团队'), findsNothing);
    expect(find.text('123粉丝 · 456获赞'), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);
  });
}

Widget _app(
  _Authors authors, {
  required Widget child,
  bool signedIn = true,
  Brightness brightness = Brightness.light,
}) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(signedIn ? _SignedIn.new : _Guest.new),
    videoAuthorRepositoryProvider.overrideWithValue(authors),
  ],
  child: MaterialApp(
    theme: brightness == Brightness.light
        ? BiliTheme.light()
        : BiliTheme.dark(),
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: const ValueKey('staff-preview'),
          child: ColoredBox(
            color: brightness == Brightness.light
                ? Colors.white
                : const Color(0xff171717),
            child: SizedBox(
              width: 380,
              child: Padding(padding: const EdgeInsets.all(12), child: child),
            ),
          ),
        ),
      ),
    ),
  ),
);

VideoDetail _video({List<VideoStaffMember>? members}) => VideoDetail(
  summary: const VideoSummary(
    id: VideoId('BV1234567890'),
    title: '合作视频',
    coverUrl: '',
    author: 'UP',
    duration: Duration(minutes: 3),
  ),
  description: '',
  authorMid: '42',
  parts: const [
    VideoPart(cid: '1', page: 1, title: 'P1', duration: Duration(minutes: 3)),
  ],
  staff:
      members ??
      [
        for (var i = 0; i < 7; i++)
          VideoStaffMember(
            id: UserId('${42 + i}'),
            name: i == 0 ? 'UP' : '成员 $i',
            title: i == 0
                ? 'UP主'
                : i == 1
                ? '赞助商'
                : '参演',
            highlightedRole: i == 1,
            nicknameColor: '#FB7299',
          ),
      ],
);

final class _SignedIn extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.signedIn, mid: '1');
}

final class _Guest extends AuthController {
  @override
  AuthState build() => const AuthState();
}

final class _Authors extends Fake implements VideoAuthorRepository {
  final reads = <String>[];
  final writes = <(String, bool)>[];
  Completer<void>? pending;
  @override
  String get accountScope => 'user:1';
  @override
  int get sessionEpoch => 0;
  @override
  Future<VideoAuthor> load(
    VideoAuthorId id,
    RequestCancellation cancellation,
  ) async {
    reads.add(id.value);
    return const VideoAuthor(
      following: false,
      followerCount: 123,
      likeCount: 456,
    );
  }

  @override
  Future<void> follow(
    VideoAuthorId id,
    bool following,
    RequestCancellation cancellation,
  ) async {
    writes.add((id.value, following));
    await pending?.future;
  }
}

final class _Videos implements VideoRepository {
  @override
  Future<VideoDetail> loadDetail(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async => _video();
}

final class _Extras implements VideoExtrasRepository {
  @override
  Future<List<String>> loadTags(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<List<VideoSummary>> loadRelated(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<VideoCommentsPage> loadComments(
    VideoId id, {
    required int page,
    required RequestCancellation cancellation,
  }) async => const VideoCommentsPage(comments: [], hasMore: false);
}

final class _Player extends StatefulWidget {
  const _Player({required this.onCreate});
  final VoidCallback onCreate;
  @override
  State<_Player> createState() => _PlayerState();
}

final class _PlayerState extends State<_Player> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Future<void> _snapshot(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('VIDEO_STAFF_PREVIEW')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('staff-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Preview encoding failed');
    await Directory('build/video-staff-preview').create(recursive: true);
    await File('build/video-staff-preview/$name.png')
        .writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}
