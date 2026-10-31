import 'dart:ui' as ui;

import 'package:bilisail/core/platform/window_size_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('complete display takes precedence over a narrow viewport', () {
    final view = _View(
      display: _Display(const ui.Size(2560, 1600), 2),
      physicalSize: const ui.Size(1000, 1600),
      devicePixelRatio: 2,
    );
    final size = WindowSizePolicy.displaySize(view);
    expect(size, const ui.Size(1280, 800));
    expect(WindowSizePolicy.compactDisplay(size), isFalse);
    expect(
      WindowSizePolicy.compactLayout(
        mobile: true,
        displaySize: size,
        availableWidth: 500,
      ),
      isTrue,
    );
  });

  for (final (name, physical, density) in [
    ('Android uninitialized sentinels', const ui.Size(-1, -1), -1.0),
    ('zero display', ui.Size.zero, 2.25),
    ('negative display', const ui.Size(-1, 1600), 2.25),
    ('infinite display', const ui.Size(double.infinity, 1600), 2.25),
    ('NaN display', const ui.Size(double.nan, 1600), 2.25),
    ('zero density', const ui.Size(2560, 1600), 0.0),
    ('negative density', const ui.Size(2560, 1600), -1.0),
    ('infinite density', const ui.Size(2560, 1600), double.infinity),
    ('NaN density', const ui.Size(2560, 1600), double.nan),
    ('overflowing division', const ui.Size(2560, 1600), 1e-308),
  ]) {
    test('$name falls back to the independently reported viewport', () {
      final view = _View(
        display: _Display(physical, density),
        physicalSize: const ui.Size(2560, 1600),
        devicePixelRatio: 2.25,
      );
      final size = WindowSizePolicy.displaySize(view);
      expect(size, const ui.Size(2560, 1600) / 2.25);
      expect(WindowSizePolicy.compactDisplay(size), isFalse);
    });
  }

  test('unknown full display still keeps a landscape phone compact', () {
    final size = WindowSizePolicy.displaySize(
      _View(
        display: _Display(const ui.Size(-1, -1), -1),
        physicalSize: const ui.Size(2532, 1170),
        devicePixelRatio: 3,
      ),
    );
    expect(size, const ui.Size(844, 390));
    expect(
      WindowSizePolicy.compactLayout(
        mobile: true,
        displaySize: size,
        availableWidth: 844,
      ),
      isTrue,
    );
  });

  test(
    'two invalid metric sources remain unavailable to orientation policy',
    () {
      final view = _View(
        display: _Display(const ui.Size(-1, -1), -1),
        physicalSize: const ui.Size(2560, 1600),
        devicePixelRatio: 0,
      );
      expect(WindowSizePolicy.displaySize(view), ui.Size.zero);
    },
  );
}

final class _Display extends Fake implements ui.Display {
  _Display(this.size, this.devicePixelRatio);

  @override
  final ui.Size size;
  @override
  final double devicePixelRatio;
}

final class _View extends Fake implements ui.FlutterView {
  _View({
    required this.display,
    required this.physicalSize,
    required this.devicePixelRatio,
  });

  @override
  final ui.Display display;
  @override
  final ui.Size physicalSize;
  @override
  final double devicePixelRatio;
}
