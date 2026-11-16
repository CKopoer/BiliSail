import '../../support/material_tooltip_finder.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/downloads/application/download_controller.dart';
import 'package:bilisail/features/downloads/data/android_public_download_storage.dart';
import 'package:bilisail/features/downloads/presentation/download_destination_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('dev.bilisail/download_storage');
const _root = '/storage/emulated/0';
const _downloads = '$_root/Download';

Map<String, Object?> _listing(String? directory) => {
  'directory': directory == null
      ? null
      : {'path': directory, 'name': directory == _root ? '0' : 'Download'},
  'parent': directory == _downloads ? _root : null,
  'folders': [
    if (directory == null) {'path': _root, 'name': '内部存储'},
    if (directory == _root) {'path': _downloads, 'name': 'Download'},
  ],
};

Future<void> _pump(
  WidgetTester tester, {
  required void Function(bool) onResult,
  bool force = false,
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  GlobalKey? captureKey,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        publicDownloadStorageProvider.overrideWithValue(
          const AndroidPublicDownloadStorage(),
        ),
      ],
      child: RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? BiliTheme.dark() : BiliTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async => onResult(
                  await chooseDownloadDestination(context, ref, force: force),
                ),
                child: const Text('选择下载位置'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('选择下载位置'));
  await tester.pumpAndSettle();
}

Future<void> _openDownloads(WidgetTester tester) async {
  await tester.tap(find.text('内部存储'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Download'));
  await tester.pumpAndSettle();
}

void main() {
  late List<MethodCall> calls;
  late bool remembered, granted;
  late Future<Object?> Function(MethodCall) choose;

  setUpAll(() async {
    await (FontLoader('HarmonyOS Sans')..addFont(
          rootBundle.load(
            'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
          ),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() {
    calls = [];
    remembered = false;
    granted = true;
    choose = (_) async => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'hasDestination' => remembered,
            'requestAccess' => granted,
            'listDirectories' => _listing(
              (call.arguments as Map<Object?, Object?>)['directory'] as String?,
            ),
            'choose' => await choose(call),
            _ => throw StateError(
              'Unexpected storage operation: ${call.method}',
            ),
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets(
    'cancellation leaves destination unchanged and no default is offered',
    (tester) async {
      bool? result;
      await _pump(tester, onResult: (value) => result = value);
      expect(find.textContaining('BiliSail'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '选择此文件夹'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, false);
      expect(calls.map((call) => call.method), [
        'hasDestination',
        'requestAccess',
        'listDirectories',
      ]);
    },
  );

  testWidgets(
    'permission precedes browsing and Downloads root is explicitly selected',
    (tester) async {
      bool? result;
      await _pump(tester, onResult: (value) => result = value);
      await _openDownloads(tester);
      expect(result, isNull);
      expect(find.text(_downloads), findsOneWidget);
      await tester.tap(find.text('选择此文件夹'));
      await tester.pumpAndSettle();
      expect(result, true);
      expect(calls.last.method, 'choose');
      expect(calls.last.arguments, {'directory': _downloads});
      expect(calls.map((call) => call.method).take(3), [
        'hasDestination',
        'requestAccess',
        'listDirectories',
      ]);
    },
  );

  testWidgets(
    'remembered directory skips picker until settings explicitly changes it',
    (tester) async {
      remembered = true;
      bool? result;
      await _pump(tester, onResult: (value) => result = value);
      expect(result, true);
      expect(find.text('选择下载文件夹'), findsNothing);
      await _pump(tester, force: true, onResult: (value) => result = value);
      expect(find.text('选择下载文件夹'), findsOneWidget);
      expect(
        calls.where((call) => call.method == 'hasDestination'),
        hasLength(1),
      );
    },
  );

  testWidgets('denial does not browse or save and supports granting on retry', (
    tester,
  ) async {
    granted = false;
    bool? result;
    await _pump(tester, onResult: (value) => result = value);
    expect(find.textContaining('需要文件访问权限'), findsOneWidget);
    expect(calls.where((call) => call.method == 'listDirectories'), isEmpty);
    expect(result, isNull);
    granted = true;
    await tester.tap(find.text('重新授权'));
    await tester.pumpAndSettle();
    await _openDownloads(tester);
    await tester.tap(find.text('选择此文件夹'));
    await tester.pumpAndSettle();
    expect(result, true);
  });

  testWidgets('save failure stays visible and allows retry', (tester) async {
    choose = (_) async =>
        throw PlatformException(code: 'storage', message: '此文件夹不可写');
    bool? result;
    await _pump(tester, onResult: (value) => result = value);
    await _openDownloads(tester);
    await tester.tap(find.text('选择此文件夹'));
    await tester.pumpAndSettle();
    expect(find.text('此文件夹不可写'), findsOneWidget);
    expect(result, isNull);
    choose = (_) async => null;
    await tester.tap(find.text('选择此文件夹'));
    await tester.pumpAndSettle();
    expect(result, true);
  });

  testWidgets('folder navigation returns to parent and storage devices', (
    tester,
  ) async {
    await _pump(tester, onResult: (_) {});
    await _openDownloads(tester);
    await tester.tap(findMaterialTooltip('上一级'));
    await tester.pumpAndSettle();
    expect(find.text(_root), findsOneWidget);
    await tester.tap(findMaterialTooltip('上一级'));
    await tester.pumpAndSettle();
    expect(find.text('内部存储'), findsOneWidget);
    expect(find.text('选择存储位置'), findsOneWidget);
  });

  testWidgets('pending save prevents duplicate requests and back', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    choose = (_) => pending.future;
    bool? result;
    await _pump(tester, onResult: (value) => result = value);
    await _openDownloads(tester);
    await tester.tap(find.text('选择此文件夹'));
    await tester.pump();
    await tester.tap(find.text('选择此文件夹'));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(calls.where((call) => call.method == 'choose'), hasLength(1));
    expect(find.text('选择下载文件夹'), findsOneWidget);
    expect(result, isNull);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(result, true);
  });

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        'themed folder browser dark=$dark width=$width with large text',
        (tester) async {
          final captureKey = GlobalKey();
          await _pump(
            tester,
            onResult: (_) {},
            dark: dark,
            size: Size(width, 844),
            textScale: width == 320 ? 1.5 : 1,
            captureKey: captureKey,
          );
          await tester.tap(find.text('内部存储'));
          await tester.pumpAndSettle();
          final context = tester.element(find.text('选择下载文件夹'));
          expect(
            Theme.of(context).brightness,
            dark ? Brightness.dark : Brightness.light,
          );
          expect(tester.takeException(), isNull);
          final previewDirectory =
              Platform.environment['DOWNLOAD_DESTINATION_PREVIEW_DIR'];
          if (previewDirectory != null) {
            final boundary =
                captureKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$previewDirectory/folder-${dark ? 'dark' : 'light'}-${width.toInt()}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
