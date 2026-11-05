import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/profile/domain/profile_report.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';

class ProfileReportFake implements ProfileRepository, ProfileReportRepository {
  @override
  String accountScope = 'user:1';
  @override
  int sessionEpoch = 1;
  final reports = <(UserId, ProfileReport)>[];
  RequestCancellation? signal;
  Completer<void>? pending;
  Object? failure;

  @override
  Future<void> report(
    UserId id,
    ProfileReport report, {
    required RequestCancellation cancellation,
  }) async {
    reports.add((id, report));
    signal = cancellation;
    if (pending case final wait?) await wait.future;
    if (failure case final error?) throw error;
  }

  @override
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => UserProfile(id: id, name: '目标用户');
  @override
  Future<ProfileLiveRoom?> loadLiveRoom(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => null;
  @override
  Future<ProfilePage> loadEntries(
    UserId id,
    ProfileSection section, {
    required int page,
    String? cursor,
    String order = 'pubdate',
    String keyword = '',
    String? folderId,
    ProfileCollectionId? collection,
    required RequestCancellation cancellation,
  }) async => const ProfilePage(items: [], hasMore: false);
}
