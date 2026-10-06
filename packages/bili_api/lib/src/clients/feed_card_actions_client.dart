import '../api_client.dart';
import '../models.dart';

/// Web Cookie/CSRF writes: one attempt per explicit action.
final class FeedCardActionsClient {
  const FeedCardActionsClient(this.api);
  final BiliApiClient api;

  Future<void> removeWatchLater(
    String aid, {
    ApiRequestContext? context,
  }) async {
    _id(aid);
    await api.submitForm('/x/v2/history/toview/del', 'watch_later_remove', {
      'aid': aid,
    }, context: context);
  }

  Future<void> rejectRecommendation(
    ApiRecommendationFeedback feedback, {
    ApiRequestContext? context,
  }) => _submitFeedback(feedback, undo: false, context: context);

  Future<void> undoRecommendationFeedback(
    ApiRecommendationFeedback feedback, {
    ApiRequestContext? context,
  }) => _submitFeedback(feedback, undo: true, context: context);

  Future<void> _submitFeedback(
    ApiRecommendationFeedback feedback, {
    required bool undo,
    ApiRequestContext? context,
  }) async {
    _id(feedback.aid);
    if (feedback.goto != 'av' ||
        feedback.trackId.length > 4096 ||
        !RegExp(r'^\d+$').hasMatch(feedback.ownerMid)) {
      throw ArgumentError('Invalid recommendation feedback');
    }
    await api.submitForm(
      undo
          ? '/x/web-interface/feedback/dislike/cancel'
          : '/x/web-interface/feedback/dislike',
      undo ? 'recommendation_feedback_undo' : 'recommendation_reject',
      {
        'app_id': '100',
        'platform': '5',
        'from_spmid': '',
        'spmid': '333.1007.0.0',
        'goto': feedback.goto,
        'id': feedback.aid,
        'mid': feedback.ownerMid,
        'track_id': feedback.trackId,
        'feedback_page': '1',
        'reason_id': '1',
      },
      context: context,
    );
  }

  static void _id(String id) {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(id)) {
      throw ArgumentError('Invalid archive ID');
    }
  }
}
