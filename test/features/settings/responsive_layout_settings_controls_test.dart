import 'package:bilisail/domain/responsive_layout_settings.dart';
import 'package:bilisail/features/settings/presentation/responsive_layout_settings_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showControls(
    WidgetTester tester, {
    ResponsiveLayoutSettings settings =
        const ResponsiveLayoutSettings.defaults(),
    Future<void> Function(List<int>?)? grid,
    Future<void> Function(int)? sidebar,
    Future<void> Function(int)? playback,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ResponsiveLayoutSettingsControls(
            settings: settings,
            onVideoGridChanged: grid ?? (_) async {},
            onSidebarChanged: sidebar ?? (_) async {},
            onPlaybackChanged: playback ?? (_) async {},
          ),
        ),
      ),
    ),
  );

  final first = find.byKey(const ValueKey('layout-breakpoint-0'));
  testWidgets(
    'numeric threshold validates, saves, cancels and restores defaults',
    (tester) async {
      var saved = 0;
      await showControls(tester, sidebar: (value) async => saved = value);
      await tester.tap(find.text('侧栏展开阈值'));
      await tester.pumpAndSettle();
      await tester.enterText(first, '599');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 600–6000 之间的整数'), findsOneWidget);
      expect(saved, 0);
      await tester.enterText(first, '1280');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(saved, 0);
      await tester.tap(find.text('侧栏展开阈值'));
      await tester.pumpAndSettle();
      await tester.enterText(first, '1280');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved, 1280);
      expect(find.byType(AlertDialog), findsNothing);

      await showControls(
        tester,
        settings: ResponsiveLayoutSettings(sidebarExpandedWidth: 1280),
        sidebar: (value) async => saved = value,
      );
      await tester.tap(find.text('侧栏展开阈值'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(first).controller?.text, '1600');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved, 1600);
    },
  );

  testWidgets(
    'grid rejects unordered values and restores the original algorithm',
    (tester) async {
      List<int>? saved;
      var writes = 0;
      await showControls(
        tester,
        grid: (values) async {
          saved = values;
          writes++;
        },
      );
      await tester.tap(find.text('视频卡片列数阈值'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('video-grid-column-2')));
      final exact = find.byKey(const ValueKey('video-grid-exact-width'));
      await tester.enterText(exact, '500');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 200–491 之间的整数'), findsOneWidget);
      expect(writes, 0);
      await tester.enterText(exact, '320');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved?.first, 320);
      expect(writes, 1);
      await showControls(
        tester,
        settings: ResponsiveLayoutSettings(videoGridMinWidths: saved),
        grid: (values) async {
          saved = values;
          writes++;
        },
      );
      await tester.tap(find.text('视频卡片列数阈值'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(writes, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed save retains draft and allows retry in a narrow dialog',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var fail = true;
      var saved = 0;
      await showControls(
        tester,
        playback: (value) async {
          if (fail) throw StateError('save failed');
          saved = value;
        },
      );
      await tester.tap(find.text('播放页左右布局阈值'));
      await tester.pumpAndSettle();
      await tester.enterText(first, '900');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('设置保存失败，请重试'), findsOneWidget);
      expect(tester.widget<TextFormField>(first).controller?.text, '900');
      fail = false;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved, 900);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
