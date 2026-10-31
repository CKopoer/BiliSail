import 'dart:async';

import 'package:bilisail/features/playback/application/casting_controller.dart';
import 'package:bilisail/features/playback/domain/casting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/casting_fakes.dart';

void main() {
  test(
    'successful handoff pauses local once and commands stay serialized',
    () async {
      final h = CastingHarness();
      addTearDown(h.dispose);
      await h.controller.search();
      expect(h.controller.devices.length, 2);
      await h.controller.connect(castDevice('a'));
      await h.controller.connect(castDevice('a'));
      expect(h.localPauses, 1);
      expect(h.devices.calls, ['set:a', 'play:a']);
      h.devices.pendingCommand = Completer<void>();
      final pause = h.controller.control(CastCommand.pause);
      await h.controller.control(CastCommand.play);
      expect(h.devices.calls, ['set:a', 'play:a', 'pause:a']);
      h.devices.pendingCommand!.complete();
      await pause;
      expect(h.controller.transport, CastingTransport.paused);
      h.devices.pendingCommand = null;
      await h.controller.control(CastCommand.play);
      await h.controller.control(CastCommand.stop);
      expect(h.controller.selected, isNull);
      expect(h.localPauses, 1);
    },
  );
  test(
    'device switch stops previous renderer before setting the new URL',
    () async {
      final h = CastingHarness();
      addTearDown(h.dispose);
      await h.controller.connect(castDevice('a'));
      h.devices.pendingCommand = Completer<void>();
      final switchDevice = h.controller.connect(castDevice('b'));
      await Future<void>.delayed(Duration.zero);
      expect(h.devices.calls, ['set:a', 'play:a', 'stop:a']);
      h.devices.pendingCommand!.complete();
      await switchDevice;
      expect(h.devices.calls, ['set:a', 'play:a', 'stop:a', 'set:b', 'play:b']);
      expect(h.media.calls, 2);
    },
  );
  test(
    'failed handoff is visible, does not pause local or replay commands',
    () async {
      final h = CastingHarness();
      addTearDown(h.dispose);
      h.devices.failCommand = CastCommand.play;
      await h.controller.connect(castDevice('a'));
      expect(h.localPauses, 0);
      expect(h.controller.selected, isNull);
      expect(h.controller.message, '设备操作失败');
      expect(h.devices.calls, ['set:a', 'play:a']);
    },
  );
  for (final reason in ['source', 'account', 'dispose']) {
    test(
      '$reason invalidation cancels pending URL and prevents remote/local changes',
      () async {
        final h = CastingHarness();
        h.media.pending = Completer<Uri>();
        final connecting = h.controller.connect(castDevice('a'));
        if (reason == 'dispose') {
          h.controller.dispose();
        } else if (reason == 'account') {
          h.lifetime!.cancel();
        } else {
          h.current = false;
          h.source.value++;
        }
        expect(h.media.token!.isCancelled, isTrue);
        h.media.pending!.complete(Uri.parse('https://cdn.example/late.mp4'));
        await connecting;
        expect(h.devices.calls, isEmpty);
        expect(h.localPauses, 0);
        expect(h.devices.disposed, isTrue);
        if (reason != 'dispose') h.controller.dispose();
        expect(h.untracked, isTrue);
        h.source.dispose();
      },
    );
  }
  test(
    'late successful Play cannot pause a replacement local source',
    () async {
      final h = CastingHarness();
      addTearDown(h.dispose);
      h.devices.pendingCommand = Completer<void>();
      final connecting = h.controller.connect(castDevice('a'));
      await Future<void>.delayed(Duration.zero);
      h.current = false;
      h.source.value++;
      h.devices.pendingCommand!.complete();
      await connecting;
      expect(h.localPauses, 0);
      expect(h.controller.selected, isNull);
    },
  );
  test(
    'search deduplicates and caps discovered devices while retaining controls',
    () async {
      final h = CastingHarness();
      addTearDown(h.dispose);
      h.devices.found = [
        for (var i = 0; i < 100; i++) castDevice('$i'),
        castDevice('1'),
      ];
      await h.controller.search();
      expect(h.controller.devices.length, 64);
      await h.controller.connect(castDevice('1'));
      await h.controller.search();
      expect(h.controller.selected?.id, '1');
      expect(h.devices.searchToken!.isCancelled, isTrue);
    },
  );
}
