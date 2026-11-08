import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/switching_video_output.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Output implements FlutterVideoOutput, VideoFrameReadiness {
  _Output(this.color);
  final Color color;
  final ready = ValueNotifier(true);
  @override
  ValueListenable<bool> get frameReady => ready;
  @override
  void attach(Object owner) {}
  @override
  void detach(Object owner) {}
  @override
  void updateViewport(
    Object owner, {
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) {}
  @override
  Widget buildVideoSurface() => ColoredBox(color: color);
}

void main() {
  testWidgets(
    'runtime replacement shares retained pixels through child disposal',
    (tester) async {
      final child = SwitchingVideoOutput()
        ..bind(_Output(const Color(0xFF123456)));
      final output = SwitchingVideoOutput()..bind(child);
      await tester.pumpWidget(VideoSurface.output(output: output));
      await tester.runAsync(child.retainFrame);
      await tester.pump();
      final original = tester.widget<RawImage>(find.byType(RawImage)).image!;
      await tester.runAsync(output.retainFrame);
      output.bind(null);
      child.dispose();
      await tester.pump();
      final retained = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect(original.debugDisposed, true);
      final pixels = await tester.runAsync(() => retained.toByteData());
      expect(pixels!.getUint8(0), 0x12);
      expect(pixels.getUint8(1), 0x34);
      expect(pixels.getUint8(2), 0x56);
      await tester.pumpWidget(const SizedBox.shrink());
      output.dispose();
      await tester.pump();
      expect(retained.debugDisposed, true);
    },
  );
  testWidgets(
    'retained pixels cover an absent output and an unready replacement',
    (tester) async {
      final output = SwitchingVideoOutput()
        ..bind(_Output(const Color(0xFF123456)));
      await tester.pumpWidget(VideoSurface.output(output: output));
      await tester.runAsync(output.retainFrame);
      await tester.pump();
      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      final bytes = await tester.runAsync(() => image.toByteData());
      expect(bytes!.getUint8(0), 0x12);
      expect(bytes.getUint8(1), 0x34);
      expect(bytes.getUint8(2), 0x56);
      expect(image.width * image.height, lessThanOrEqualTo(1920 * 1080));
      output.bind(null);
      await tester.pump();
      expect(output.frameReady.value, true);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(image));
      final replacement = _Output(const Color(0xFFFF0000))..ready.value = false;
      output.bind(replacement);
      await tester.pump();
      await tester.runAsync(output.retainFrame);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(image));
      replacement.ready.value = true;
      await tester.pump();
      // A video frame alone cannot expose a replacement whose audio is pending.
      expect(find.byType(RawImage), findsOneWidget);
      output.clearRetainedFrame();
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(image.debugDisposed, true);
      await tester.pumpWidget(const SizedBox.shrink());
      output.dispose();
    },
  );

  testWidgets('clearing or disposing retires a pending frame capture', (
    tester,
  ) async {
    for (final dispose in [false, true]) {
      final output = SwitchingVideoOutput()
        ..bind(_Output(const Color(0xFF123456)));
      await tester.pumpWidget(VideoSurface.output(output: output));
      await tester.runAsync(() async {
        final capturing = output.retainFrame();
        if (dispose) {
          output.dispose();
        } else {
          output.clearRetainedFrame();
        }
        await capturing;
      });
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      if (!dispose) output.dispose();
    }
  });
}
