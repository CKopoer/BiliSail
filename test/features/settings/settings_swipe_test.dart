import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _surface = find.byKey(const ValueKey('settings-category-swipe'));

void main() {
  late ValueNotifier<SettingsCategory> category;
  late ValueNotifier<bool> active;
  late _Repository repository;
  late List<SettingsCategory> changes;

  setUp(() {
    category = ValueNotifier(SettingsCategory.appearance);
    active = ValueNotifier(true);
    repository = _Repository();
    changes = [];
  });
  tearDown(() {
    category.dispose();
    active.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: active,
              builder: (_, visible, _) => WorkspaceActivity(
                active: visible,
                child: ValueListenableBuilder(
                  valueListenable: category,
                  builder: (_, value, _) => SettingsScreen(
                    category: value,
                    onCategoryChanged: (next) {
                      changes.add(next);
                      category.value = next;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> swipe(WidgetTester tester, double dx) async {
    await tester.dragFrom(
      tester.getBottomRight(_surface) - const Offset(5, 80),
      Offset(dx, 0),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'touch visits all categories in both directions without saving settings',
    (tester) async {
      await mount(tester);
      await swipe(tester, 240);
      expect(changes, isEmpty);
      for (final next in SettingsCategory.values.skip(1)) {
        await swipe(tester, -240);
        expect(category.value, next);
      }
      await swipe(tester, -240);
      expect(category.value, SettingsCategory.about);
      for (final next in SettingsCategory.values.reversed.skip(1)) {
        await swipe(tester, 240);
        expect(category.value, next);
      }
      expect(repository.loads, 1);
      expect(repository.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short, cancelled and mouse drags do not change settings category',
    (tester) async {
      await mount(tester);
      await tester.timedDragFrom(
        tester.getBottomRight(_surface) - const Offset(5, 80),
        const Offset(-40, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getBottomRight(_surface) - const Offset(5, 80),
      );
      await gesture.moveBy(const Offset(-240, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      await tester.drag(
        _surface,
        const Offset(-240, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(repository.writes, 0);
    },
  );

  testWidgets('continuous swipes only commit the final settings category', (
    tester,
  ) async {
    await mount(tester);
    final start = tester.getBottomRight(_surface) - const Offset(5, 80);
    final first = await tester.startGesture(start);
    await first.moveBy(const Offset(-220, 0));
    await tester.pump();
    await first.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(of: _surface, matching: find.byType(Scrollable))
              .first,
        )
        .position;
    final interruptedPixels = position.pixels;
    final second = await tester.startGesture(start);
    await tester.pump();
    await tester.pump();
    expect(category.value, SettingsCategory.appearance);
    expect(changes, isEmpty);
    expect(position.pixels, closeTo(interruptedPixels, .1));
    await second.moveBy(const Offset(-350, 0));
    await tester.pump();
    expect(position.pixels, closeTo(interruptedPixels + 350, 1));
    await second.up();
    await tester.pumpAndSettle();
    expect(category.value, SettingsCategory.shortcuts);
    expect(changes, [SettingsCategory.shortcuts]);
    expect(repository.loads, 1);
    expect(repository.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'each category retains its own scroll and settings controls still save',
    (tester) async {
      category.value = SettingsCategory.shortcuts;
      await mount(tester);
      final appearance = _position(tester, SettingsCategory.shortcuts);
      await tester.dragFrom(const Offset(370, 650), const Offset(0, -260));
      await tester.pumpAndSettle();
      final saved = appearance.pixels;
      expect(saved, greaterThan(0));
      category.value = SettingsCategory.playback;
      await tester.pumpAndSettle();
      final shortcuts = _position(tester, SettingsCategory.playback);
      await tester.dragFrom(const Offset(370, 650), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(shortcuts.pixels, greaterThan(0));
      expect(appearance.pixels, closeTo(saved, .1));
      category.value = SettingsCategory.shortcuts;
      await tester.pumpAndSettle();
      expect(_position(tester, SettingsCategory.shortcuts), same(appearance));
      expect(appearance.pixels, closeTo(saved, .1));
      category.value = SettingsCategory.appearance;
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '深色'));
      await tester.pumpAndSettle();
      expect(repository.settings.theme, AppThemePreference.dark);
      expect(repository.writes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('external selection and hiding supersede a pending swipe', (
    tester,
  ) async {
    await mount(tester);
    final gesture = await tester.startGesture(
      tester.getBottomRight(_surface) - const Offset(5, 80),
    );
    await gesture.moveBy(const Offset(-220, 0));
    category.value = SettingsCategory.about;
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(category.value, SettingsCategory.about);
    expect(changes, isEmpty);
    category.value = SettingsCategory.appearance;
    await tester.pumpAndSettle();
    final hidden = await tester.startGesture(
      tester.getBottomRight(_surface) - const Offset(5, 80),
    );
    await hidden.moveBy(const Offset(-220, 0));
    active.value = false;
    await tester.pump();
    await hidden.up();
    await tester.pumpAndSettle();
    active.value = true;
    await tester.pumpAndSettle();
    expect(category.value, SettingsCategory.appearance);
    expect(changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop scrollbar and setting sliders retain their input', (
    tester,
  ) async {
    category.value = SettingsCategory.playback;
    await mount(tester, platform: TargetPlatform.windows);
    expect(find.byType(Scrollbar), findsOneWidget);
    final position = _position(tester, SettingsCategory.playback);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: const Offset(300, 650),
        scrollDelta: const Offset(0, 180),
      ),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    position.jumpTo(0);
    await tester.pumpAndSettle();
    final slider = find.byType(Slider).first;
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(category.value, SettingsCategory.playback);
    expect(changes, isEmpty);
    expect(repository.writes, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}

ScrollPosition _position(WidgetTester tester, SettingsCategory category) =>
    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(PageStorageKey('settings-${category.name}')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

final class _Repository implements SettingsRepository {
  AppSettings settings = const AppSettings.defaults();
  int loads = 0, writes = 0;
  @override
  Future<AppSettings> load() async {
    loads++;
    return settings;
  }

  @override
  Future<void> save(AppSettings value) async {
    writes++;
    settings = value;
  }
}
