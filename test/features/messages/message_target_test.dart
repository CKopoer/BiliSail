import 'package:bilisail/features/messages/domain/message_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
        'https://t.bilibili.com/123',
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
