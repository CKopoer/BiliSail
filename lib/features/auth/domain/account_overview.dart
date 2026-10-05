import '../../../domain/request_cancellation.dart';

final class AccountOverview {
  const AccountOverview({
    this.level,
    this.currentExperience,
    this.levelExperience,
    this.nextExperience,
    this.following,
    this.followers,
    this.dynamics,
    this.vipLabel,
    this.coins,
  });
  final int? level,
      currentExperience,
      levelExperience,
      nextExperience,
      following,
      followers,
      dynamics;
  final String? vipLabel;
  final num? coins;
  double? get progress {
    if (level case final int value when value >= 6) return 1;
    final current = currentExperience,
        start = levelExperience,
        next = nextExperience;
    if (current == null || start == null || next == null || next <= start) {
      return null;
    }
    return ((current - start) / (next - start)).clamp(0, 1);
  }
}

abstract interface class AccountOverviewRepository {
  Future<AccountOverview> load(
    String mid, {
    required RequestCancellation cancellation,
  });
}
