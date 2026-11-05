import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';

enum ProfileReportContent { avatar, nickname, signature }

enum ProfileReportReason {
  sexualContent,
  misinformation,
  prohibitedContent,
  personalAttack,
  gamblingFraud,
  illegalPromotion,
}

final class ProfileReport {
  ProfileReport({required Set<ProfileReportContent> contents, this.reason})
    : contents = Set.unmodifiable(contents) {
    if (contents.isEmpty) throw ArgumentError('Report content is required');
  }

  final Set<ProfileReportContent> contents;
  final ProfileReportReason? reason;
}

abstract interface class ProfileReportRepository {
  Future<void> report(
    UserId id,
    ProfileReport report, {
    required RequestCancellation cancellation,
  });
}
