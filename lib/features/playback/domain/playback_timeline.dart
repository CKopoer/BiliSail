final class VideoChapter {
  const VideoChapter({
    required this.start,
    required this.end,
    required this.title,
  });
  final Duration start, end;
  final String title;
}

/// Gaps remain unnamed; overlapping metadata never creates overlapping tracks.
List<VideoChapter> normalizeChapters(
  List<VideoChapter> chapters,
  Duration total,
) {
  if (total <= Duration.zero) return const [];
  final sorted = chapters.take(200).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final result = <VideoChapter>[];
  for (var i = 0; i < sorted.length; i++) {
    final item = sorted[i];
    final start = item.start < Duration.zero ? Duration.zero : item.start;
    var end = item.end > total ? total : item.end;
    if (i + 1 < sorted.length && sorted[i + 1].start < end) {
      end = sorted[i + 1].start;
    }
    if (end <= start || start >= total || item.title.trim().isEmpty) continue;
    result.add(VideoChapter(start: start, end: end, title: item.title));
  }
  return List.unmodifiable(result);
}

VideoChapter? chapterAt(List<VideoChapter> chapters, Duration position) {
  for (final chapter in chapters) {
    if (position >= chapter.start && position < chapter.end) return chapter;
  }
  return null;
}

final class StoryboardFrame {
  const StoryboardFrame(this.image, this.column, this.row);
  final Uri image;
  final int column, row;
}

final class VideoStoryboard {
  VideoStoryboard({
    required this.columns,
    required this.rows,
    required this.tileWidth,
    required this.tileHeight,
    required Iterable<Uri> images,
    required Iterable<Duration> times,
  }) : images = List.unmodifiable(images),
       times = List.unmodifiable(times);
  final int columns, rows, tileWidth, tileHeight;
  final List<Uri> images;
  final List<Duration> times;
  double get aspectRatio => tileWidth / tileHeight;

  StoryboardFrame? frameAt(Duration position) {
    if (times.isEmpty || images.isEmpty || columns < 1 || rows < 1) return null;
    var low = 0, high = times.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (times[middle] <= position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final index = (low - 1).clamp(0, times.length - 1);
    final perImage = columns * rows;
    final page = index ~/ perImage;
    if (page >= images.length) return null;
    final tile = index % perImage;
    return StoryboardFrame(images[page], tile % columns, tile ~/ columns);
  }
}
