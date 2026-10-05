import 'package:bilisail/features/playback/domain/playback_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chapters are sorted, clipped, disjoint and preserve gaps', () {
    final chapters = normalizeChapters(const [
      VideoChapter(
        start: Duration(seconds: 30),
        end: Duration(seconds: 200),
        title: 'Last',
      ),
      VideoChapter(
        start: Duration.zero,
        end: Duration(seconds: 15),
        title: 'Intro',
      ),
      VideoChapter(
        start: Duration(seconds: 10),
        end: Duration(seconds: 20),
        title: 'Middle',
      ),
    ], const Duration(seconds: 60));
    expect(chapters.map((c) => c.title), ['Intro', 'Middle', 'Last']);
    expect(chapters.first.end, const Duration(seconds: 10));
    expect(chapters.last.end, const Duration(seconds: 60));
    expect(chapterAt(chapters, const Duration(seconds: 10))?.title, 'Middle');
    expect(chapterAt(chapters, const Duration(seconds: 25)), isNull);
    expect(chapterAt(chapters, const Duration(seconds: 60)), isNull);
    expect(normalizeChapters(chapters, Duration.zero), isEmpty);
  });

  test(
    'storyboard binary lookup selects the last preceding frame across sheets',
    () {
      final shot = VideoStoryboard(
        columns: 2,
        rows: 2,
        tileWidth: 160,
        tileHeight: 90,
        images: [
          Uri.parse('https://i0.hdslb.com/a.jpg'),
          Uri.parse('https://i0.hdslb.com/b.jpg'),
        ],
        times: List.generate(6, (i) => Duration(seconds: i * 5)),
      );
      final before = shot.frameAt(const Duration(seconds: 4));
      expect(before?.column, 0);
      final frame = shot.frameAt(const Duration(seconds: 19));
      expect(frame?.column, 1);
      expect(frame?.row, 1);
      expect(frame?.image.path, '/a.jpg');
      expect(shot.frameAt(const Duration(seconds: 20))?.image.path, '/b.jpg');
      expect(shot.frameAt(const Duration(hours: 1))?.column, 1);
    },
  );
}
