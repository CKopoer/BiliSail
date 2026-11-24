import 'package:bilisail/features/pgc/domain/pgc_playback_sequence.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:flutter_test/flutter_test.dart';

PgcEpisode _ep(String id, {String? section, bool available = true}) =>
    PgcEpisode(
      id: PgcEpisodeId(id),
      title: id,
      sectionTitle: section,
      bvid: 'BV1ab411c7mD',
      cid: id,
      available: available,
    );

void main() {
  test(
    'course playback crosses directory sections and stops at locked lessons',
    () {
      final lessons = [
        _ep('1', section: '基础'),
        _ep('2', section: '语法'),
        _ep('3', section: '语法', available: false),
      ];
      final course = PgcSeason(
        course: true,
        id: const PgcSeasonId('7'),
        title: '法语',
        episodes: lessons,
      );
      expect(adjacentPgcEpisode(course, lessons.first, 1), lessons[1]);
      expect(adjacentPgcEpisode(course, lessons[1], 1), isNull);
      expect(
        adjacentPgcEpisode(course, lessons.last, 1, loop: true),
        lessons.first,
      );
    },
  );

  test(
    'duplicate IDs retain first position within each raw/display section',
    () {
      final episodes = [
        _ep('1'),
        _ep('2'),
        _ep('3', section: 'SP'),
        _ep('1', section: 'SP'),
        _ep('4', section: 'SP'),
      ];
      final season = PgcSeason(
        id: const PgcSeasonId('42'),
        title: '重复分组',
        episodes: episodes,
      );
      expect(season.episode(const PgcEpisodeId('1')), episodes.first);
      expect(season.episodePosition(const PgcEpisodeId('1')), 0);
      expect(
        season.episodeGroupPosition(const PgcEpisodeId('1'), section: 'SP'),
        1,
      );
      expect(adjacentPgcEpisode(season, episodes[3], 1), episodes[4]);
      expect(adjacentPgcEpisode(season, episodes[3], -1), episodes[2]);
    },
  );

  test('season owns stable immutable groups and positions until refreshed', () {
    final episodes = [
      for (var i = 1; i <= 5000; i++)
        _ep('$i', section: i > 4000 ? 'SP' : null),
    ];
    final season = PgcSeason(
      id: const PgcSeasonId('42'),
      title: '长季',
      episodes: episodes,
    );
    final groups = season.episodeGroups;
    expect(groups['正片']!.length, 4000);
    expect(groups['SP']!.length, 1000);
    for (var i = 0; i < 100; i++) {
      expect(identical(season.episodeGroups, groups), isTrue);
      expect(season.episodePosition(const PgcEpisodeId('5000')), 4999);
      expect(season.episodeGroupPosition(const PgcEpisodeId('5000')), 999);
      expect(
        identical(season.episode(const PgcEpisodeId('5000')), episodes.last),
        isTrue,
      );
    }
    expect(() => groups['SP']!.clear(), throwsUnsupportedError);
    expect(() => groups.clear(), throwsUnsupportedError);
    episodes.clear();
    expect(season.episodes.length, 5000);
    final fresh = PgcSeason(
      id: season.id,
      title: season.title,
      episodes: [_ep('5000')],
    );
    expect(fresh.episodePosition(const PgcEpisodeId('5000')), 0);
    expect(fresh.episodeGroups.keys, ['正片']);
    expect(identical(fresh.episodeGroups, groups), isFalse);
  });

  test('sequence retains raw SP grouping, permission stop and direction', () {
    final episodes = [
      _ep('1'),
      _ep('2', available: false),
      _ep('3'),
      _ep('4', section: ' SP '),
      _ep('5', section: 'SP'),
      _ep('6', section: ' SP '),
      _ep('7', section: ''),
      _ep('8', section: ''),
    ];
    final season = PgcSeason(
      id: const PgcSeasonId('42'),
      title: '混合分组',
      episodes: episodes,
    );
    expect(season.episodeGroups.keys, ['正片', 'SP']);
    expect(adjacentPgcEpisode(season, episodes[0], 1), isNull);
    expect(adjacentPgcEpisode(season, episodes[2], 1), isNull);
    expect(adjacentPgcEpisode(season, episodes[3], 1), episodes[5]);
    expect(adjacentPgcEpisode(season, episodes[5], -1), episodes[3]);
    expect(adjacentPgcEpisode(season, episodes[6], 1), episodes[7]);
    expect(adjacentPgcEpisode(season, episodes[0], 2), isNull);
    expect(season.episodePosition(const PgcEpisodeId('999')), -1);
  });
}
