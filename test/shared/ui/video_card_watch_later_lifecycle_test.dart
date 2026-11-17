import 'dart:async';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/video/application/video_card_preview_playback.dart';
import 'package:bilisail/features/video/domain/video_card_interactions.dart';
import 'package:bilisail/shared/ui/video_card_cover.dart';
import 'package:bilisail/shared/ui/video_card_interaction_scope.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

const _video = VideoSummary(
  id: VideoId('BV1234567890'),
  title: 'Video',
  author: 'Author',
  coverUrl: '',
  duration: Duration.zero,
);

void main() {
  testWidgets('only interactive active covers observe watch-later changes', (
    tester,
  ) async {
    final operations = _Operations();
    final replacement = _Operations();
    addTearDown(operations.changes.close);
    addTearDown(replacement.changes.close);
    Future<void> mount({
      bool active = true,
      bool? hovered = false,
      bool focused = false,
      bool action = true,
      _Operations? source,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceActivity(
              active: active,
              child: VideoCardInteractionScope(
                interactions: source ?? operations,
                hoverPlaybackEnabled: false,
                onNotice: (_, _) {},
                child: SizedBox(
                  width: 320,
                  height: 180,
                  child: VideoCardCover(
                    video: _video,
                    hovered: hovered,
                    focused: focused,
                    showWatchLaterButton: action,
                    child: const ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount();
    expect(operations.changes.hasListener, isFalse);
    await mount(hovered: true);
    expect(operations.changes.hasListener, isTrue);
    operations.added = true;
    operations.changes.add(_video.id);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await mount(active: false, hovered: true);
    expect(operations.changes.hasListener, isFalse);
    operations.added = false;
    operations.changes.add(_video.id);
    await tester.pumpAndSettle();
    await mount(hovered: true);
    expect(operations.changes.hasListener, isTrue);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    await mount(focused: true);
    expect(operations.changes.hasListener, isTrue);
    await mount(focused: true, source: replacement);
    expect(operations.changes.hasListener, isFalse);
    expect(replacement.changes.hasListener, isTrue);
    await mount(focused: true, source: replacement, action: false);
    expect(replacement.changes.hasListener, isFalse);
    await mount(hovered: null);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    await mouse.moveTo(tester.getCenter(find.byType(VideoCardCover)));
    await tester.pumpAndSettle();
    expect(operations.changes.hasListener, isTrue);
    await mouse.moveTo(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(operations.changes.hasListener, isFalse);
    await mouse.removePointer();
    await mount(hovered: true);
    await tester.pumpWidget(const SizedBox());
    expect(operations.changes.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });
}

class _Operations implements VideoCardOperations, VideoCardWatchLaterToggle {
  final changes = StreamController<VideoId>.broadcast(sync: true);
  bool added = false;
  @override
  Stream<VideoId> get watchLaterChanges => changes.stream;
  @override
  bool isAdded(VideoId id) => added;
  @override
  bool isUncertain(VideoId id) => false;
  @override
  bool isWatchLaterBusy(VideoId id) => false;
  @override
  Future<bool> refreshWatchLater() async => true;
  @override
  Future<WatchLaterResult> addWatchLater(VideoId id) async =>
      WatchLaterResult.added;
  @override
  Future<WatchLaterResult> removeWatchLater(VideoId id) async =>
      WatchLaterResult.removed;
  @override
  Future<VideoCardPreviewSession?> preview(
    VideoId id,
    RequestCancellation cancellation, {
    String? cid,
  }) async => null;
}
