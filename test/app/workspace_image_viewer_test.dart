// Exercise the pinned SDK's native-dialog path used by desktop playback.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:ui' as ui;

import 'package:bilisail/app/workspace_playback_window.dart';
import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/features/image_viewer/application/image_viewer_controller.dart';
import 'package:bilisail/features/image_viewer/domain/original_image.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:bilisail/shared/ui/comment_rich_content.dart';
import 'package:bilisail/shared/ui/image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/foundation/_features.dart' as flutter_features;
import 'package:flutter/src/widgets/_window.dart' as flutter_window;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/detached_window_fake.dart';
import '../support/input_test_app.dart';
import '../support/native_window_events.dart';

void main() {
  for (final imageCount in [1, 2]) {
    for (final completeBeforeRebuild in [false, true]) {
      testWidgets(
        'desktop comment preview keeps $imageCount originals when rebuilt '
        '${completeBeforeRebuild ? 'after' : 'during'} loading',
        (tester) async {
          final previousWindowing = flutter_features.isWindowingEnabled;
          flutter_features.isWindowingEnabled = true;
          addTearDown(
            () => flutter_features.isWindowingEnabled = previousWindowing,
          );
          for (final name in [
            'bilisail/desktop_window',
            'bilisail/text_input',
          ]) {
            final channel = MethodChannel(name);
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              channel,
              (_) async => null,
            );
            addTearDown(
              () => tester.binding.defaultBinaryMessenger
                  .setMockMethodCallHandler(channel, null),
            );
          }
          final bytes = await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
            final picture = recorder.endRecording();
            final image = await picture.toImage(24, 16);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            picture.dispose();
            if (data == null) throw StateError('PNG missing');
            return data.buffer.asUint8List();
          });
          if (bytes == null) throw StateError('PNG missing');
          final repository = _Originals(
            OriginalImage(bytes: bytes, width: 24, height: 16),
          );
          final sources = [
            Uri.https('i0.hdslb.com', '/first.png'),
            Uri.https('i0.hdslb.com', '/second.png'),
          ].take(imageCount).toList();
          final previews = sources
              .map((uri) => Uri.parse('$uri@1280w_1280h_0e.webp'))
              .toList();
          final initialIndex = sources.length - 1;
          final windows = FakeDetachedWindowFactory(tester.view);
          var backs = 0;
          var closes = 0;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                originalImageRepositoryProvider.overrideWithValue(repository),
              ],
              child: InputTestApp(
                home: DesktopPlaybackWindow(
                  windowFactory: windows.call,
                  onCloseRequested: () => closes++,
                  onError: (error) => fail('$error'),
                  playback: WorkspacePlaybackWindow(
                    shortcuts: const ShortcutSettings.defaults(),
                    theme: ThemeData(),
                    onBack: () => backs++,
                    onClose: () => closes++,
                    onActivateBrowser: () {},
                    child: CommentRichContent(
                      comment: CommentEntry(
                        id: '1',
                        author: 'author',
                        message: 'comment',
                        pictures: sources,
                      ),
                    ),
                  ),
                  child: const Scaffold(body: Text('browser')),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final content = tester.element(find.byType(CommentRichContent));
          final playbackNavigator = Navigator.of(content);
          final browserNavigator = Navigator.of(
            tester.element(find.text('browser')),
          );
          final registry = flutter_window.WindowRegistry.of(content);
          final playback = windows.windows.single;
          // A fake window has no embedder to report activation. Keyboard input
          // must belong to the native focused view, even when a tap focused UI.
          tester.binding.handleViewFocusChanged(
            ui.ViewFocusEvent(
              viewId: playback.viewId,
              state: ui.ViewFocusState.focused,
              direction: ui.ViewFocusDirection.undefined,
            ),
          );
          await tester.pumpAndSettle();
          expect(View.of(content).viewId, playback.viewId);
          expect(registry.windows, isEmpty);

          await tester.tap(
            find
                .descendant(
                  of: find.byType(CommentRichContent),
                  matching: find.byType(InkWell),
                )
                .at(initialIndex),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          final viewer = tester.element(find.byType(ImageViewer));
          expect(View.of(viewer).viewId, playback.viewId);
          expect(Navigator.of(viewer), same(playbackNavigator));
          expect(browserNavigator.canPop(), isFalse);
          expect(registry.windows, isEmpty);
          expect(find.text('$imageCount / $imageCount'), findsOneWidget);
          expect(repository.sources, [previews[initialIndex]]);
          expect(find.text('正在加载预览图…'), findsOneWidget);
          Future<void> completeOriginal() async {
            repository.initial.complete(repository.image);
            await tester.pump();
            expect(find.text('正在加载预览图…'), findsNothing);
            expect(find.byType(InteractiveViewer), findsOneWidget);
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pumpAndSettle();
          }

          if (completeBeforeRebuild) await completeOriginal();
          // Navigator refreshes route pages when the owning window's inherited
          // configuration changes. Keep both pending reads and completed originals.
          ModalRoute.of(viewer)!.changedExternalState();
          await tester.pump();
          expect(repository.reads.single.isCancelled, isFalse);
          if (!completeBeforeRebuild) await completeOriginal();
          expect(find.text('正在加载预览图…'), findsNothing);
          expect(find.byType(InteractiveViewer), findsOneWidget);
          expect(repository.sources, [previews[initialIndex]]);
          await sendNativeWindowBack(tester, playback.viewId);
          expect(backs, 0);
          expect(find.byType(ImageViewer), findsOneWidget);
          await tester.tap(find.byTooltip('放大'));
          await tester.pump();
          expect(find.text('125%'), findsOneWidget);
          ModalRoute.of(viewer)!.changedExternalState();
          await tester.pump();
          expect(find.text('125%'), findsOneWidget);
          expect(find.text('正在加载预览图…'), findsNothing);
          if (imageCount > 1) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
            await tester.pumpAndSettle();
            expect(find.text('1 / 2'), findsOneWidget);
            expect(repository.sources, [previews[1], previews[0]]);
            ModalRoute.of(viewer)!.changedExternalState();
            await tester.pump();
            expect(find.text('1 / 2'), findsOneWidget);
            expect(find.text('正在加载预览图…'), findsNothing);
            expect(find.byType(InteractiveViewer), findsOneWidget);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(ImageViewer), findsNothing);
          expect(
            tester.element(find.byType(CommentRichContent)),
            same(content),
          );
          expect(playbackNavigator.canPop(), isFalse);
          expect(playback.disposed, isFalse);
          expect(windows.creationCount, 1);
          expect(backs, 0);
          expect(closes, 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          expect(playback.disposed, isTrue);
        },
      );
    }
  }
}

class _Originals implements OriginalImageRepository {
  _Originals(this.image);
  final OriginalImage image;
  final initial = Completer<OriginalImage>();
  final sources = <Uri>[];
  final reads = <RequestCancellation>[];

  @override
  Future<OriginalImage> load(Uri source, RequestCancellation cancellation) {
    sources.add(source);
    reads.add(cancellation);
    return sources.length == 1 ? initial.future : Future.value(image);
  }
}
