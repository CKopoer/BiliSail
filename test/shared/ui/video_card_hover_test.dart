import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/video/application/video_card_preview_playback.dart';
import 'package:bilisail/features/video/domain/video_card_interactions.dart';

import '../../support/video_card_fake_engine.dart';

import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_card_cover.dart';
import 'package:bilisail/shared/ui/video_card_interaction_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _video = VideoSummary(
  id: VideoId('BV1234567890'),
  title: '悬停查看视频预览，右上角添加稍后再看',
  coverUrl: '',
  author: '测试 UP 主',
  duration: Duration(seconds: 20),
  playCount: 21000,
  danmakuCount: 36,
  previewCid: '42',
);

void main() {
  setUpAll(() async {
    await (FontLoader('HarmonyOS Sans')..addFont(
          rootBundle.load(
            'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
          ),
        ))
        .load();
    await (FontLoader(
      'BiliIcons',
    )..addFont(rootBundle.load('assets/fonts/biliicon.ttf'))).load();
  });
  testWidgets('disabled hover playback keeps card actions without loading', (
    tester,
  ) async {
    final services = _Interactions();
    var opens = 0;
    await tester.pumpWidget(
      _app(services, hoverPlaybackEnabled: false, open: () => opens++),
    );
    final mouse = await _mouse(tester);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('video-card-cover-scale'))),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(services.reads, 0);
    expect(services.engines, isEmpty);
    expect(
      find.byKey(const ValueKey('video-card-hover-preview')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('video-card-preview')), findsNothing);
    expect(
      tester
          .widget<AnimatedScale>(
            find.byKey(const ValueKey('video-card-cover-scale')),
          )
          .scale,
      1.05,
    );
    await tester.tap(find.byKey(const ValueKey('video-card-watch-later')));
    await tester.pump();
    expect(services.writes, 1);
    expect(opens, 0);
    await tester.tap(find.text(_video.title));
    expect(opens, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('preview listeners exist only during an enabled hover', (
    tester,
  ) async {
    final services = _Interactions();
    final scroll = _CountingScrollController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
    });
    Widget app({
      bool enabled = false,
      bool hovered = true,
      bool cover = true,
    }) => MaterialApp(
      home: Scaffold(
        body: VideoCardInteractionScope(
          interactions: services,
          onNotice: (_, _) {},
          hoverPlaybackEnabled: enabled,
          child: SingleChildScrollView(
            controller: scroll,
            child: SizedBox(
              height: 1000,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  height: 180,
                  child: cover
                      ? VideoCardCover(
                          video: _video,
                          hovered: hovered,
                          child: const ColoredBox(color: Colors.blueGrey),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final owner = find.byKey(const ValueKey('video-card-hover-preview'));
    await tester.pumpWidget(app(cover: false));
    final baseline = scroll.notifier.listenerCount;
    await tester.pumpWidget(app());
    expect(owner, findsNothing);
    expect(scroll.notifier.listenerCount, baseline);
    await tester.pumpWidget(app(enabled: true, hovered: false));
    expect(owner, findsNothing);
    expect(scroll.notifier.listenerCount, baseline);
    await tester.pumpWidget(app(enabled: true));
    expect(owner, findsOneWidget);
    expect(tester.state(owner), isA<WidgetsBindingObserver>());
    expect(scroll.notifier.listenerCount, baseline + 1);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(services.reads, 1);
    await tester.pumpWidget(app());
    expect(owner, findsNothing);
    expect(scroll.notifier.listenerCount, baseline);
    expect(services.token?.isCancelled, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(services.reads, 1);
  });

  for (final enabled in [false, true]) {
    testWidgets('Android touch mounts no preview owner (enabled: $enabled)', (
      tester,
    ) async {
      final services = _Interactions();
      var opens = 0;
      await tester.pumpWidget(
        _app(services, hoverPlaybackEnabled: enabled, open: () => opens++),
      );
      await tester.tap(find.text(_video.title));
      await tester.pump(const Duration(seconds: 1));
      expect(opens, 1);
      expect(
        find.byKey(const ValueKey('video-card-hover-preview')),
        findsNothing,
      );
      expect(services.reads, 0);
      expect(services.engines, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('disabling cancels hover delay and enabling waits again', (
    tester,
  ) async {
    final services = _Interactions();
    await tester.pumpWidget(_app(services));
    final mouse = await _mouse(tester);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('video-card-cover-scale'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(_app(services, hoverPlaybackEnabled: false));
    await tester.pump(const Duration(seconds: 1));
    expect(services.reads, 0);
    await tester.pumpWidget(_app(services));
    await tester.pump(const Duration(milliseconds: 199));
    expect(services.reads, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(services.reads, 1);
    expect(find.byKey(const ValueKey('video-card-preview')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final phase in ['request', 'opening', 'playing']) {
    testWidgets('disabling cancels $phase preview and rejects late results', (
      tester,
    ) async {
      final services = _Interactions();
      final pending = phase == 'playing' ? null : Completer<void>();
      if (phase == 'request') services.pending = pending;
      if (phase == 'opening') services.firstOutput = pending;
      await tester.pumpWidget(_app(services));
      final mouse = await _mouse(tester);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('video-card-cover-scale'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(services.reads, 1);
      expect(services.engines, hasLength(phase == 'request' ? 0 : 1));
      final token = services.token;
      await tester.pumpWidget(_app(services, hoverPlaybackEnabled: false));
      expect(token?.isCancelled, isTrue);
      expect(find.byKey(const ValueKey('video-card-preview')), findsNothing);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      if (phase != 'request') {
        expect(services.engines.single.stops, 1);
        expect(services.engines.single.disposals, 1);
      }
      pending?.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(services.reads, 1);
      expect(find.byKey(const ValueKey('video-card-preview')), findsNothing);
      services.pending = null;
      services.firstOutput = null;
      await tester.pumpWidget(_app(services));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(services.reads, 2);
      expect(find.byKey(const ValueKey('video-card-preview')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'cover remains visible while native open waits for its first output frame',
    (tester) async {
      final frame = Completer<void>();
      final services = _Interactions()..firstOutput = frame;
      await tester.pumpWidget(_app(services));
      final mouse = await _mouse(tester);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('video-card-cover-scale'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 310));
      expect(services.engines, hasLength(1));
      expect(
        find.byKey(const ValueKey('video-card-cover-scale')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('video-card-preview')), findsNothing);
      expect(
        find.byKey(const ValueKey('fake-card-video-surface')),
        findsNothing,
      );
      frame.complete();
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('fake-card-video-surface')),
        findsOneWidget,
      );
      await mouse.moveTo(const Offset(650, 550));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'whole card hover auto plays without pointer motion and stops on exit',
    (tester) async {
      final services = _Interactions();
      var opens = 0;
      final notices = <String>[];
      await tester.pumpWidget(
        _app(services, open: () => opens++, notice: notices.add),
      );
      final mouse = await _mouse(tester);
      final cover = tester.getRect(
        find.byKey(const ValueKey('video-card-cover-scale')),
      );
      await mouse.moveTo(
        Offset(cover.left + cover.width * .1, cover.center.dy),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(services.reads, 0);
      expect(
        tester
            .widget<AnimatedScale>(
              find.byKey(const ValueKey('video-card-cover-scale')),
            )
            .scale,
        1.05,
      );
      expect(
        find.byKey(const ValueKey('video-card-watch-later')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(services.reads, 1);
      expect(services.lastCid, '42');
      expect(
        find.byKey(const ValueKey('fake-card-video-surface')),
        findsOneWidget,
      );
      final engine = services.engines.single;
      engine.advance(const Duration(seconds: 8));
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('video-card-preview-progress')),
            )
            .value,
        .4,
      );
      await mouse.moveTo(tester.getCenter(find.text(_video.title)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(services.reads, 1);
      expect(engine.seeks, 0);
      await tester.tap(find.byKey(const ValueKey('video-card-watch-later')));
      await tester.pump();
      expect(services.writes, 1);
      expect(opens, 0);
      expect(notices, ['已加入稍后再看']);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('video-card-watch-later')));
      await tester.pump();
      expect(services.writes, 1);
      expect(opens, 0);
      await mouse.moveTo(const Offset(650, 550));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(services.token?.isCancelled, true);
      await tester.pump();
      expect(engine.stops, 1);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(engine.disposals, 1);
      expect(
        find.byKey(const ValueKey('fake-card-video-surface')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('video-card-watch-later')),
        findsNothing,
      );
      await tester.tap(find.text(_video.title));
      expect(opens, 1);
    },
  );

  testWidgets(
    'short hover, touch, hidden page and disposed cover stop preview reads',
    (tester) async {
      final services = _Interactions();
      await tester.pumpWidget(_app(services));
      await tester.tap(find.text(_video.title));
      await tester.pump(const Duration(milliseconds: 400));
      expect(services.reads, 0);
      final mouse = await _mouse(tester);
      final center = tester.getCenter(
        find.byKey(const ValueKey('video-card-cover-scale')),
      );
      await mouse.moveTo(center);
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.moveTo(const Offset(650, 550));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(services.reads, 0);
      services.pending = Completer<void>();
      await mouse.moveTo(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 310));
      expect(services.reads, 1);
      await tester.pumpWidget(_app(services, active: false));
      expect(services.token?.isCancelled, true);
      services.pending!.complete();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('fake-card-video-surface')),
        findsNothing,
      );
      await tester.pumpWidget(_app(services));
      await mouse.moveTo(const Offset(650, 550));
      await mouse.moveTo(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(services.token?.isCancelled, true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard focus exposes add button and Enter only adds watch later',
    (tester) async {
      final services = _Interactions();
      var opens = 0;
      await tester.pumpWidget(_app(services, open: () => opens++));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('video-card-watch-later')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('video-card-watch-later')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(services.writes, 1);
      expect(opens, 0);
      expect(services.reads, 0);
    },
  );

  testWidgets(
    'outer scrolling cancels a pending preview and rejects its late result',
    (tester) async {
      final services = _Interactions()..pending = Completer<void>();
      final pending = services.pending;
      final outer = ScrollController();
      final inner = ScrollController();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        outer.dispose();
        inner.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoCardInteractionScope(
              interactions: services,
              onNotice: (_, _) {},
              child: SingleChildScrollView(
                controller: outer,
                child: SizedBox(
                  height: 1200,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 320,
                      height: 400,
                      child: SingleChildScrollView(
                        controller: inner,
                        child: VideoCard(video: _video, onTap: () {}),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await _mouse(tester);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('video-card-cover-scale'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 210));
      expect(services.reads, 1);
      final token = services.token;
      final scrolling = outer.animateTo(
        30,
        duration: const Duration(milliseconds: 400),
        curve: Curves.linear,
      );
      expect(outer.position.isScrollingNotifier.value, true);
      expect(inner.position.isScrollingNotifier.value, false);
      expect(token?.isCancelled, true);
      pending?.complete();
      services.pending = null;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(services.reads, 1);
      final coverScale = tester.widget<AnimatedScale>(
        find.byKey(const ValueKey('video-card-cover-scale')),
      );
      expect(coverScale.scale, 1);
      expect(coverScale.duration, Duration.zero);
      expect(services.engines, isEmpty);
      expect(find.byKey(const ValueKey('video-card-preview')), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      await scrolling;
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 210));
      await tester.pump();
      expect(services.reads, 2);
      expect(services.engines, hasLength(1));
      expect(find.byKey(const ValueKey('video-card-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('watch-later cards hide cover add without changing other cards', (
    tester,
  ) async {
    final services = _Interactions();
    final mouse = await _mouse(tester);
    await tester.pumpWidget(_app(services, showWatchLaterButton: false));
    await mouse.moveTo(tester.getCenter(find.text(_video.title)));
    await tester.pump();
    expect(find.byKey(const ValueKey('video-card-watch-later')), findsNothing);
    await tester.pumpWidget(_app(services));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('video-card-watch-later')),
      findsOneWidget,
    );
  });

  testWidgets(
    'background releases and resume restarts a stationary title hover',
    (tester) async {
      final services = _Interactions();
      await tester.pumpWidget(_app(services));
      final mouse = await _mouse(tester);
      await mouse.moveTo(tester.getCenter(find.text(_video.title)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pump();
      expect(services.reads, 1);
      expect(services.engines.single.options?.play, true);
      expect(services.engines.single.options?.volume, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(services.token?.isCancelled, true);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(services.engines.single.disposals, 1);
      expect(
        find.byKey(const ValueKey('fake-card-video-surface')),
        findsNothing,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(services.reads, 2);
      expect(services.engines, hasLength(2));
      expect(
        find.byKey(const ValueKey('fake-card-video-surface')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'showing a hidden workspace restores hover without mouse movement',
    (tester) async {
      final services = _Interactions();
      await tester.pumpWidget(_app(services));
      final mouse = await _mouse(tester);
      await mouse.moveTo(tester.getCenter(find.text(_video.title)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pump();
      expect(services.reads, 1);
      await tester.pumpWidget(_app(services, active: false));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(services.engines.single.disposals, 1);
      await tester.pumpWidget(_app(services));
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pump();
      expect(services.reads, 2);
      expect(
        find.byKey(const ValueKey('fake-card-video-surface')),
        findsOneWidget,
      );
    },
  );

  testWidgets('hover preview fits narrow cards and double text', (
    tester,
  ) async {
    final key = GlobalKey();
    final mouse = await _mouse(tester);
    for (final (dark, scale, width) in [
      (false, 1.0, 320.0),
      (true, 2.0, 140.0),
    ]) {
      final services = _Interactions();
      await tester.pumpWidget(
        _app(services, dark: dark, scale: scale, width: width, boundary: key),
      );
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('video-card-cover-scale'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pump();
      // The fake engine opens in microtasks; only its fade-in needs fake time.
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(const ValueKey('fake-card-video-surface')),
        findsOneWidget,
        reason: 'dark=$dark scale=$scale reads=${services.reads}',
      );
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('WRITE_UI_PREVIEW')) {
        final boundary = key.currentContext?.findRenderObject();
        if (boundary is! RenderRepaintBoundary) {
          throw StateError('Missing boundary');
        }
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          if (bytes == null) throw StateError('Missing preview');
          final dir = Directory('build/video-card-hover-preview');
          await dir.create(recursive: true);
          await File(
            '${dir.path}/${dark ? 'dark-large-text' : 'light-hover'}.png',
          ).writeAsBytes(bytes.buffer.asUint8List());
        });
      }
      await mouse.moveTo(const Offset(650, 550));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(650, 550));
  addTearDown(mouse.removePointer);
  return mouse;
}

Widget _app(
  _Interactions services, {
  VoidCallback? open,
  ValueChanged<String>? notice,
  bool active = true,
  bool dark = false,
  double scale = 1,
  double width = 320,
  GlobalKey? boundary,
  bool showWatchLaterButton = true,
  bool hoverPlaybackEnabled = true,
}) => MaterialApp(
  theme: dark ? BiliTheme.dark() : BiliTheme.light(),
  home: Scaffold(
    body: VideoCardInteractionScope(
      interactions: services,
      onNotice: (_, message) => notice?.call(message),
      hoverPlaybackEnabled: hoverPlaybackEnabled,
      child: WorkspaceActivity(
        active: active,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: dark ? const Color(0xff121212) : Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: SizedBox(
                        width: width,
                        child: VideoCard(
                          video: _video,
                          onTap: open ?? () {},
                          showWatchLaterButton: showWatchLaterButton,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

class _Interactions implements VideoCardOperations {
  _Interactions() {
    addTearDown(() => unawaited(previews.close()));
  }
  final engines = <CardFakeEngine>[];
  late final previews = VideoCardPreviewPlayback(
    createEngine: () {
      final engine = CardFakeEngine();
      engine.opening = firstOutput;
      engines.add(engine);
      return engine;
    },
  );
  int reads = 0, writes = 0;
  String? lastCid;
  bool added = false;
  RequestCancellation? token;
  Completer<void>? pending;
  Completer<void>? firstOutput;
  @override
  Future<VideoCardPreviewSession?> preview(
    VideoId id,
    RequestCancellation cancellation, {
    String? cid,
  }) async {
    reads++;
    lastCid = cid;
    token = cancellation;
    await pending?.future;
    return previews.start(cardPreviewMedia(), cancellation);
  }

  @override
  Future<WatchLaterResult> addWatchLater(VideoId id) async {
    writes++;
    added = true;
    return WatchLaterResult.added;
  }

  @override
  bool isAdded(VideoId id) => added;
  @override
  bool isUncertain(VideoId id) => false;
}

class _CountingScrollController extends ScrollController {
  _ListenerCountingNotifier get notifier =>
      position.isScrollingNotifier as _ListenerCountingNotifier;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _CountingScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _CountingScrollPosition extends ScrollPositionWithSingleContext {
  _CountingScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final _notifier = _ListenerCountingNotifier();
  @override
  ValueNotifier<bool> get isScrollingNotifier => _notifier;
}

class _ListenerCountingNotifier extends ValueNotifier<bool> {
  _ListenerCountingNotifier() : super(false);
  int listenerCount = 0;

  @override
  void addListener(VoidCallback listener) {
    listenerCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount--;
    super.removeListener(listener);
  }
}
