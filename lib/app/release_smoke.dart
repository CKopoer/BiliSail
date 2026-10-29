import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/input/input_stroke.dart';
import '../core/input/shortcut_dispatcher.dart';
import '../core/platform/detached_playback_window.dart';
import '../core/platform/macos_application_window.dart';
import '../core/presentation/app_input_host.dart';
import '../core/presentation/window_input_focus.dart';
import '../core/storage/credential_store.dart';

enum ReleaseCredentialStep {
  empty('empty'),
  writeFirst('write-first'),
  readFirst('read-first'),
  writeSecond('write-second'),
  readSecond('read-second'),
  readRestart('read-restart'),
  delete('delete'),
  deleted('deleted'),
  cleanupBootstrap('cleanup-bootstrap'),
  cleanupRecommendation('cleanup-recommendation');

  const ReleaseCredentialStep(this.marker);
  final String marker;
}

// Run only in the explicit startup smoke of the exact bundle being packaged.
// This must exercise the real FFI twice; a capability check alone would let
// an in-window fallback hide a broken macOS multi-window initialization.
Future<void> verifyMacOSPlaybackWindows(
  MacOSApplicationWindow mainWindow,
  Widget app,
) async {
  final binding = WidgetsBinding.instance;
  final dispatcher = binding.platformDispatcher;
  if (!DetachedPlaybackWindow.isSupported ||
      mainWindow.window.viewId == dispatcher.implicitView?.viewId) {
    throw StateError('macOS requires an explicit main window');
  }
  // Direct binary launches on CI start in the background. Establish the
  // user's foreground-main-window precondition before creating playback;
  // never reactivate playback to hide its missing initial focus event.
  stderr.writeln('BILISAIL_FOCUS_STAGE:foreground');
  await mainWindow.service.activate();
  final foregroundWait = Stopwatch()..start();
  final nativeFocus = WindowInputFocus.instance;
  do {
    await nativeFocus.synchronizeNativeFocusIfSupported();
    if (nativeFocus.viewId == mainWindow.window.viewId) break;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  } while (foregroundWait.elapsed < const Duration(seconds: 2));
  if (nativeFocus.viewId != mainWindow.window.viewId) {
    throw StateError('Smoke requires a foreground main window');
  }
  final baseline = dispatcher.views.length;
  final explicitViews = dispatcher.views.where(
    (view) => view.viewId != dispatcher.implicitView?.viewId,
  );
  if (explicitViews.length != 1) throw StateError('Expected one main window');
  for (var attempt = 0; attempt < 2; attempt++) {
    final playback = DetachedPlaybackWindow.create(
      title: 'BiliSail window validation',
      onCloseRequested: () {},
    );
    final owner = Object();
    var presses = 0;
    final input = ShortcutDispatcher<String>(
      scopeFor: (_) => CommandScope.workspace,
      repeats: (_) => false,
      editorException: (_, _) => false,
    );
    input.replaceBindings({const ShortcutChord('Space'): 'probe'});
    input.register(
      owner: owner,
      scope: CommandScope.workspace,
      active: () => true,
      commands: {
        'probe': (stroke) {
          if (stroke.phase == InputPhase.down) presses++;
          return CommandOutcome.completed;
        },
      },
    );
    try {
      stderr.writeln('BILISAIL_FOCUS_STAGE:prepare');
      await playback.prepare();
      // Check before any second activation: the SDK installs its window
      // delegate after makeKeyAndOrderFront, losing the initial focus event.
      final focus = WindowInputFocus.instance;
      if (!focus.observed || focus.viewId != playback.viewId) {
        throw StateError('Initial native playback focus was not synchronized');
      }
      stderr.writeln('BILISAIL_FOCUS_STAGE:present');
      mainWindow.present(
        app,
        additionalView: playback.buildView(
          AppInputHost<String>(
            dispatcher: input,
            routes: InputRouteObserver(),
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: Center(child: Text('BiliSail window validation')),
            ),
          ),
        ),
      );
      await binding.endOfFrame.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final view = dispatcher.views.singleWhere(
        (view) => view.viewId == playback.viewId,
      );
      if (dispatcher.views.length != baseline + 1 ||
          view.physicalSize.isEmpty) {
        throw StateError('Playback view did not attach');
      }
      stderr.writeln('BILISAIL_FOCUS_STAGE:primary');
      final primary = FocusManager.instance.primaryFocus?.context;
      if (primary == null ||
          !primary.mounted ||
          View.maybeOf(primary)?.viewId != playback.viewId) {
        throw StateError('Initial playback has the wrong Flutter focus');
      }
      // Deliver through the real NSWindow responder/engine/host path, without
      // activating again. Native injection is gated to explicit startup smoke.
      stderr.writeln('BILISAIL_FOCUS_STAGE:space');
      await const MethodChannel('bilisail/application_window')
          .invokeMethod<void>('probeWindowSpace', {'viewId': playback.viewId})
          .timeout(const Duration(seconds: 2));
      final inputWait = Stopwatch()..start();
      final keyboard = HardwareKeyboard.instance;
      bool held() => keyboard.isLogicalKeyPressed(LogicalKeyboardKey.space);
      while ((presses == 0 || held()) &&
          inputWait.elapsed < const Duration(seconds: 2)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (presses != 1 || held()) {
        throw StateError('Playback Space sequence was not handled');
      }
      stderr.writeln('BILISAIL_FOCUS_STAGE:passed');
      await playback.windowService.bindTitleBarBack(
        owner: owner,
        onBack: () {},
      );
      await playback.windowService.activate();
    } finally {
      try {
        await playback.windowService.unbindTitleBarBack(owner);
        await playback.saveGeometry();
      } finally {
        mainWindow.present(app);
        try {
          await binding.endOfFrame.timeout(const Duration(seconds: 5));
        } finally {
          // Native removal can pump frames. Leave the frame stack first.
          await Future<void>.delayed(Duration.zero);
          playback.dispose();
          input.dispose();
        }
      }
    }
    if (dispatcher.views.length != baseline) {
      throw StateError('Playback view did not retire');
    }
  }
}

/// An explicit macOS packaging probe in the shipped application, never enabled
/// by normal launches. Only synthetic values under a fresh random prefix change.
class ReleaseSmokeRequest {
  const ReleaseSmokeRequest._(this.phase, this.runId);

  static const flag = '--bilisail-release-smoke';
  static const phases = {
    'startup',
    'write',
    'read-delete',
    'verify-deleted',
    'cleanup',
  };

  final String phase;
  final String runId;
  String get prefix => 'bilisail.release_smoke.v1.$runId';
  String get successMarker => 'BILISAIL_RELEASE_SMOKE_OK:$phase:$runId';
  String get _value => 'BiliSail synthetic Keychain probe $runId';

  CredentialStore bootstrapCredentials({FlutterSecureStorage? storage}) =>
      SystemCredentialStore(storage: storage, keyPrefix: '$prefix.bootstrap');

  CredentialStore recommendationCredentials({FlutterSecureStorage? storage}) =>
      SystemCredentialStore(
        storage: storage,
        keyPrefix: '$prefix.recommendation',
      );

  // Direct binary launches on CI can remain in the background. Establish the
  // foreground precondition before waiting for the compositor's first frame.
  Future<void> waitForFirstFrame({
    required Future<void> Function() activate,
    required Future<void> Function() rasterized,
  }) async {
    await activate();
    await rasterized();
  }

  static ReleaseSmokeRequest? parse(List<String> arguments) {
    if (!arguments.contains(flag)) return null;
    if (arguments.length != 3 ||
        arguments.first != flag ||
        !phases.contains(arguments[1]) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(arguments[2])) {
      throw const FormatException('Invalid release smoke request');
    }
    return ReleaseSmokeRequest._(arguments[1], arguments[2]);
  }

  Future<void> probeCredentials({
    FlutterSecureStorage? storage,
    void Function(ReleaseCredentialStep)? onStep,
  }) async {
    final secureStorage = storage ?? SystemCredentialStore.defaultStorage;
    final credentials = SystemCredentialStore(
      storage: secureStorage,
      keyPrefix: prefix,
    );
    Future<T> step<T>(
      ReleaseCredentialStep stage,
      Future<T> Function() action,
    ) {
      onStep?.call(stage);
      // A hung native call must fail the child, never retry an uncertain write.
      // The packaging script still owns the 60-second process deadline.
      return action().timeout(const Duration(seconds: 10));
    }

    switch (phase) {
      case 'startup':
        return;
      case 'write':
        await step(
          ReleaseCredentialStep.empty,
          () => _expectDeleted(secureStorage),
        );
        await step(
          ReleaseCredentialStep.writeFirst,
          () => credentials.write('$_value first'),
        );
        if (await step(ReleaseCredentialStep.readFirst, credentials.read) !=
            '$_value first') {
          throw StateError('Keychain write/read failed');
        }
        // Exercise both snapshot slots and the active-reference switch.
        await step(
          ReleaseCredentialStep.writeSecond,
          () => credentials.write(_value),
        );
        if (await step(ReleaseCredentialStep.readSecond, credentials.read) !=
            _value) {
          throw StateError('Keychain snapshot switch failed');
        }
      case 'read-delete':
        if (await step(ReleaseCredentialStep.readRestart, credentials.read) !=
            _value) {
          throw StateError('Keychain read after restart failed');
        }
        await step(ReleaseCredentialStep.delete, credentials.delete);
        await step(
          ReleaseCredentialStep.deleted,
          () => _expectDeleted(secureStorage),
        );
      case 'verify-deleted':
        await step(
          ReleaseCredentialStep.deleted,
          () => _expectDeleted(secureStorage),
        );
      case 'cleanup':
        await step(ReleaseCredentialStep.delete, credentials.delete);
        await step(
          ReleaseCredentialStep.deleted,
          () => _expectDeleted(secureStorage),
        );
        await step(
          ReleaseCredentialStep.cleanupBootstrap,
          bootstrapCredentials(storage: secureStorage).delete,
        );
        await step(
          ReleaseCredentialStep.cleanupRecommendation,
          recommendationCredentials(storage: secureStorage).delete,
        );
    }
  }

  Future<void> _expectDeleted(FlutterSecureStorage storage) async {
    for (final suffix in ['active', 'a', 'b']) {
      if (await storage.read(key: '$prefix.$suffix') != null) {
        throw StateError('Keychain probe slot still exists');
      }
    }
  }
}
