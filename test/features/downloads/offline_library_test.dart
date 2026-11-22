import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/downloads/domain/download_models.dart';
import 'package:bilisail/features/downloads/domain/offline_library.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const first = VideoId('BV1234567890'), second = VideoId('BV1234567891');
VideoSummary video(VideoId id) => VideoSummary(
  id: id,
  title: '同名投稿',
  author: '同一作者',
  coverUrl: '',
  duration: Duration.zero,
);
VideoPart part(int p) =>
    VideoPart(cid: '$p', page: p, title: '片段 $p', duration: Duration.zero);
DownloadTask task(
  String id,
  DownloadItem item, {
  int quality = 80,
  int day = 1,
}) => DownloadTask(
  id: id,
  scope: 'guest',
  item: item,
  selection: DownloadSelection(quality: quality),
  status: DownloadStatus.completed,
  directory: '',
  createdAt: DateTime(2026, 1, day),
  updatedAt: DateTime(2026, 1, day),
);

void main() {
  test('collection uses source order and original P numbers, one row per content across versions', () {
    const collection = VideoCollection(
      id: '9',
      title: '摄影合集',
      entries: [
        VideoCollectionEntry(id: second, title: '第二个 BV 排在前面', parts: []),
        VideoCollectionEntry(id: first, title: '第一个 BV 排在后面', parts: []),
      ],
    );
    List<DownloadItem> items(VideoId bv) => DownloadItem.fromVideo(
      VideoDetail(
        summary: video(bv),
        description: '投稿介绍',
        parts: [part(2), part(5)],
        collection: collection,
      ),
    );
    final a = items(first), b = items(second);
    final a2 = task('a2', a.first),
        a5 = task('a5', a.last),
        b5 = task('b5', b.last);
    final a2Low = task('low', a.first, quality: 32, day: 2),
        b5Low = task('blow', b.last, quality: 32, day: 2);
    final legacy = task(
      'legacy',
      DownloadItem(video: video(first), part: part(8)),
    );
    final unrelated = task(
      'single',
      DownloadItem(video: video(const VideoId('BV1234567892')), part: part(1)),
      day: 3,
    );
    final library = OfflineLibrary(
      [legacy, a5, a2Low, b5, b5Low, a2, unrelated],
      {a.first.workKey: a.first.work!, b.last.workKey: b.last.work!},
    );
    expect(library.groups.map((g) => g.title), ['同名投稿', '摄影合集']);
    final group = library.find('a2')!.group;
    expect(
      group.entries.map((e) => (e.task.item.video.id, e.task.item.part.page)),
      [(second, 5), (first, 2), (first, 5), (first, 8)],
    );
    expect(group.entries[1].preferred(a2), same(a2));
    expect(group.entries[1].preferred(b5Low), same(a2Low));
    expect(group.entries[0].preferred(a2), same(b5));
    expect(library.workFor(legacy.item)?.description, '投稿介绍');
    expect(group.adjacent(group.entries.last, 1), isNull);
    expect(
      group.adjacent(group.entries.last, 1, loop: true),
      same(group.entries.first),
    );
    expect(library.find('single')!.group.showCurrent, isFalse);
  });
  test('season types and sections survive projection; same title in another season is independent', () {
    PgcSeason season(String id, int type) => PgcSeason(
      id: PgcSeasonId(id),
      title: '同名季',
      type: type,
      description: '整季简介',
      episodes: [
        const PgcEpisode(id: PgcEpisodeId('101'), title: '1', cid: '301'),
        const PgcEpisode(
          id: PgcEpisodeId('102'),
          title: '2',
          cid: '302',
          available: false,
        ),
        const PgcEpisode(
          id: PgcEpisodeId('103'),
          title: '3',
          longTitle: '正片标题',
          cid: '303',
        ),
        const PgcEpisode(
          id: PgcEpisodeId('104'),
          title: '幕后',
          cid: '304',
          sectionTitle: '花絮',
        ),
      ],
    );
    final a = DownloadItem.fromSeason(season('1', 1)),
        b = DownloadItem.fromSeason(season('2', 4));
    expect(a.map((e) => e.part.page), [1, 3, 4]);
    expect(a[1].displayPartTitle, '第 3 集 · 正片标题');
    expect(a[0].work, same(a[1].work));
    expect(a[0].category(a[0].work), DownloadCategory.bangumi);
    expect(b[0].category(b[0].work), DownloadCategory.guochuang);
    final library = OfflineLibrary([
      for (final i in [2, 1, 0]) task('a$i', a[i]),
      task('b0', b[0]),
    ], {});
    final group = library.find('a1')!.group;
    expect(library.groups.length, 2);
    expect(group.adjacent(group.entries[1], 1), isNull);
    expect(
      group.adjacent(group.entries[1], 1, loop: true),
      same(group.entries.first),
    );
    expect(
      group.adjacent(group.entries.last, 1, loop: true),
      same(group.entries.last),
    );
    expect(library.workFor(a.last)?.description, '整季简介');
  });
}
