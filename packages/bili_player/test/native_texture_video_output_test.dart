import 'package:bili_player/src/native_texture_video_output.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('presentation waits for the revealed texture to paint', (
    tester,
  ) async {
    final output = NativeTextureVideoOutput();
    addTearDown(output.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: VideoSurface.output(output: output),
      ),
    );
    output.bind(1, const VideoDimensions(320, 180));
    var presented = false;
    final ready = output.confirmFrame().then((_) => presented = true);
    await tester.pump();
    expect(output.frameReady.value, true);
    expect(presented, false);
    await tester.pump();
    await ready;
    expect(presented, true);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('retired callbacks cannot confirm the replacement source', (
    tester,
  ) async {
    final output = NativeTextureVideoOutput();
    addTearDown(output.dispose);
    output.bind(1, const VideoDimensions(320, 180));
    await output.confirmFrame();
    output.clear();
    output.bind(2, const VideoDimensions(320, 180));
    await tester.pump();
    expect(output.frameReady.value, false);
  });

  testWidgets('detaching releases presentation without requiring a new frame', (
    tester,
  ) async {
    final output = NativeTextureVideoOutput();
    addTearDown(output.dispose);
    final owner = Object();
    output.attach(owner);
    output.bind(1, const VideoDimensions(320, 180));
    final ready = output.confirmFrame();
    output.detach(owner);
    await ready;
    output.clear();
    await tester.pump();
    expect(output.frameReady.value, false);
  });
}
