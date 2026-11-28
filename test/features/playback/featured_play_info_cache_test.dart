import 'dart:async';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/data/featured_play_info_cache.dart';
import 'package:flutter_test/flutter_test.dart';

ApiPlayInfo _info({int? deadline}) => ApiPlayInfo(
  duration: const Duration(seconds: 60),
  acceptQuality: const [80],
  dashVideo: [
    ApiMediaTrack(
      id: 80,
      url: Uri.https('example.test', '/video', {
        'deadline': ?deadline?.toString(),
      }),
      backupUrls: const [],
      bandwidth: 10,
      mimeType: 'video/mp4',
      codecs: 'avc1',
    ),
  ],
  dashAudio: const [],
);

void main() {
  const id = VideoId('BV17x411w7KC');
  late ApiRequests requests;
  late FeaturedPlayInfoCache cache;
  late DateTime now;
  final reads = <RequestCancellation>[];
  final results = <Completer<ApiPlayInfo>>[];
  setUp(() {
    requests = ApiRequests();
    now = DateTime.utc(2026, 11, 28);
    reads.clear();
    results.clear();
    cache = FeaturedPlayInfoCache(requests, (video, cid, token) {
      reads.add(token);
      final result = Completer<ApiPlayInfo>();
      results.add(result);
      return result.future;
    }, now: () => now);
  });

  test('selection adopts the in-flight playurl; releasing both preview leases does not cancel it', () async {
    final release = cache.prepare(id, '1');
    final second = cache.prepare(id, '1');
    final pending = cache.take(id, '1', ApiCancellation());
    expect(pending, isNotNull);
    release();
    second();
    expect(reads, hasLength(1));
    expect(reads.single.isCancelled, isFalse);
    final info = _info();
    results.single.complete(info);
    expect(await pending, same(info));
    expect(cache.take(id, '1', null), isNull);
  });

  test(
    'an immediate reverse swipe can use the same playurl once on a new visit',
    () async {
      final current = cache.prepare(id, '1');
      final info = _info();
      results.single.complete(info);
      expect(await cache.take(id, '1', null), same(info));
      expect(cache.take(id, '1', null), isNull);
      final previous = cache.prepare(id, '1', neighbor: true);
      current();
      final revisited = cache.prepare(id, '1');
      previous();
      expect(await cache.take(id, '1', null), same(info));
      expect(reads, hasLength(1));
      revisited();
      expect(reads.single.isCancelled, isTrue);
    },
  );

  test('leaving the view, interrupting a selected request, and switching accounts discard responses', () async {
    cache.prepare(id, '1')();
    expect(reads.first.isCancelled, isTrue);
    expect(cache.take(id, '1', null), isNull);
    cache.prepare(id, '2');
    final owner = ApiCancellation();
    final pending = cache.take(id, '2', owner);
    owner.cancel();
    expect(reads.last.isCancelled, isTrue);
    results.last.complete(_info());
    expect(await pending, isNull);
    cache.prepare(id, '3');
    results.last.complete(_info());
    await Future<void>.delayed(Duration.zero);
    requests.advanceSession();
    expect(cache.take(id, '3', null), isNull);
  });

  test('stale, expired, failed and displaced requests fall back to foreground resolution', () async {
    cache.prepare(id, '1');
    results.last.complete(_info());
    now = now.add(const Duration(minutes: 1));
    expect(await cache.take(id, '1', null), isNull);
    cache.prepare(id, '2');
    results.last.complete(
      _info(deadline: now.millisecondsSinceEpoch ~/ 1000 + 3),
    );
    expect(await cache.take(id, '2', null), isNull);
    cache.prepare(id, '3');
    results.last.completeError(
      const AppFailure(AppFailureKind.network, 'offline'),
    );
    expect(await cache.take(id, '3', null), isNull);
    for (var i = 0; i < 7; i++) {
      cache.prepare(id, 'next-$i');
    }
    expect(cache.take(id, 'next-0', null), isNull);
    expect(reads[3].isCancelled, isTrue);
    requests.advanceSession();
  });
}
