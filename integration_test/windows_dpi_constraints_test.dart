import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows runner clamps plugin minimum to the monitor work area', (
    tester,
  ) async {
    if (!Platform.isWindows) return;
    const probe = String.fromEnvironment('WINDOW_DPI_PROBE');
    expect(
      probe,
      isNotEmpty,
      reason: 'Run tool/test-window-size.ps1 -Integration',
    );
    await windowManager.ensureInitialized();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('DPI window constraints'))),
      ),
    );
    await tester.pumpAndSettle();
    await windowManager.hide();
    try {
      for (final size in const [
        Size(420, 560),
        Size(420, 900),
        Size(2000, 2000),
      ]) {
        await windowManager.setMinimumSize(size);
        final result = await Process.run(probe, ['$pid']);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stdout, contains('PASS min_track='));
        debugPrint('WINDOW_DPI_CONSTRAINT $size ${result.stdout}');
      }
    } finally {
      await windowManager.setMinimumSize(const Size(420, 560));
    }
    expect(tester.takeException(), isNull);
  });
}
