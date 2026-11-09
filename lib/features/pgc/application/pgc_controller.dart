import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/pgc_repository.dart';
import '../domain/pgc_resume_repository.dart';

final pgcRepositoryProvider = Provider<PgcRepository>(
  (ref) => throw UnimplementedError('PgcRepository must be provided by app'),
);

final pgcResumeRepositoryProvider = Provider<PgcResumeRepository?>(
  (ref) => null,
);

final pgcControllerProvider = NotifierProvider.autoDispose
    .family<PgcController, PgcState, PgcLocator>(PgcController.new);

final class PgcState {
  const PgcState({
    this.season,
    this.selectedEpisodeId,
    this.loading = false,
    this.message,
  });
  final PgcSeason? season;
  final PgcEpisodeId? selectedEpisodeId;
  final bool loading;
  final String? message;

  PgcEpisode? get selectedEpisode {
    final current = season;
    if (current == null || current.episodes.isEmpty) return null;
    return current.episode(selectedEpisodeId) ??
        current.firstPlayableEpisode ??
        current.episodes.first;
  }
}

final class PgcController extends Notifier<PgcState> {
  PgcController(this.locator);
  final PgcLocator locator;
  RequestCancellation? _active;
  int _generation = 0;
  bool _registeredDispose = false;

  @override
  PgcState build() {
    ref.watch(authControllerProvider);
    _active?.cancel();
    final generation = ++_generation;
    if (!_registeredDispose) {
      _registeredDispose = true;
      ref.onDispose(() {
        ++_generation;
        _active?.cancel();
      });
    }
    Future<void>.microtask(() {
      if (ref.mounted && generation == _generation) {
        unawaited(load(refresh: false));
      }
    });
    return PgcState(selectedEpisodeId: locator.episodeId, loading: true);
  }

  bool _isCurrent(
    int generation,
    RequestCancellation cancellation,
    PgcRepository repository,
    String scope,
    int epoch,
  ) =>
      ref.mounted &&
      generation == _generation &&
      !cancellation.isCancelled &&
      repository.accountScope == scope &&
      repository.sessionEpoch == epoch;

  Future<void> load({
    PgcEpisodeId? requestedEpisode,
    bool refresh = true,
  }) async {
    _active?.cancel();
    final cancellation = RequestCancellation();
    _active = cancellation;
    final generation = ++_generation;
    final repository = ref.read(pgcRepositoryProvider);
    final scope = repository.accountScope;
    final epoch = repository.sessionEpoch;
    final previous = state;
    state = PgcState(
      season: previous.season,
      selectedEpisodeId: requestedEpisode ?? previous.selectedEpisodeId,
      loading: true,
    );
    try {
      final season = await repository.detail(
        seasonId: locator.seasonId,
        episodeId: requestedEpisode ?? locator.episodeId,
        refresh: refresh,
        cancellation: cancellation,
      );
      if (!_isCurrent(generation, cancellation, repository, scope, epoch)) {
        return;
      }
      var preferred = requestedEpisode ?? previous.selectedEpisodeId;
      String? resumeMessage;
      if (preferred == null) {
        try {
          preferred = await ref
              .read(pgcResumeRepositoryProvider)
              ?.resumeEpisode(season, scope: scope, cancellation: cancellation)
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          resumeMessage = '观看记录读取失败，本次从首集播放';
        }
      }
      if (!_isCurrent(generation, cancellation, repository, scope, epoch)) {
        return;
      }
      // A selection made while refresh/history was pending wins over its result.
      preferred = state.selectedEpisodeId ?? preferred;
      final selected =
          season.episode(preferred) ??
          season.firstPlayableEpisode ??
          season.episodes.firstOrNull;
      state = PgcState(
        season: season,
        selectedEpisodeId: selected?.id,
        message: resumeMessage,
      );
    } on AppFailure catch (error) {
      if (!_isCurrent(generation, cancellation, repository, scope, epoch)) {
        return;
      }
      state = PgcState(
        season: previous.season,
        selectedEpisodeId: previous.selectedEpisodeId,
        message: error.kind == AppFailureKind.cancelled ? null : error.message,
      );
    } catch (_) {
      if (!_isCurrent(generation, cancellation, repository, scope, epoch)) {
        return;
      }
      state = PgcState(
        season: previous.season,
        selectedEpisodeId: previous.selectedEpisodeId,
        message: '影视详情暂时无法加载，请重试',
      );
    }
  }

  bool selectEpisode(PgcEpisodeId id) {
    if (state.selectedEpisodeId == id) return false;
    final season = state.season;
    if (season == null || season.episode(id) == null) return false;
    state = PgcState(season: season, selectedEpisodeId: id);
    return true;
  }

  void selectDeepLinkEpisode(PgcEpisodeId id) {
    if (!selectEpisode(id) && state.selectedEpisodeId != id) {
      unawaited(load(requestedEpisode: id));
    }
  }
}
