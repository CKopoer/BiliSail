import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/favorite_folder_repository.dart';

final class ApiFavoriteFolderRepository implements FavoriteFolderRepository {
  ApiFavoriteFolderRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
    // ignore: prefer_initializing_formals
  }) : _accountScope = accountScope;
  final FavoriteFolderClient client;
  final ApiRequests requests;
  final String Function() _accountScope;
  @override
  String get accountScope => _accountScope();
  @override
  int get sessionEpoch => requests.sessionEpoch;

  void _check(FavoriteFolderTarget target) {
    if (!target.scope.startsWith('user:')) {
      throw const AppFailure(AppFailureKind.authentication, '请先登录');
    }
    if (target.scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
  }

  @override
  Future<FavoriteFolderInfo> load(
    FavoriteFolderTarget target,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    _check(target);
    final info = await client.load(target.id, context: context);
    _check(target);
    if (target.scope != 'user:${info.ownerMid}') {
      throw const AppFailure(AppFailureKind.permission, '只能修改自己创建的收藏夹');
    }
    return FavoriteFolderInfo(
      id: info.id,
      title: info.title,
      intro: info.intro,
      isPrivate: info.isPrivate,
    );
  }, cancellation: cancellation);

  @override
  Future<void> update(
    FavoriteFolderTarget target,
    FavoriteFolderEdit edit,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    _check(target);
    try {
      await client.update(
        target.id,
        title: edit.title,
        intro: edit.intro,
        isPrivate: edit.isPrivate,
        context: context,
      );
    } on ApiFailure catch (error) {
      if (context.cancellation?.isCancelled == true) rethrow;
      if (const {
        ApiFailureCategory.network,
        ApiFailureCategory.timeout,
        ApiFailureCategory.http,
        ApiFailureCategory.protocol,
      }.contains(error.category)) {
        throw const FavoriteFolderWriteUncertain();
      }
      if (error.category == ApiFailureCategory.permission) {
        throw const AppFailure(AppFailureKind.permission, '当前账号无法修改这个收藏夹');
      }
      rethrow;
    }
    _check(target);
  }, cancellation: cancellation);
}
