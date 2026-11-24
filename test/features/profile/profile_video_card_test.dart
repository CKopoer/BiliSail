import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_section_content.dart';
import 'package:bilisail/features/profile/presentation/profile_video_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final video = VideoSummary(
    id: const VideoId('BV1234567890'),
    title: '这是一个很长的投稿标题，用来验证窄窗口与文字放大时依然只有两行并且不会溢出',
    coverUrl: '',
    author: '投稿作者',
    duration: const Duration(minutes: 12, seconds: 34),
    playCount: 23456,
    danmakuCount: 123,
    publishedAt: DateTime(2026, 10, 5),
  );

  for (final width in [343.0, 560.0, 630.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('submission card at width $width and text scale $scale', (
        tester,
      ) async {
        var opened = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: ProfileVideoCard(
                      video: video,
                      onTap: () => opened = true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('12:34'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('2.3万'), findsOneWidget);
        expect(find.text('123'), findsOneWidget);
        expect(find.text('发表于 2026-10-05'), findsOneWidget);
        final title = tester.widget<Text>(find.text(video.title));
        expect(title.maxLines, 2);
        final cover = tester.getSize(find.byType(ClipRRect));
        expect(cover.width, lessThanOrEqualTo(200));
        expect(cover.height, closeTo(cover.width * .6, .01));
        await tester.tap(find.text(video.title));
        expect(opened, isTrue);
      });
    }
  }

  testWidgets('submissions show partial and completed playback on the cover', (
    tester,
  ) async {
    Future<void> render(double? progress) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 343,
              child: CustomScrollView(
                slivers: [
                  ProfileSectionContent(
                    section: ProfileSection.videos,
                    entries: [
                      ProfileEntry(
                        id: video.id.value,
                        kind: ProfileEntryKind.video,
                        title: video.title,
                        video: video,
                        watchProgress: progress,
                      ),
                    ],
                    onOpenFolder: (_) {},
                    onOpenLink: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await render(.25);
    final bar = find.byType(LinearProgressIndicator);
    final cover = find.byType(ClipRRect);
    expect(find.text('03:08/12:34'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(bar).value, .25);
    expect(tester.getBottomRight(bar), tester.getBottomRight(cover));
    expect(tester.getSize(bar), Size(tester.getSize(cover).width, 3));

    await render(1);
    expect(find.text('已看完'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(bar).value, 1);

    await render(null);
    expect(find.text('12:34'), findsOneWidget);
    expect(bar, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
