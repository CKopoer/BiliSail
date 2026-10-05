import 'package:bili_lite/domain/user.dart';
import 'package:bili_lite/domain/video.dart';
import 'package:bili_lite/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user IDs only accept positive decimal identifiers', () {
    for (final value in ['0', '-1', '1.0', '', ' 12', '01']) {
      expect(UserId.tryParse(value), isNull);
    }
    expect(
      UserId.tryParse('12345678901234567890'),
      const UserId('12345678901234567890'),
    );
  });
  testWidgets('missing author ID never opens a guessed profile', (
    tester,
  ) async {
    final users = <UserId>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 250,
            child: VideoCard(
              video: const VideoSummary(
                id: VideoId('BV1234567890'),
                title: '视频',
                coverUrl: '',
                author: '作者',
                duration: Duration.zero,
              ),
              onTap: () {},
              onOpenUser: users.add,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('作者'));
    expect(users, isEmpty);
  });
  testWidgets('author click opens user without opening video', (tester) async {
    final users = <UserId>[];
    var videos = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 250,
            child: VideoCard(
              video: const VideoSummary(
                id: VideoId('BV1234567890'),
                title: '视频',
                coverUrl: '',
                author: '作者',
                authorId: UserId('42'),
                duration: Duration.zero,
              ),
              onTap: () => videos++,
              onOpenUser: users.add,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('作者'));
    expect(users, [const UserId('42')]);
    expect(videos, 0);
  });
}
