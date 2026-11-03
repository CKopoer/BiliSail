import 'dart:async';
import 'dart:ui' as ui;

import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('new playback mounts only in its prepared view', (tester) async {
    final prepared = Completer<void>();
    final views = <int>[];
    late _FakeWindow window;
    await tester.pumpWidget(
      DesktopPlaybackWindow(
        playback: Builder(
          builder: (context) {
            views.add(View.of(context).viewId);
            return const SizedBox();
          },
        ),
        onCloseRequested: () {},
        onError: (error) => fail('$error'),
        windowFactory: ({required title, required onCloseRequested}) =>
            window = _FakeWindow(
              tester.view,
              onCloseRequested,
              onPrepare: () => prepared.future,
            ),
        child: const SizedBox(),
      ),
    );
    await tester.pump(Duration.zero);
    expect(views, isEmpty);
    prepared.complete();
    await tester.pumpAndSettle();
    expect(views, [window.viewId]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(window.disposed, isTrue);
  });

  testWidgets('cancelled new playback never starts its page work', (
    tester,
  ) async {
    final prepared = Completer<void>();
    var builds = 0;
    late _FakeWindow window;
    Widget build(bool open) => DesktopPlaybackWindow(
      playback: open
          ? Builder(
              builder: (_) {
                builds++;
                return const SizedBox();
              },
            )
          : null,
      onCloseRequested: () {},
      onError: (error) => fail('$error'),
      windowFactory: ({required title, required onCloseRequested}) =>
          window = _FakeWindow(
            tester.view,
            onCloseRequested,
            onPrepare: () => prepared.future,
          ),
      child: const SizedBox(),
    );
    await tester.pumpWidget(build(true));
    await tester.pump(Duration.zero);
    await tester.pumpWidget(build(false));
    prepared.complete();
    await tester.pumpAndSettle();
    expect(builds, 0);
    expect(window.disposed, isTrue);
  });

  testWidgets(
    'application exit waits for unmount, geometry and native destroy',
    (tester) async {
      final controller = DesktopPlaybackWindowController();
      final saved = Completer<void>();
      late _FakeWindow window;
      var unmounted = false;
      var creations = 0;
      var completed = false;
      Widget build(Object token) => DesktopPlaybackWindow(
        controller: controller,
        activationToken: token,
        playback: _DisposeProbe(onDispose: () => unmounted = true),
        onCloseRequested: () => fail('Shutdown must not navigate'),
        onError: (error) => fail('$error'),
        windowFactory: ({required title, required onCloseRequested}) {
          creations++;
          return window = _FakeWindow(
            tester.view,
            onCloseRequested,
            onSave: () => saved.future,
            onDispose: () {
              expect(unmounted, isTrue);
              expect(find.byType(View), findsOneWidget);
            },
          );
        },
        child: const SizedBox(key: ValueKey('browser')),
      );
      await tester.pumpWidget(build('first'));
      await tester.pumpAndSettle();
      final closing = controller.close();
      expect(controller.close(), same(closing));
      unawaited(closing.then((_) => completed = true));
      await tester.pumpAndSettle();
      expect(unmounted, isTrue);
      expect(window.disposed, isFalse);
      expect(completed, isFalse);
      saved.complete();
      await tester.pumpAndSettle();
      await closing;
      expect(window.disposed, isTrue);
      expect(completed, isTrue);
      expect(find.byKey(const ValueKey('browser')), findsOneWidget);
      await tester.pumpWidget(build('later'));
      await tester.pumpAndSettle();
      expect(creations, 1);
      expect(find.byType(_DisposeProbe), findsNothing);
    },
  );

  testWidgets('application exit cancels queued creation before native entry', (
    tester,
  ) async {
    final controller = DesktopPlaybackWindowController();
    await tester.pumpWidget(
      DesktopPlaybackWindow(
        controller: controller,
        playback: const SizedBox(),
        onCloseRequested: () {},
        onError: (error) => fail('$error'),
        windowFactory: ({required title, required onCloseRequested}) =>
            throw StateError('Creation must be cancelled'),
        child: const SizedBox(),
      ),
    );
    final closing = controller.close();
    await tester.pumpAndSettle();
    await closing;
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed fullscreen close barrier retains the native view', (
    tester,
  ) async {
    final controller = DesktopPlaybackWindowController();
    final normal = Completer<void>();
    final failure = StateError('AppKit transition failed');
    late _FakeWindow window;
    await tester.pumpWidget(
      DesktopPlaybackWindow(
        controller: controller,
        playback: const SizedBox(),
        onCloseRequested: () {},
        onError: (error) => fail('$error'),
        windowFactory: ({required title, required onCloseRequested}) =>
            window = _FakeWindow(
              tester.view,
              onCloseRequested,
              onPrepareClose: () => normal.future,
            ),
        child: const SizedBox(key: ValueKey('browser')),
      ),
    );
    await tester.pumpAndSettle();
    final closing = controller.close();
    final failed = expectLater(closing, throwsA(same(failure)));
    await tester.pumpAndSettle();
    normal.completeError(failure);
    await tester.pumpAndSettle();
    await failed;
    expect(tester.takeException(), same(failure));
    expect(window.disposed, isFalse);
    expect(find.byKey(const ValueKey('browser')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('application exit drains every cancelled and current prepare', (
    tester,
  ) async {
    final controller = DesktopPlaybackWindowController();
    final ready = [Completer<void>(), Completer<void>()];
    final windows = <_FakeWindow>[];
    var completed = false;
    Widget build(bool open) => DesktopPlaybackWindow(
      controller: controller,
      playback: open ? const SizedBox() : null,
      onCloseRequested: () {},
      onError: (error) => fail('$error'),
      windowFactory: ({required title, required onCloseRequested}) {
        final index = windows.length;
        final window = _FakeWindow(
          tester.view,
          onCloseRequested,
          viewId: 100 + index,
          onPrepare: () => ready[index].future,
        );
        windows.add(window);
        return window;
      },
      child: const SizedBox(),
    );
    await tester.pumpWidget(build(true));
    await tester.pump(Duration.zero);
    await tester.pumpWidget(build(false));
    await tester.pumpWidget(build(true));
    await tester.pump(Duration.zero);
    expect(windows, hasLength(2));
    final closing = controller.close();
    unawaited(closing.then((_) => completed = true));
    ready.last.complete();
    await tester.pumpAndSettle();
    expect(windows.last.disposed, isTrue);
    expect(completed, isFalse);
    ready.first.complete();
    await tester.pumpAndSettle();
    await closing;
    expect(windows.every((window) => window.disposed), isTrue);
    expect(find.byType(View), findsOneWidget);
  });

  testWidgets(
    'application exit includes a previously unmounted host retiring',
    (tester) async {
      final controller = DesktopPlaybackWindowController();
      final saved = Completer<void>();
      late _FakeWindow window;
      var completed = false;
      await tester.pumpWidget(
        DesktopPlaybackWindow(
          controller: controller,
          playback: const SizedBox(),
          onCloseRequested: () {},
          onError: (error) => fail('$error'),
          windowFactory: ({required title, required onCloseRequested}) =>
              window = _FakeWindow(
                tester.view,
                onCloseRequested,
                onSave: () => saved.future,
              ),
          child: const SizedBox(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      final closing = controller.close();
      unawaited(closing.then((_) => completed = true));
      await tester.pumpAndSettle();
      expect(completed, isFalse);
      saved.complete();
      await tester.pumpAndSettle();
      await closing;
      expect(window.disposed, isTrue);
    },
  );

  testWidgets(
    'macOS native preflight grants support and revokes it on rejection',
    (tester) async {
      const channel = MethodChannel('bilisail/application_window');
      var ready = false;
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return ready;
      });
      addTearDown(() async {
        ready = false;
        await expectLater(
          DetachedPlaybackWindow.prepareMacOSWindowing(),
          throwsUnsupportedError,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      await expectLater(
        DetachedPlaybackWindow.prepareMacOSWindowing(),
        throwsUnsupportedError,
      );
      expect(DetachedPlaybackWindow.isSupported, isFalse);
      ready = true;
      await DetachedPlaybackWindow.prepareMacOSWindowing();
      expect(DetachedPlaybackWindow.isSupported, isTrue);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'engine_unavailable'),
      );
      await expectLater(
        DetachedPlaybackWindow.prepareMacOSWindowing(),
        throwsA(isA<PlatformException>()),
      );
      expect(DetachedPlaybackWindow.isSupported, isFalse);
      expect(calls, ['prepareWindowing', 'prepareWindowing']);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => false,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'macOS implicit view rejects detached creation before entering native code',
    (tester) async {
      expect(tester.binding.platformDispatcher.implicitView, isNotNull);
      expect(DetachedPlaybackWindow.isSupported, isFalse);
      expect(
        () => DetachedPlaybackWindow.create(
          title: 'Playback',
          onCloseRequested: () {},
        ),
        throwsUnsupportedError,
      );
      expect(tester.binding.platformDispatcher.views, hasLength(1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Windows supports detached playback alongside its implicit view',
    (tester) async {
      expect(tester.binding.platformDispatcher.implicitView, isNotNull);
      expect(DetachedPlaybackWindow.isSupported, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('pending playback moves to its view without disposing state', (
    tester,
  ) async {
    var disposals = 0;
    final probe = _DisposeProbe(onDispose: () => disposals++);
    await tester.pumpWidget(
      DesktopPlaybackWindow(
        keepPlaybackMounted: true,
        playback: probe,
        onCloseRequested: () {},
        onError: (error) => fail('$error'),
        windowFactory: ({required title, required onCloseRequested}) =>
            _FakeWindow(tester.view, onCloseRequested),
        child: const SizedBox(),
      ),
    );
    final pending = tester.element(
      find.byType(_DisposeProbe, skipOffstage: false),
    );
    expect(View.of(pending).viewId, tester.view.viewId);
    expect(disposals, 0);
    await tester.pump(Duration.zero);
    expect(tester.element(find.byType(_DisposeProbe)), same(pending));
    expect(View.of(pending).viewId, 100);
    expect(disposals, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    expect(disposals, 1);
  });

  testWidgets('media updates reuse the window without stealing focus', (
    tester,
  ) async {
    late _FakeWindow window;
    var creations = 0;
    Widget build(Object token) => DesktopPlaybackWindow(
      playback: const SizedBox(),
      activationToken: token,
      onCloseRequested: () {},
      onError: (error) => fail('$error'),
      windowFactory: ({required title, required onCloseRequested}) {
        expect(SchedulerBinding.instance.schedulerPhase, SchedulerPhase.idle);
        creations++;
        return window = _FakeWindow(tester.view, onCloseRequested);
      },
      child: const SizedBox(),
    );
    await tester.pumpWidget(build('video'));
    await tester.pumpWidget(build('video'));
    await tester.pump(Duration.zero);
    expect(creations, 1);
    expect(window.activations, 0);
    await tester.pumpWidget(build('live'));
    await tester.pump(Duration.zero);
    expect(creations, 1);
    expect(window.activations, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    expect(window.disposed, isTrue);
  });

  testWidgets(
    'opening queues a native event without waiting for another frame',
    (tester) async {
      var frameFinished = false;
      var creations = 0;
      bool? frameAtCreation;
      SchedulerPhase? phaseAtCreation;
      Widget build(bool open) => DesktopPlaybackWindow(
        playback: open ? const SizedBox() : null,
        onCloseRequested: () {},
        onError: (error) => fail('$error'),
        windowFactory: ({required title, required onCloseRequested}) {
          frameAtCreation = frameFinished;
          phaseAtCreation = SchedulerBinding.instance.schedulerPhase;
          creations++;
          return _FakeWindow(tester.view, onCloseRequested);
        },
        child: const SizedBox(),
      );
      await tester.pumpWidget(build(false));
      tester.binding.addPostFrameCallback((_) => frameFinished = true);
      final element = tester.element(find.byType(DesktopPlaybackWindow));
      tester.binding.buildOwner!.buildScope(
        element,
        () => element.update(build(true)),
      );
      expect(creations, 0);
      await tester.pump(Duration.zero);
      expect(creations, 1);
      expect(frameAtCreation, isFalse);
      expect(phaseAtCreation, SchedulerPhase.idle);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'close waits for playback to unmount before destroying its view',
    (tester) async {
      late _FakeWindow window;
      var closeRequests = 0;
      var playbackUnmounted = false;
      Widget build(bool open) => DesktopPlaybackWindow(
        playback: open
            ? _DisposeProbe(onDispose: () => playbackUnmounted = true)
            : null,
        onCloseRequested: () => closeRequests++,
        onError: (error) => fail('$error'),
        windowFactory: ({required title, required onCloseRequested}) {
          return window = _FakeWindow(
            tester.view,
            onCloseRequested,
            onDispose: () => expect(playbackUnmounted, isTrue),
          );
        },
        child: const SizedBox(),
      );
      await tester.pumpWidget(build(true));
      await tester.pump(Duration.zero);
      window.requestClose();
      window.requestClose();
      expect(closeRequests, 0);
      await tester.pump(Duration.zero);
      expect(closeRequests, 1);
      expect(window.disposed, isFalse);
      expect(playbackUnmounted, isFalse);
      await tester.pumpWidget(build(false));
      await tester.pump(Duration.zero);
      expect(window.disposed, isTrue);
      expect(playbackUnmounted, isTrue);
    },
  );

  testWidgets('closing before the next frame cancels pending creation', (
    tester,
  ) async {
    var creations = 0;
    Widget build(bool open) => DesktopPlaybackWindow(
      playback: open ? const SizedBox() : null,
      onCloseRequested: () {},
      onError: (error) => fail('$error'),
      windowFactory: ({required title, required onCloseRequested}) {
        creations++;
        return _FakeWindow(tester.view, onCloseRequested);
      },
      child: const SizedBox(),
    );
    await tester.pumpWidget(build(false));
    final element = tester.element(find.byType(DesktopPlaybackWindow));
    tester.binding.buildOwner!.buildScope(element, () {
      element.update(build(true));
    });
    expect(creations, 0);
    await tester.pumpWidget(build(false));
    expect(creations, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmounting before the next frame cancels pending creation', (
    tester,
  ) async {
    var creations = 0;
    Widget build(bool open) => DesktopPlaybackWindow(
      playback: open ? const SizedBox() : null,
      onCloseRequested: () {},
      onError: (error) => fail('$error'),
      windowFactory: ({required title, required onCloseRequested}) {
        creations++;
        return _FakeWindow(tester.view, onCloseRequested);
      },
      child: const SizedBox(),
    );
    await tester.pumpWidget(build(false));
    final element = tester.element(find.byType(DesktopPlaybackWindow));
    tester.binding.buildOwner!.buildScope(element, () {
      element.update(build(true));
    });
    expect(creations, 0);
    await tester.pumpWidget(const SizedBox());
    expect(creations, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rapid reopen creates one window for the latest request', (
    tester,
  ) async {
    var creations = 0;
    final titles = <String>[];
    Widget build(String? title) => DesktopPlaybackWindow(
      title: title ?? 'closed',
      activationToken: title,
      playback: title == null ? null : const SizedBox(),
      onCloseRequested: () {},
      onError: (error) => fail('$error'),
      windowFactory: ({required title, required onCloseRequested}) {
        creations++;
        titles.add(title);
        return _FakeWindow(tester.view, onCloseRequested);
      },
      child: const SizedBox(),
    );
    await tester.pumpWidget(build(null));
    final element = tester.element(find.byType(DesktopPlaybackWindow));
    tester.binding.buildOwner!.buildScope(element, () {
      element.update(build('first'));
      element.update(build(null));
      element.update(build('latest'));
    });
    expect(creations, 0);
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(creations, 1);
    expect(titles, ['latest']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reopen waits for the previous engine and fullscreen window to retire',
    (tester) async {
      final release = Completer<void>();
      final normal = Completer<void>();
      final windows = <_FakeWindow>[];
      Widget build(bool open) => DesktopPlaybackWindow(
        playback: open ? const SizedBox(key: ValueKey('player')) : null,
        waitForPlaybackRelease: () => release.future,
        onCloseRequested: () {},
        onError: (error) => fail('$error'),
        windowFactory: ({required title, required onCloseRequested}) {
          final window = _FakeWindow(
            tester.view,
            onCloseRequested,
            viewId: 100 + windows.length,
            onPrepareClose: () => normal.future,
          );
          windows.add(window);
          return window;
        },
        child: const SizedBox(key: ValueKey('browser')),
      );
      Future<void> frames() async {
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(build(true));
      await frames();
      await tester.pumpWidget(build(false));
      await tester.pumpWidget(build(true));
      await frames();
      expect(windows, hasLength(1));
      expect(windows.first.disposed, isFalse);
      expect(find.byKey(const ValueKey('player')), findsNothing);
      release.complete();
      await frames();
      expect(windows, hasLength(1));
      normal.complete();
      await frames();
      expect(windows.first.disposed, isTrue);
      expect(windows, hasLength(2));
      expect(find.byKey(const ValueKey('player')), findsOneWidget);
      expect(find.byKey(const ValueKey('browser')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await frames();
    },
  );

  testWidgets('closing after the frame cancels the queued native event', (
    tester,
  ) async {
    var creations = 0;
    Widget build(bool open) => DesktopPlaybackWindow(
      playback: open ? const SizedBox() : null,
      onCloseRequested: () {},
      onError: (error) => fail('$error'),
      windowFactory: ({required title, required onCloseRequested}) {
        creations++;
        return _FakeWindow(tester.view, onCloseRequested);
      },
      child: const SizedBox(),
    );
    await tester.pumpWidget(build(true));
    expect(creations, 0);
    final element = tester.element(find.byType(DesktopPlaybackWindow));
    tester.binding.buildOwner!.buildScope(element, () {
      element.update(build(false));
    });
    await tester.pump(Duration.zero);
    expect(creations, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'creation failures are reported once and leave browsing mounted',
    (tester) async {
      final errors = <Object>[];
      final error = StateError('native view unavailable');
      var creations = 0;
      Widget build() => DesktopPlaybackWindow(
        playback: const SizedBox(),
        onCloseRequested: () {},
        onError: errors.add,
        windowFactory: ({required title, required onCloseRequested}) {
          creations++;
          throw error;
        },
        child: const SizedBox(key: ValueKey('browser')),
      );
      await tester.pumpWidget(build());
      await tester.pumpWidget(build());
      await tester.pump(Duration.zero);
      expect(creations, 1);
      expect(errors, [same(error)]);
      expect(find.byKey(const ValueKey('browser')), findsOneWidget);
    },
  );
  testWidgets(
    'prepare restores before mounting and coalesces latest media/title',
    (tester) async {
      final ready = Completer<void>();
      final titles = <String>[];
      late _FakeWindow window;
      var creations = 0;
      Widget build(String title, String token) => DesktopPlaybackWindow(
        title: title,
        activationToken: token,
        playback: const SizedBox(key: ValueKey('player')),
        onCloseRequested: () {},
        onError: (error) => fail('$error'),
        windowFactory: ({required title, required onCloseRequested}) {
          creations++;
          return window = _FakeWindow(
            tester.view,
            onCloseRequested,
            onPrepare: () => ready.future,
            onSetTitle: titles.add,
          );
        },
        child: const SizedBox(),
      );
      await tester.pumpWidget(build('first', 'video'));
      await tester.pump(Duration.zero);
      expect(
        find.byKey(const ValueKey('player'), skipOffstage: false),
        findsNothing,
      );
      await tester.pumpWidget(build('latest', 'live'));
      await tester.pump(Duration.zero);
      expect(creations, 1);
      ready.complete();
      await tester.pumpAndSettle();
      expect(
        View.of(tester.element(find.byKey(const ValueKey('player')))).viewId,
        100,
      );
      expect(titles, ['latest']);
      expect(window.activations, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(window.disposed, isTrue);
    },
  );

  for (final removeHost in [false, true]) {
    testWidgets(
      'pending restore safely retires after close/host removal=$removeHost',
      (tester) async {
        final ready = Completer<void>();
        final errors = <Object>[];
        late _FakeWindow window;
        Widget build(bool open) => DesktopPlaybackWindow(
          playback: open ? const SizedBox() : null,
          onCloseRequested: () {},
          onError: errors.add,
          windowFactory: ({required title, required onCloseRequested}) =>
              window = _FakeWindow(
                tester.view,
                onCloseRequested,
                onPrepare: () => ready.future,
              ),
          child: const SizedBox(),
        );
        await tester.pumpWidget(build(true));
        await tester.pump(Duration.zero);
        await tester.pumpWidget(removeHost ? const SizedBox() : build(false));
        ready.complete();
        await tester.pumpAndSettle();
        expect(window.disposed, isTrue);
        expect(errors, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'restore failure destroys its native window and reports the real error',
    (tester) async {
      final errors = <Object>[];
      final failure = StateError('restore failed');
      late _FakeWindow window;
      await tester.pumpWidget(
        DesktopPlaybackWindow(
          playback: const SizedBox(),
          onCloseRequested: () {},
          onError: errors.add,
          windowFactory: ({required title, required onCloseRequested}) =>
              window = _FakeWindow(
                tester.view,
                onCloseRequested,
                onPrepare: () => Future.error(failure),
              ),
          child: const SizedBox(key: ValueKey('browser')),
        ),
      );
      await tester.pumpAndSettle();
      expect(window.disposed, isTrue);
      expect(errors, [same(failure)]);
      expect(find.byKey(const ValueKey('browser')), findsOneWidget);
    },
  );

  testWidgets(
    'late close from old preparing/retiring window cannot close the new media',
    (tester) async {
      final ready = Completer<void>(), saved = Completer<void>();
      final windows = <_FakeWindow>[];
      var closes = 0;
      Widget build(bool open) => DesktopPlaybackWindow(
        playback: open ? const SizedBox() : null,
        onCloseRequested: () => closes++,
        onError: (error) => fail('$error'),
        windowFactory: ({required title, required onCloseRequested}) {
          final old = windows.isEmpty;
          final window = _FakeWindow(
            tester.view,
            onCloseRequested,
            viewId: 100 + windows.length,
            onPrepare: old ? () => ready.future : null,
            onSave: old ? () => saved.future : null,
          );
          windows.add(window);
          return window;
        },
        child: const SizedBox(),
      );
      await tester.pumpWidget(build(true));
      await tester.pump(Duration.zero);
      await tester.pumpWidget(build(false));
      await tester.pumpWidget(build(true));
      await tester.pump(Duration.zero);
      windows.first.requestClose();
      expect(closes, 0);
      ready.complete();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      windows.first.requestClose();
      expect(closes, 0);
      expect(windows.first.disposed, isFalse);
      windows.last.requestClose();
      await tester.pump(Duration.zero);
      expect(closes, 1);
      saved.complete();
      await tester.pumpAndSettle();
      expect(windows.first.disposed, isTrue);
      expect(windows.last.disposed, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'external destruction disposes after its notifier stack unwinds',
    (tester) async {
      late _FakeWindow window;
      var closes = 0;
      await tester.pumpWidget(
        DesktopPlaybackWindow(
          playback: const SizedBox(),
          onCloseRequested: () => closes++,
          onError: (error) => fail('$error'),
          windowFactory: ({required title, required onCloseRequested}) =>
              window = _FakeWindow(tester.view, onCloseRequested),
          child: const SizedBox(),
        ),
      );
      await tester.pumpAndSettle();
      window.destroyNative();
      expect(window.disposed, isFalse);
      await tester.pump(Duration.zero);
      expect(closes, 1);
      await tester.pumpAndSettle();
      expect(window.disposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native title failure while preparing reports before retiring the request',
    (tester) async {
      final ready = Completer<void>();
      final errors = <Object>[];
      final failure = StateError('native title failed');
      late _FakeWindow window;
      Widget build(String title) => DesktopPlaybackWindow(
        title: title,
        playback: const SizedBox(),
        onCloseRequested: () {},
        onError: errors.add,
        windowFactory: ({required title, required onCloseRequested}) =>
            window = _FakeWindow(
              tester.view,
              onCloseRequested,
              onPrepare: () => ready.future,
              onSetTitle: (_) => throw failure,
            ),
        child: const SizedBox(),
      );
      await tester.pumpWidget(build('old'));
      await tester.pump(Duration.zero);
      await tester.pumpWidget(build('new'));
      ready.complete();
      await tester.pumpAndSettle();
      expect(errors, [same(failure)]);
      expect(window.disposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('destruction while preparing never mounts a dead view', (
    tester,
  ) async {
    final ready = Completer<void>();
    final errors = <Object>[];
    late _FakeWindow window;
    await tester.pumpWidget(
      DesktopPlaybackWindow(
        playback: const SizedBox(),
        onCloseRequested: () {},
        onError: errors.add,
        windowFactory: ({required title, required onCloseRequested}) =>
            window = _FakeWindow(
              tester.view,
              onCloseRequested,
              onPrepare: () => ready.future,
            ),
        child: const SizedBox(),
      ),
    );
    await tester.pump(Duration.zero);
    window.destroyNative();
    ready.complete();
    await tester.pumpAndSettle();
    expect(window.disposed, isTrue);
    expect(errors.single, isStateError);
    expect(find.byType(View), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeWindow extends DetachedPlaybackWindow {
  _FakeWindow(
    ui.FlutterView mainView,
    this.requestClose, {
    this.onDispose,
    this.onPrepare,
    this.onSave,
    this.onPrepareClose,
    this.onSetTitle,
    int viewId = 100,
  }) : view = _SecondaryView(mainView, viewId: viewId);

  final _SecondaryView view;
  final VoidCallback requestClose;
  final VoidCallback? onDispose;
  final Future<void> Function()? onPrepare;
  final Future<void> Function()? onSave;
  final Future<void> Function()? onPrepareClose;
  final ValueChanged<String>? onSetTitle;
  bool nativeClosed = false;
  var disposed = false;
  var activations = 0;

  @override
  int get viewId => view.viewId;

  @override
  bool get isOpen => !disposed && !nativeClosed;

  void destroyNative() {
    nativeClosed = true;
    notifyListeners();
  }

  @override
  Future<void> prepare() => onPrepare?.call() ?? Future.value();

  @override
  Future<void> saveGeometry() => onSave?.call() ?? Future.value();

  @override
  Future<void> prepareToClose() => onPrepareClose?.call() ?? Future.value();

  @override
  late final windowService = WindowService.forView(
    viewId: viewId,
    setFullScreen: (_) async {},
    activate: () async => activate(),
  );

  @override
  Widget buildView(Widget child) => View(view: view, child: child);

  @override
  void activate() {
    expect(SchedulerBinding.instance.schedulerPhase, SchedulerPhase.idle);
    activations++;
  }

  @override
  void setTitle(String title) {
    expect(SchedulerBinding.instance.schedulerPhase, SchedulerPhase.idle);
    onSetTitle?.call(title);
  }

  @override
  void dispose() {
    expect(SchedulerBinding.instance.schedulerPhase, SchedulerPhase.idle);
    onDispose?.call();
    disposed = true;
    super.dispose();
  }
}

// Additional views follow Flutter's BSD-licensed multi_view_testing.dart
// harness: each fake view owns a render tree without sending it to the engine.
class _SecondaryView extends TestFlutterView {
  _SecondaryView(ui.FlutterView view, {this.viewId = 100})
    : super(
        view: view,
        platformDispatcher: view.platformDispatcher as TestPlatformDispatcher,
        display: view.display as TestDisplay,
      );

  @override
  final int viewId;

  @override
  void render(ui.Scene scene, {ui.Size? size}) {}

  @override
  void updateSemantics(ui.SemanticsUpdate update) {}
}

class _DisposeProbe extends StatefulWidget {
  const _DisposeProbe({required this.onDispose});

  final VoidCallback onDispose;

  @override
  State<_DisposeProbe> createState() => _DisposeProbeState();
}

class _DisposeProbeState extends State<_DisposeProbe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
