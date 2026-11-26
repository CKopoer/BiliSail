import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/recommendation_card.dart';
import '../../../domain/request_cancellation.dart';
import '../../settings/application/settings_controller.dart';
import '../domain/feed_repository.dart';
import 'app_recommendation_identity.dart';
import 'feed_controller.dart';

final recommendationReporterProvider = Provider<RecommendationReporter?>((ref) {
  // Wait for saved preferences before sending any reports.
  if (!ref.watch(
    settingsControllerProvider.select(
      (settings) =>
          settings.asData?.value.recommendations.reportInteractions ?? false,
    ),
  )) {
    return null;
  }
  final repository = ref.watch(feedRepositoryProvider);
  if (repository is! RecommendationReportingRepository) return null;
  final key = ref.watch(recommendationQueryKeyProvider);
  final epoch = ref.watch(sessionEpochProvider);
  final reporter = RecommendationReporter(
    repository as RecommendationReportingRepository,
    accepts: (card) =>
        card.source == key.source &&
        card.identityRevision == key.identity &&
        card.epoch == epoch(),
  );
  ref.onDispose(reporter.dispose);
  return reporter;
});

final class RecommendationReporter {
  RecommendationReporter(this.repository, {required this.accepts});
  final RecommendationReportingRepository repository;
  final bool Function(RecommendationCard) accepts;
  // Weak keys follow card lifetime, including retained refreshes and remounts.
  final _seen = Expando<bool>();
  final _pending = <RecommendationEvent>[];
  Timer? _timer;
  RequestCancellation? _sending;
  bool _disposed = false;

  bool seen(RecommendationCard card) => _seen[card] == true;

  void record(
    RecommendationCard card,
    RecommendationInteraction interaction, {
    required int position,
    required int row,
    required int column,
  }) {
    if (_disposed || !accepts(card)) return;
    if (interaction == RecommendationInteraction.exposure) {
      if (seen(card)) return;
      _seen[card] = true;
    }
    if (_pending.length >= 32) {
      if (interaction == RecommendationInteraction.exposure) return;
      _pending.removeAt(0);
    }
    _pending.add((
      card: card,
      interaction: interaction,
      position: position,
      row: row,
      column: column,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    _schedule();
  }

  void _schedule() {
    if (_disposed || _sending != null || _pending.isEmpty) return;
    _timer ??= Timer(const Duration(milliseconds: 300), _flush);
  }

  Future<void> _flush() async {
    _timer = null;
    final batch = _pending.where((e) => accepts(e.card)).toList();
    _pending.clear();
    if (batch.isEmpty) return;
    final signal = _sending = RequestCancellation();
    try {
      await repository.reportRecommendations(batch, cancellation: signal);
    } catch (_) {
      // Delivery is best effort. The batch has already left the queue.
    } finally {
      _sending = null;
      _schedule();
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _pending.clear();
    _sending?.cancel();
  }
}
