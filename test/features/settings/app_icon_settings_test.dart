import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/app_icon.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/presentation/app_icon_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_settings_repository.dart';

const _iconColor = Color(0xffe95480);
const _boundary = ValueKey('icon-settings-pixels');

void main() {
  for (final dark in [false, true]) {
    testWidgets('icon previews keep their colors on open and select: $dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(_iconColor, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(28, 28);
        try {
          return await image.toByteData(format: ui.ImageByteFormat.png);
        } finally {
          image.dispose();
          picture.dispose();
        }
      });
      if (bytes == null) throw StateError('Missing icon fixture');
      final repository = MemorySettingsRepository();
      final icons = _Icons();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repository),
          appIconServiceProvider.overrideWithValue(icons),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final opening = ValueNotifier(0);
      addTearDown(opening.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: DefaultAssetBundle(
            bundle: _IconBundle(bytes),
            child: MaterialApp(
              theme: dark ? BiliTheme.dark() : BiliTheme.light(),
              home: Scaffold(
                body: RepaintBoundary(
                  key: _boundary,
                  child: ValueListenableBuilder(
                    valueListenable: opening,
                    builder: (context, value, child) => Consumer(
                      key: ValueKey(value),
                      builder: (context, ref, child) => AppIconSettings(
                        value: ref
                            .watch(settingsControllerProvider)
                            .requireValue
                            .appIcon,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final context = tester.element(find.byType(AppIconSettings));
        for (final icon in AppIconPreference.values) {
          await precacheImage(AssetImage(icon.asset), context);
        }
      });
      await tester.pumpAndSettle();

      for (final selected in [
        AppIconPreference.bilisail,
        AppIconPreference.bilibili,
        AppIconPreference.bilisail,
      ]) {
        if (repository.value.appIcon != selected) {
          await tester.tap(find.widgetWithText(ChoiceChip, selected.label));
          await tester.pumpAndSettle();
        }
        expect(repository.value.appIcon, selected);
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, selected.label),
              )
              .selected,
          isTrue,
        );
        await _expectIconColors(tester);
        // Recreate the form as on a fresh visit, with images already cached.
        opening.value++;
        await tester.pumpAndSettle();
        await _expectIconColors(tester);
      }
      expect(icons.applied, [
        AppIconPreference.bilibili,
        AppIconPreference.bilisail,
      ]);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _expectIconColors(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  for (final elapsed in [Duration.zero, const Duration(milliseconds: 100)]) {
    await tester.pump(elapsed);
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final pixels = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (pixels == null) throw StateError('Missing settings pixels');
        for (final icon in AppIconPreference.values) {
          final preview = find.descendant(
            of: find.widgetWithText(ChoiceChip, icon.label),
            matching: find.byType(Image),
          );
          final center = boundary.globalToLocal(tester.getCenter(preview));
          final offset =
              (center.dy.floor() * image.width + center.dx.floor()) * 4;
          expect(
            pixels.buffer.asUint8List(pixels.offsetInBytes + offset, 4),
            [0xe9, 0x54, 0x80, 0xff],
            reason: '${icon.label} preview must not be darkened or overpainted',
          );
        }
      } finally {
        image.dispose();
      }
    });
  }
}

final class _IconBundle extends CachingAssetBundle {
  _IconBundle(this.bytes);
  final ByteData bytes;

  @override
  Future<ByteData> load(String key) async =>
      AppIconPreference.values.any((icon) => icon.asset == key)
      ? bytes
      : rootBundle.load(key);
}

final class _Icons implements AppIconService {
  final applied = <AppIconPreference>[];

  @override
  AppIconSurface get surface => AppIconSurface.window;

  @override
  Future<AppIconPreference> restore(AppIconPreference saved) async => saved;

  @override
  Future<void> apply(AppIconPreference icon) async => applied.add(icon);
}
