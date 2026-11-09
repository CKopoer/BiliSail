import 'package:bilisail/features/dynamic/domain/dynamic_link.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final url in [
    'https://m.bilibili.com/topic-detail?topic_id=12&frommodule=H5',
    'https://www.bilibili.com/topic-detail/?topic_id=12',
    'https://m.bilibili.com/topic?topic_id=12',
    'bilibili://topic?topic_id=12',
    'bilibili://topic-detail/?topic_id=12',
    'bilibili://m.bilibili.com/topic-detail?topic_id=12&h5awaken=1',
  ]) {
    test('recognises registered topic destination: $url', () {
      expect(dynamicTopicId(Uri.parse(url)), '12');
    });
  }
  test(
    'topic identity wins over jump metadata and name fallback stays internal',
    () {
      final target = dynamicTopicDestination(
        id: '9007199254740993123',
        name: '话题',
        url: Uri.parse('https://m.bilibili.com/topic-detail?topic_id=99'),
      );
      expect(target?.host, 'www.bilibili.com');
      expect(target?.queryParameters['topic_id'], '9007199254740993123');
      final fallback = dynamicTopicDestination(
        name: '#C# 话题#',
        url: Uri.https('example.test', '/unknown'),
      );
      expect(fallback?.host, 'search.bilibili.com');
      expect(fallback?.queryParameters['keyword'], 'C# 话题');
      expect(
        dynamicTopicDestination(
          name: '有身份无链接',
          id: '12',
        )?.queryParameters['topic_id'],
        '12',
      );
      expect(
        dynamicTopicDestination(
          name: '',
          url: Uri.https('example.test', '/unknown'),
        ),
        isNull,
      );
    },
  );
  for (final url in [
    'https://m.bilibili.com.evil.test/topic-detail?topic_id=12',
    'https://user@m.bilibili.com/topic-detail?topic_id=12',
    'https://m.bilibili.com:8443/topic-detail?topic_id=12',
    'https://m.bilibili.com/topic-detail?topic_id=0',
    'https://m.bilibili.com/topic-detail?topic_id=1.2',
    'bilibili://topic-detail.evil.test?topic_id=12',
    'bilibili://user@topic?topic_id=12',
    'bilibili://topic:123?topic_id=12',
    'bilibili://m.bilibili.com/video?topic_id=12',
  ]) {
    test('rejects spoofed or malformed topic alias: $url', () {
      expect(dynamicTopicId(Uri.parse(url)), isNull);
    });
  }
  test(
    'name-only topics use the internal search query without decoding twice',
    () {
      final uri = Uri.https('search.bilibili.com', '/all', {
        'keyword': '话题 %20 & #',
      });
      expect(dynamicSearchQuery(uri), '话题 %20 & #');
      expect(
        dynamicSearchQuery(
          Uri.parse('https://search.bilibili.com.evil.test/all?keyword=a'),
        ),
        isNull,
      );
      expect(
        dynamicSearchQuery(
          Uri.parse('https://user@search.bilibili.com/all?keyword=a'),
        ),
        isNull,
      );
      expect(
        dynamicSearchQuery(
          Uri.parse('https://search.bilibili.com/all?keyword='),
        ),
        isNull,
      );
    },
  );
  test('topic links preserve decimal identity and reject spoofed or malformed destinations', () {
    const id = '9007199254740993123';
    expect(
      dynamicTopicId(
        Uri.parse(
          'https://www.bilibili.com/v/topic/detail/?topic_id=$id&from=dynamic',
        ),
      ),
      id,
    );
    expect(
      dynamicTopicId(
        Uri.parse('https://m.bilibili.com/v/topic/detail?topic_id=12'),
      ),
      '12',
    );
    for (final url in [
      'https://www.bilibili.com.evil.test/v/topic/detail?topic_id=12',
      'https://user@www.bilibili.com/v/topic/detail?topic_id=12',
      'http://www.bilibili.com/v/topic/detail?topic_id=12',
      'https://www.bilibili.com:8443/v/topic/detail?topic_id=12',
      'https://www.bilibili.com/v/topic/detail?topic_id=0',
      'https://www.bilibili.com/v/topic/detail?topic_id=1.5',
      'https://www.bilibili.com/v/topic/detail',
    ]) {
      expect(dynamicTopicId(Uri.parse(url)), isNull);
    }
  });
  test('video and PGC cards use explicit content identities', () {
    expect(
      dynamicVideo(
        Uri.parse('https://www.bilibili.com/video/BV1234567890?from=dynamic'),
      )?.value,
      'BV1234567890',
    );
    expect(
      dynamicPgcRoute(Uri.parse('https://www.bilibili.com/bangumi/play/ep123')),
      '/pgc/episode/123',
    );
    expect(
      dynamicPgcRoute(
        Uri.parse('https://www.bilibili.com/bangumi/play/ss456/'),
      ),
      '/pgc/season/456',
    );
    for (final url in [
      'https://www.bilibili.com.evil.test/bangumi/play/ep123',
      'https://user@www.bilibili.com/bangumi/play/ep123',
      'https://www.bilibili.com:8443/bangumi/play/ep123',
      'https://www.bilibili.com/bangumi/play/ep0',
    ]) {
      expect(dynamicPgcRoute(Uri.parse(url)), isNull);
      expect(dynamicVideo(Uri.parse(url)), isNull);
    }
  });
  test(
    'public live links retain decimal IDs and ignore tracking parameters',
    () {
      const id = '900719925474099312345';
      expect(
        dynamicLiveRoom(
          Uri.parse('https://live.bilibili.com/$id?from=dynamic'),
        ),
        const RoomId(id),
      );
      expect(
        dynamicLiveRoom(Uri.parse('https://live.bilibili.com/12/')),
        const RoomId('12'),
      );
    },
  );
  for (final url in [
    'https://t.bilibili.com/12',
    'https://live.bilibili.com.evil.test/12',
    'https://live.bilibili.com:8443/12',
    'https://user@live.bilibili.com/12',
    'http://live.bilibili.com/12',
    'https://live.bilibili.com/',
    'https://live.bilibili.com/0',
    'https://live.bilibili.com/-1',
    'https://live.bilibili.com/12.0',
    'https://live.bilibili.com/12/34',
    'https://live.bilibili.com/blanc/12',
  ]) {
    test('unsupported link stays outside live navigation: $url', () {
      expect(dynamicLiveRoom(Uri.parse(url)), isNull);
    });
  }
}
