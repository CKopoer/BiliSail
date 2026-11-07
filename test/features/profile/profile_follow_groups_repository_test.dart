import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/profile/data/api_profile_repository.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = UserId('7');
  for (final scope in ['guest', 'user:8', 'user:7']) {
    test('follow groups are scoped to their owner: $scope', () async {
      final paths = <String>[];
      final requests = ApiRequests();
      final api = BiliApiClient(
        sessionProvider: requests,
        transport: _Transport((uri) {
          paths.add(uri.path);
          return uri.path == '/x/relation/tags'
              ? [
                  {'tagid': -10, 'name': '特别关注'},
                  {'tagid': 1, 'name': '分组'},
                ]
              : [
                  {'mid': '9007199254740993123', 'uname': '分组用户'},
                ];
        }),
      );
      addTearDown(api.close);
      final repo = ApiProfileRepository(
        ProfileClient(api),
        requests,
        accountScope: () => scope,
      );
      if (scope == 'user:7') {
        final groups = await repo.loadFollowGroups(
          id,
          cancellation: RequestCancellation(),
        );
        expect(groups.map((group) => group.id), ['0', '-10', '1']);
        final page = await repo.loadFollowingGroup(
          id,
          '1',
          page: 1,
          cancellation: RequestCancellation(),
        );
        expect(page.items.single.userId, const UserId('9007199254740993123'));
        expect(page.items.single.title, '分组用户');
        expect(page.hasMore, false);
        expect(paths, ['/x/relation/tags', '/x/relation/tag']);
      } else {
        final denied = throwsA(
          isA<AppFailure>().having(
            (error) => error.kind,
            'kind',
            AppFailureKind.permission,
          ),
        );
        await expectLater(
          repo.loadFollowGroups(id, cancellation: RequestCancellation()),
          denied,
        );
        await expectLater(
          repo.loadFollowingGroup(
            id,
            '1',
            page: 1,
            cancellation: RequestCancellation(),
          ),
          denied,
        );
        await expectLater(
          repo.loadManagedFollowing(
            id,
            page: 1,
            blacklist: true,
            cancellation: RequestCancellation(),
          ),
          denied,
        );
        await expectLater(
          repo.loadManagedFollowing(
            id,
            page: 1,
            keyword: '查询',
            cancellation: RequestCancellation(),
          ),
          denied,
        );
        await expectLater(
          repo.editFollowGroup(
            id,
            FollowGroupEdit.create,
            name: '分组',
            cancellation: RequestCancellation(),
          ),
          denied,
        );
        await expectLater(
          repo.sortFollowGroups(id, [
            '1',
            '2',
          ], cancellation: RequestCancellation()),
          denied,
        );
        await expectLater(
          repo.setFollowingBlocked(
            id,
            const UserId('9'),
            true,
            cancellation: RequestCancellation(),
          ),
          denied,
        );
        expect(paths, isEmpty);
      }
    });
  }
}

final class _Transport implements ApiTransport {
  _Transport(this.data);
  final Object Function(Uri) data;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
    200,
    Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data(uri)}))),
    const {},
  );
}
