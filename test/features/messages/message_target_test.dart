import 'package:bilisail/features/messages/domain/message_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('message links preserve only validated content navigation parameters', () {
    expect(
      messageWorkspaceLocation(
        Uri.parse(
          'https://www.bilibili.com/video/BV17x411w7KC?cid=9007199254740993&p=2&comment_root_id=100&comment_secondary_id=101&start_progress=12500&from=message',
        ),
      ),
      '/video/BV17x411w7KC?cid=9007199254740993&p=2&comment_root_id=100&comment_secondary_id=101&start_progress=12500',
    );
    expect(
      messageWorkspaceLocation(
        Uri.parse(
          'https://www.bilibili.com/video/BV17x411w7KC?dm_progress=12000',
        ),
      ),
      '/video/BV17x411w7KC?start_progress=9000',
    );
    expect(
      messageWorkspaceLocation(
        Uri.parse(
          'https://www.bilibili.com/video/BV17x411w7KC?t=12.5#reply9007199254740993',
        ),
      ),
      '/video/BV17x411w7KC?comment_root_id=9007199254740993&start_progress=12500',
    );
    expect(
      messageWorkspaceLocation(
        Uri.parse(
          'https://www.bilibili.com/bangumi/play/ep123?comment_root_id=100&t=9',
        ),
      ),
      '/pgc/episode/123?comment_root_id=100&start_progress=9000',
    );
    for (final query in [
      'cid=-1&p=0&comment_root_id=1e9&comment_secondary_id=2&t=NaN',
      'start_progress=-1',
      'start_progress=9999999999999999999',
      'p=10001&comment_root_id=0&t=Infinity',
    ]) {
      expect(
        messageWorkspaceLocation(
          Uri.parse('https://www.bilibili.com/video/BV17x411w7KC?$query'),
        ),
        '/video/BV17x411w7KC',
        reason: query,
      );
    }
  });
  test('supported message cards use existing workspace destinations', () {
    const cases = {
      'https://www.bilibili.com/video/BV17x411w7KC/?from=message':
          '/video/BV17x411w7KC',
      'https://bilibili.com/video/BV17x411w7KC': '/video/BV17x411w7KC',
      'https://www.bilibili.com/bangumi/play/ep123#reply': '/pgc/episode/123',
      'https://www.bilibili.com/bangumi/play/ss456': '/pgc/season/456',
      'https://live.bilibili.com/123': '/live/123',
      'https://space.bilibili.com/9007199254740993/': '/user/9007199254740993',
    };
    for (final entry in cases.entries) {
      expect(messageWorkspaceLocation(Uri.parse(entry.key)), entry.value);
    }
  });

  test('dynamic notifications use detail routes and retain comment IDs', () {
    const cases = {
      'https://t.bilibili.com/9007199254740993123':
          '/dynamic/9007199254740993123',
      'https://www.bilibili.com/opus/9007199254740993123?comment_root_id=10&comment_secondary_id=11&from=message': '/dynamic/9007199254740993123?comment_root_id=10&comment_secondary_id=11',
      'https://m.bilibili.com/h5/dynamic/9007199254740993123/?p=2&t=3#reply20':
          '/dynamic/9007199254740993123?comment_root_id=20',
      'https://t.bilibili.com/456?type=2&root=10':
          '/dynamic/resource/456?comment_root_id=10',
    };
    for (final entry in cases.entries) {
      expect(messageWorkspaceLocation(Uri.parse(entry.key)), entry.value);
    }
  });

  test(
    'unsupported or unsafe message targets cannot select a workspace page',
    () {
      for (final target in [
        'http://www.bilibili.com/video/BV17x411w7KC',
        'https://www.bilibili.com:444/video/BV17x411w7KC',
        'https://user@www.bilibili.com/video/BV17x411w7KC',
        'https://www.bilibili.com.evil.example/video/BV17x411w7KC',
        'https://www.bilibili.com/video/BV17x411w7KC/extra',
        'https://www.bilibili.com/video/not-a-video',
        'https://www.bilibili.com/bangumi/play/ep0',
        'https://www.bilibili.com/read/cv123',
        'https://t.bilibili.com/123/extra',
        'https://t.bilibili.com.evil.example/123',
        'https://t.bilibili.com/vote/h5/index?vote_id=123',
        'https://www.bilibili.com/opus/0',
        'https://live.bilibili.com/0',
        'https://space.bilibili.com/-1',
        'javascript:alert(1)',
      ]) {
        expect(
          messageWorkspaceLocation(Uri.parse(target)),
          isNull,
          reason: target,
        );
      }
    },
  );
}
