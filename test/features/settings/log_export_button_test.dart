import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/features/settings/application/log_export_controller.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/log_export_repository.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/presentation/log_export_button.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_settings_repository.dart';

void main() {
  for (final initialWidth in [375.0, 1280.0]) {
    testWidgets(
      'export completes after resizing the settings header: $initialWidth',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(initialWidth, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final repository = _Exporter();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(
                MemorySettingsRepository(),
              ),
              logExportRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              builder: AppNoticeHost.builder,
              home: const Scaffold(
                body: SettingsScreen(category: SettingsCategory.subtitles),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('export-logs')));
        await tester.pump();
        // Avoid pumpAndSettle while the export progress indicator is animating.
        for (final width in [320.0, 600.0, 1280.0, 375.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pump();
          final export = find.byKey(const ValueKey('export-logs'));
          if (width < 600) {
            expect(find.byTooltip('正在导出…'), findsOneWidget);
            expect(tester.widget<IconButton>(export).onPressed, isNull);
          } else {
            expect(find.text('正在导出…'), findsOneWidget);
            expect(tester.widget<TextButton>(export).onPressed, isNull);
          }
          expect(tester.getRect(export).right, width - 20);
          expect(
            tester.getCenter(export).dy,
            tester
                .getCenter(find.byKey(const ValueKey('settings-page-title')))
                .dy,
          );
          expect(tester.takeException(), isNull);
        }
        expect(repository.calls, 1);
        repository.pending.complete('Documents/BiliSail/exported_logs/log.zip');
        await tester.pumpAndSettle();
        expect(find.text('日志已导出'), findsOneWidget);
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('导出日志').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final fail in [false, true]) {
    testWidgets('export reports location or error and allows retry: $fail', (
      tester,
    ) async {
      final repository = _Exporter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            logExportRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: const Scaffold(body: LogExportButton()),
          ),
        ),
      );
      await tester.tap(find.text('导出日志'));
      await tester.pump();
      expect(find.text('正在导出…'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('export-logs')))
            .onPressed,
        isNull,
      );
      expect(repository.calls, 1);
      if (fail) {
        repository.pending.completeError(
          const AppFailure(AppFailureKind.storage, '存储空间不足'),
        );
      } else {
        repository.pending.complete('Documents/BiliSail/exported_logs/log.zip');
      }
      await tester.pumpAndSettle();
      if (fail) {
        expect(find.text('存储空间不足'), findsOneWidget);
      } else {
        expect(find.text('日志已导出'), findsOneWidget);
        expect(
          find.textContaining('Documents/BiliSail/exported_logs/log.zip'),
          findsOneWidget,
        );
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
      }
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('export-logs')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

final class _Exporter implements LogExportRepository {
  final pending = Completer<String>();
  int calls = 0;
  @override
  Future<String> export() {
    calls++;
    return pending.future;
  }
}
