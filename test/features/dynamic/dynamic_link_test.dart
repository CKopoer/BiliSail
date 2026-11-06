import 'package:bilisail/features/dynamic/domain/dynamic_link.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
