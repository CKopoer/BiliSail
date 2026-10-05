import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/account_overview.dart';

class ApiAccountOverviewRepository implements AccountOverviewRepository {
  const ApiAccountOverviewRepository(this.client, this.requests);
  final AccountClient client;
  final ApiRequests requests;
  @override
  Future<AccountOverview> load(
    String mid, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final data = await client.overview(mid, context: context);
    return AccountOverview(
      level: data.level,
      currentExperience: data.currentExperience,
      levelExperience: data.levelExperience,
      nextExperience: data.nextExperience,
      following: data.following,
      followers: data.followers,
      dynamics: data.dynamics,
      vipLabel: data.vipLabel,
      coins: data.coins,
    );
  }, cancellation: cancellation);
}
