import 'recommendation_source.dart';

/// One card in one response. Retained cards keep their original attribution.
final class RecommendationCard {
  const RecommendationCard({
    required this.source,
    required this.epoch,
    required this.id,
    required this.goto,
    required this.trackId,
    this.cid,
    this.clickTrackId,
    this.responsePosition,
    this.freshType,
    this.cardType,
    this.cardGoto,
    this.identityRevision = 0,
  });

  final RecommendationSource source;
  final int epoch, identityRevision;
  final String id, goto, trackId;
  final String? cid, cardType, cardGoto, clickTrackId;
  final int? responsePosition;
  final int? freshType;
}

enum RecommendationInteraction { exposure, click }

typedef RecommendationEvent = ({
  RecommendationCard card,
  RecommendationInteraction interaction,
  int position,
  int row,
  int column,
  int timestamp,
});
