import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/bili_app.dart';
import 'app/dependencies.dart';
import 'app/release_smoke.dart';
import 'core/presentation/bili_widgets_binding.dart';
import 'core/storage/app_database.dart';
import 'core/storage/credential_store.dart';

Future<void> main(List<String> arguments) async {
  BiliWidgetsBinding.ensureInitialized();
  ReleaseSmokeRequest? smoke;
  var smokeHadError = false;
  try {
    if (Platform.isMacOS) smoke = ReleaseSmokeRequest.parse(arguments);
  } on FormatException {
    exit(1);
  }
  if (smoke != null) {
    // Do not log exception details, which can include plugin or network data.
    FlutterError.onError = (_) => smokeHadError = true;
    PlatformDispatcher.instance.onError = (_, _) {
      smokeHadError = true;
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
  });
  try {
    if (smoke != null && smoke.phase == 'cleanup') {
      await smoke.probeCredentials();
      stdout.writeln(smoke.successMarker);
      await stdout.flush();
      exit(0);
    }
    final dependencies = await AppDependencies.create(
      // Smoke launches cannot restore real accounts or modify the user's DB.
      credentials: smoke == null
          ? null
          : SystemCredentialStore(keyPrefix: '${smoke.prefix}.bootstrap'),
      databaseOverride: smoke == null
          ? null
          : AppDatabase(NativeDatabase.memory()),
    );
    runApp(dependencies.scope(BiliApp(dependencies: dependencies)));
    if (smoke != null) {
      await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
      if (smoke.phase == 'startup') {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      await smoke.probeCredentials();
      runApp(const SizedBox.shrink());
      await WidgetsBinding.instance.endOfFrame;
      await dependencies.close();
      if (smokeHadError) throw StateError('Release application failed');
      stdout.writeln(smoke.successMarker);
      await stdout.flush();
      exit(0);
    }
  } catch (_) {
    if (smoke != null) {
      stderr.writeln('BILISAIL_RELEASE_SMOKE_FAILED:${smoke.phase}');
      exit(1);
    }
    runApp(
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
