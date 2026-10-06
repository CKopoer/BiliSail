import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/bili_app.dart';
import 'app/dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Alibaba PuHuiTi 3.0',
    ], await rootBundle.loadString('assets/fonts/alibaba_puhuiti/LICENSE.txt'));
    final license = await rootBundle.loadString(
      'assets/fonts/harmonyos_sans/LICENSE.txt',
    );
    // The supplied license has trailing NUL padding; retain the source intact.
    yield LicenseEntryWithLineBreaks([
      'HarmonyOS Sans',
    ], license.replaceAll('\u0000', ''));
  });
  try {
    final dependencies = await AppDependencies.create();
    runApp(dependencies.scope(BiliApp(dependencies: dependencies)));
  } catch (_) {
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
