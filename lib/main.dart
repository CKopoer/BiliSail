import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/bili_app.dart';
import 'app/dependencies.dart';
import 'app/release_smoke.dart';
import 'core/presentation/bili_widgets_binding.dart';
import 'core/presentation/window_input_focus.dart';
import 'core/platform/macos_application_window.dart';
import 'core/storage/app_database.dart';

Future<void> main(List<String> arguments) async {
  if (Platform.isMacOS && arguments.contains(ReleaseSmokeRequest.flag)) {
    // The launcher times native loading separately from Dart probe execution.
    stderr.writeln('BILISAIL_RELEASE_STAGE:dart-entry');
  }
  BiliWidgetsBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  ReleaseSmokeRequest? smoke;
  var smokeHadError = false;
  try {
    if (Platform.isMacOS) smoke = ReleaseSmokeRequest.parse(arguments);
  } on FormatException {
    exit(1);
  }
  WindowInputFocus.instance.initialize(
    nativeSnapshotTimeout: smoke == null ? null : releaseSmokeFocusTimeout,
  );
  if (smoke != null) {
    // Do not log exception details, which can include plugin or network data.
    FlutterError.onError = (_) {
      smokeHadError = true;
      stderr.writeln('BILISAIL_RELEASE_SMOKE_ERROR:framework');
    };
    PlatformDispatcher.instance.onError = (_, _) {
      smokeHadError = true;
      stderr.writeln('BILISAIL_RELEASE_SMOKE_ERROR:asynchronous');
      return true;
    };
  }
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'assets/fonts/harmonyos_sans/LICENSE.txt',
    );
    // The supplied license has trailing NUL padding; retain the source intact.
    yield LicenseEntryWithLineBreaks([
      'HarmonyOS Sans',
    ], license.replaceAll('\u0000', ''));
    yield LicenseEntryWithLineBreaks([
      'Simple Icons (Bilibili)',
    ], await rootBundle.loadString('assets/branding/bilibili_LICENSE.md'));
  });
  MacOSApplicationWindow? applicationWindow;
  void smokeStage(String stage) {
    if (smoke != null) stderr.writeln('BILISAIL_RELEASE_STAGE:$stage');
  }

  void present(Widget app) {
    final window = applicationWindow;
    if (window == null) {
      runApp(app);
    } else {
      window.present(app);
    }
  }

  try {
    if (smoke != null && smoke.phase != 'startup') {
      // Credential restarts exercise the shipped plugin without starting the
      // homepage's concurrent session restore and legacy credential cleanup.
      await smoke.probeCredentials(
        onStep: (step) =>
            stderr.writeln('BILISAIL_CREDENTIAL_STAGE:${step.marker}'),
      );
      if (smokeHadError) throw StateError('Release credential probe failed');
      stdout.writeln(smoke.successMarker);
      await stdout.flush();
      exit(0);
    }
    smokeStage('window-create');
    applicationWindow = await MacOSApplicationWindow.create();
    await applicationWindow?.prepare();
    smokeStage('window-ready');
    smokeStage('dependencies');
    final dependencies = await AppDependencies.create(
      // Smoke launches cannot restore real accounts or modify the user's DB.
      credentials: smoke?.bootstrapCredentials(),
      appRecommendationCredentials: smoke?.recommendationCredentials(),
      databaseOverride: smoke == null
          ? null
          : AppDatabase(NativeDatabase.memory()),
      windowOverride: applicationWindow?.service,
    );
    final app = dependencies.scope(BiliApp(dependencies: dependencies));
    smokeStage('dependencies-ready');
    present(app);
    if (smoke != null) {
      final mainWindow = applicationWindow;
      if (mainWindow == null) {
        throw StateError('macOS smoke requires an explicit main window');
      }
      smokeStage('first-frame-wait');
      await smoke.waitForFirstFrame(
        activate: mainWindow.service.activate,
        rasterized: () => WidgetsBinding.instance.waitUntilFirstFrameRasterized,
      );
      smokeStage('first-frame');
      if (smoke.phase == 'startup') {
        await Future<void>.delayed(const Duration(seconds: 3));
        await verifyMacOSPlaybackWindows(mainWindow, app);
        smokeStage('playback-windows');
      }
      await smoke.probeCredentials();
      smokeStage('credentials');
      present(const SizedBox.shrink());
      await WidgetsBinding.instance.endOfFrame;
      await dependencies.close();
      smokeStage('closed');
      if (smokeHadError) throw StateError('Release application failed');
      stdout.writeln(smoke.successMarker);
      await stdout.flush();
      exit(0);
    }
  } catch (error) {
    if (smoke != null) {
      stderr.writeln(releaseSmokeErrorMarker(error));
      stderr.writeln('BILISAIL_RELEASE_SMOKE_FAILED:${smoke.phase}');
      exit(1);
    }
    if (Platform.isMacOS && applicationWindow == null) {
      // There is no native Flutter window to display the error in. Do not
      // attach runApp to the engine's unbacked compatibility view 0.
      stderr.writeln('BILISAIL_MAIN_WINDOW_FAILED');
      exit(1);
    }
    present(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'BiliSail 启动失败。请确认应用目录完整、本地数据目录可写，随后重新启动。',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
