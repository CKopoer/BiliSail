import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/system_font_catalog.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows enumerates and renders installed and bundled fonts', (
    tester,
  ) async {
    const catalog = NativeSystemFontCatalog();
    expect(catalog.supported, isTrue);
    final families = await catalog.loadFamilies();
    expect(families, isNotEmpty);
    expect(families, contains('Segoe UI'));
    final installed = families.contains('Microsoft YaHei')
        ? 'Microsoft YaHei'
        : 'Segoe UI';
    debugPrint(
      'system_font_catalog: count=${families.length}, preview=$installed',
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: BiliTheme.light(font: AppFontPreference.harmonyOsSans),
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('BiliSail 字体验证', style: TextStyle(fontSize: 24)),
                    for (final family in ['HarmonyOS Sans', installed]) ...[
                      const SizedBox(height: 16),
                      Text(family, style: const TextStyle(fontSize: 16)),
                      Text(
                        '哔帆 · 字体预览 Aa 0123456789',
                        style: TextStyle(fontFamily: family, fontSize: 26),
                      ),
                      Text(
                        '中等与粗体 Medium / Bold',
                        style: TextStyle(
                          fontFamily: family,
                          fontSize: 26,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '哔哩哔哩 BiliSail Bold',
                        style: TextStyle(
                          fontFamily: family,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Check actual rasterization, rather than only TextStyle family metadata.
    Future<List<int>> pixels(String family) async {
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: '哔帆 Aa 0123',
          style: TextStyle(
            fontFamily: family,
            fontSize: 30,
            color: Colors.black,
          ),
        ),
      )..layout();
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), Offset.zero);
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 60);
      final data = await image.toByteData();
      image.dispose();
      picture.dispose();
      painter.dispose();
      return data?.buffer.asUint8List().toList() ?? [];
    }

    final bundled = await pixels('HarmonyOS Sans');
    expect(bundled, isNotEmpty);
    expect(bundled, isNot(await pixels(installed)));
    const output = String.fromEnvironment('FONT_PREVIEW_OUTPUT');
    if (output.isNotEmpty) {
      final render = boundary.currentContext?.findRenderObject();
      expect(render, isA<RenderRepaintBoundary>());
      if (render is RenderRepaintBoundary) {
        final image = await render.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data != null) {
          await File(output).writeAsBytes(data.buffer.asUint8List());
        }
        image.dispose();
      }
    }
    expect(tester.takeException(), isNull);
  });
}
