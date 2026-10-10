import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/video/data/api_video_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'repository carries all staff credits into the domain without guessing IDs',
    () async {
      final requests = ApiRequests();
      final api = BiliApiClient(
        transport: _Transport(),
        sessionProvider: requests,
      );
      addTearDown(api.close);
      final detail = await ApiVideoRepository(api, requests).loadDetail(
        const VideoId('BV1234567890'),
        cancellation: RequestCancellation(),
      );
      expect(detail.authorMid, '42');
      expect(detail.staff, hasLength(2));
      final member = detail.staff.first;
      expect(member.id, const UserId('9007199254740993'));
      expect(member.name, '合作成员');
      expect(member.title, '赞助商');
      expect(member.avatarUrl?.scheme, 'https');
      expect(member.highlightedRole, true);
      expect(member.nicknameColor, '#FB7299');
      expect(detail.staff.last.id, isNull);
      expect(detail.staff.last.name, '合作成员');
      expect(() => detail.staff.clear(), throwsUnsupportedError);
    },
  );
}

final class _Transport implements ApiTransport {
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
    200,
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'code': 0,
          'data': {
            'aid': 1,
            'bvid': 'BV1234567890',
            'title': '合作视频',
            'owner': {'mid': 42, 'name': 'UP'},
            'pages': [
              {'cid': 1, 'page': 1, 'part': 'P1'},
            ],
            'staff': [
              {
                'mid': '9007199254740993',
                'name': '合作成员',
                'title': '赞助商',
                'face': 'http://i0.hdslb.com/staff.jpg',
                'label_style': 1,
                'vip': {'nickname_color': '#FB7299'},
              },
              {'name': '合作成员', 'title': '参演'},
            ],
          },
        }),
      ),
    ),
    const {},
  );
}
