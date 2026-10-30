import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in DanmakuMode.values) {
    for (final fontSize in [2.4, 12.0, 24.0]) {
      for (final spacing in [0.0, 5.0]) {
        test(
          '${mode.name} area follows tall viewports at size $fontSize and gap $spacing',
          () {
            final vod = DanmakuController(monotonicNow: () => Duration.zero);
            final live = LiveDanmakuController(
              monotonicNow: () => Duration.zero,
            );
            addTearDown(vod.dispose);
            addTearDown(live.dispose);
            final text = TextPainter(
              text: TextSpan(
                text: 'line',
                style: TextStyle(fontSize: fontSize),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            addTearDown(text.dispose);
            final laneHeight = text.height + spacing;
            final events = [
              for (var i = 0; i < 160; i++)
                DanmakuEvent(
                  id: '$i',
                  at: Duration.zero,
                  text: 'line',
                  mode: mode,
                  fontSize: fontSize,
                ),
            ];
            for (final area in [.25, .5, .75, 1.0]) {
              vod.setViewport(width: 1920, height: 1440, bottomInset: 60);
              live.setViewport(width: 1920, height: 1440, bottomInset: 60);
              vod.configure(
                area: area,
                speed: 1,
                topInset: 20,
                lineSpacing: spacing,
              );
              live.configure(
                area: area,
                speed: 1,
                maxPerSecond: 0,
                topInset: 20,
                lineSpacing: spacing,
              );
              vod.replaceEvents(events);
              live.add(
                events.map(
                  (event) => LiveDanmakuEvent(
                    id: event.id,
                    text: event.text,
                    mode: event.mode,
                    fontSize: event.fontSize,
                  ),
                ),
              );
              // Drain bounded admission while both clocks stay at zero.
              for (var frame = 0; frame < 6; frame++) {
                vod.frame();
                live.frame();
              }
              final rows = (1360 * area / laneHeight).floor().clamp(0, 120);
              final vodFrame = vod.frame();
              final liveFrame = live.frame();
              expect(vodFrame, hasLength(rows), reason: 'VOD area $area');
              expect(liveFrame, hasLength(rows), reason: 'live area $area');
              for (var row = 0; row < rows; row++) {
                final y = mode == DanmakuMode.bottom
                    ? 20 + 1360 * area - (row + 1) * laneHeight
                    : 20 + row * laneHeight;
                expect(vodFrame[row].y, closeTo(y, 1e-8));
                expect(liveFrame[row].y, closeTo(y, 1e-8));
              }
              // Resizing uses the same capacity as admission, including rows
              // beyond the old 24-row ceiling, and never replays pruned items.
              vod.setViewport(width: 1920, height: 1080, bottomInset: 60);
              live.setViewport(width: 1920, height: 1080, bottomInset: 60);
              final remaining = (1000 * area / laneHeight).floor().clamp(
                0,
                rows,
              );
              expect(vod.frame(), hasLength(remaining));
              expect(live.frame(), hasLength(remaining));
              vod.setViewport(width: 1920, height: 1440, bottomInset: 60);
              live.setViewport(width: 1920, height: 1440, bottomInset: 60);
              expect(vod.frame(), hasLength(remaining));
              expect(live.frame(), hasLength(remaining));
            }
          },
        );
      }
    }
  }
}
