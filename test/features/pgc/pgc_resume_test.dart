import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/pgc/application/pgc_controller.dart';
import 'package:bilisail/features/pgc/data/local_pgc_resume_repository.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _first = PgcEpisodeId('1');
const _second = PgcEpisodeId('2');
const _extra = PgcEpisodeId('3');
final _season = PgcSeason(
  id: const PgcSeasonId('42'),
  title: '测试番剧',
  lastEpisodeId: _second,
  episodes: const [
    PgcEpisode(id: _first, title: '1', bvid: 'BV1ab411c7mD', cid: '11'),
    PgcEpisode(id: _second, title: '2', bvid: 'BV1cd411c7mD', cid: '22'),
    PgcEpisode(
      id: _extra,
      title: 'SP',
      bvid: 'BV1ef411c7mD',
      cid: '33',
      sectionTitle: '特别篇',
    ),
  ],
);

void main() {
  for (final (local, enabled, scope, expected) in [
    ('1', true, 'user:1', _first),
    ('3', true, 'user:1', _extra),
    (null, true, 'user:1', _second),
    ('999', true, 'user:1', _second),
    ('1', false, 'user:1', null),
    (null, true, 'guest', null),
    ('2', true, 'guest', _second),
  ]) {
    test('episode memory local=$local enabled=$enabled scope=$scope', () async {
      var reads = 0;
      final repository = LocalPgcResumeRepository(
        resumeEnabled: () async => enabled,
        latestEpisode: (actualScope, ids) async {
          reads++;
          expect(actualScope, scope);
          expect(ids, ['1', '2', '3']);
          return local;
        },
      );
      expect(
        await repository.resumeEpisode(
          _season,
          scope: scope,
          cancellation: RequestCancellation(),
        ),
        expected,
      );
      expect(reads, enabled ? 1 : 0);
    });
  }

  for (final action in ['cancel', 'disable']) {
    test('pending local memory respects $action', () async {
      var enabled = true;
      final pending = Completer<String?>();
      final cancellation = RequestCancellation();
      final repository = LocalPgcResumeRepository(
        resumeEnabled: () async => enabled,
        latestEpisode: (_, _) => pending.future,
      );
      final result = repository.resumeEpisode(
        _season,
        scope: 'user:1',
        cancellation: cancellation,
      );
      await _turn();
      if (action == 'cancel') cancellation.cancel();
      if (action == 'disable') enabled = false;
      pending.complete('1');
      expect(await result, isNull);
    });
  }

  test(
    'season entry waits for memory before publishing its first episode',
    () async {
      final pending = Completer<String?>();
      final harness = _Harness(latestEpisode: (_, _) => pending.future);
      addTearDown(harness.dispose);
      harness.listen();
      await _turn();
      expect(harness.state.loading, isTrue);
      expect(harness.state.selectedEpisode, isNull);
      pending.complete('3');
      await _turn();
      expect(harness.state.selectedEpisodeId, _extra);
      expect(harness.state.loading, isFalse);
      expect(harness.selections, [_extra]);
    },
  );

  for (final explicit in [_first, _extra]) {
    test('explicit episode $explicit bypasses season history', () async {
      var reads = 0;
      final harness = _Harness(
        locator: PgcLocator(
          seasonId: const PgcSeasonId('42'),
          episodeId: explicit,
        ),
        latestEpisode: (_, _) async {
          reads++;
          return '2';
        },
      );
      addTearDown(harness.dispose);
      harness.listen();
      await _turn();
      expect(harness.state.selectedEpisodeId, explicit);
      expect(reads, 0);
    });
  }

  test(
    'refresh preserves an episode selected while detail was pending',
    () async {
      final harness = _Harness(latestEpisode: (_, _) async => '1');
      addTearDown(harness.dispose);
      harness.listen();
      await _turn();
      final pending = Completer<PgcSeason>();
      harness.repository.pending = pending;
      final refreshed = harness.controller.load();
      expect(harness.controller.selectEpisode(_extra), isTrue);
      pending.complete(_season);
      await refreshed;
      expect(harness.state.selectedEpisodeId, _extra);
    },
  );

  test('explicit navigation cancels pending initial resume', () async {
    final pending = Completer<String?>();
    final harness = _Harness(latestEpisode: (_, _) => pending.future);
    addTearDown(harness.dispose);
    harness.listen();
    await _turn();
    final oldCancellation = harness.repository.cancellations.single;
    harness.controller.selectDeepLinkEpisode(_first);
    await _turn();
    pending.complete('3');
    await _turn();
    expect(oldCancellation.isCancelled, isTrue);
    expect(harness.state.selectedEpisodeId, _first);
    expect(harness.selections, everyElement(_first));
  });

  for (final boundary in ['scope', 'epoch', 'dispose']) {
    test('late episode memory is ignored after $boundary', () async {
      final pending = Completer<String?>();
      final harness = _Harness(latestEpisode: (_, _) => pending.future);
      if (boundary != 'dispose') addTearDown(harness.dispose);
      harness.listen();
      await _turn();
      if (boundary == 'scope') harness.repository.scope = 'user:2';
      if (boundary == 'epoch') harness.repository.epoch++;
      if (boundary == 'dispose') harness.dispose();
      pending.complete('3');
      await _turn();
      expect(harness.selections, isEmpty);
    });
  }

  test(
    'history failure keeps detail playable with an explicit warning',
    () async {
      final harness = _Harness(
        latestEpisode: (_, _) async => throw StateError('disk'),
      );
      addTearDown(harness.dispose);
      harness.listen();
      await _turn();
      expect(harness.state.selectedEpisodeId, _first);
      expect(harness.state.message, '观看记录读取失败，本次从首集播放');
    },
  );

  test(
    'unknown cloud episode falls back to the first playable episode',
    () async {
      final harness = _Harness(latestEpisode: (_, _) async => null);
      harness.repository.season = PgcSeason(
        id: _season.id,
        title: _season.title,
        episodes: _season.episodes,
        lastEpisodeId: const PgcEpisodeId('999'),
      );
      addTearDown(harness.dispose);
      harness.listen();
      await _turn();
      expect(harness.state.selectedEpisodeId, _first);
    },
  );
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

final class _Harness {
  _Harness({
    required Future<String?> Function(String, Iterable<String>) latestEpisode,
    this.locator = const PgcLocator(seasonId: PgcSeasonId('42')),
  }) {
    container = ProviderContainer(
      overrides: [
        pgcRepositoryProvider.overrideWithValue(repository),
        pgcResumeRepositoryProvider.overrideWithValue(
          LocalPgcResumeRepository(
            resumeEnabled: () async => true,
            latestEpisode: latestEpisode,
          ),
        ),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
  }
  final PgcLocator locator;
  final repository = _Repository();
  final auth = _Auth();
  late final ProviderContainer container;
  final selections = <PgcEpisodeId>[];
  PgcState get state => container.read(pgcControllerProvider(locator));
  PgcController get controller =>
      container.read(pgcControllerProvider(locator).notifier);
  void listen() => container.listen(pgcControllerProvider(locator), (_, next) {
    if (next.season == null) return;
    if (next.selectedEpisodeId case final id?) selections.add(id);
  });
  void dispose() {
    container.dispose();
    unawaited(auth.changesController.close());
  }
}

final class _Repository implements PgcRepository {
  String scope = 'user:1';
  int epoch = 1;
  PgcSeason season = _season;
  Completer<PgcSeason>? pending;
  final cancellations = <RequestCancellation>[];
  @override
  String get accountScope => scope;
  @override
  int get sessionEpoch => epoch;
  @override
  Future<PgcSeason> detail({
    PgcSeasonId? seasonId,
    PgcEpisodeId? episodeId,
    bool refresh = false,
    required RequestCancellation cancellation,
  }) async {
    cancellations.add(cancellation);
    return pending?.future ?? season;
  }
}

final class _Auth implements AuthRepository {
  final changesController = StreamController<AuthState>.broadcast();
  @override
  AuthState get current => const AuthState();
  @override
  Stream<AuthState> get changes => changesController.stream;
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
  @override
  void cancelSignIn() {}
}
