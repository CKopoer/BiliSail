import 'dart:async';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:bilisail/core/presentation/window_input_focus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('bilisail/application_window');

  testWidgets('interactive focus reads still fail after two seconds', (
    tester,
  ) async {
    final focus = WindowInputFocus();
    final reply = Completer<Map<String, Object?>>();
    var reads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      _,
    ) {
      reads++;
      return reply.future;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final result = expectLater(
      focus.synchronizeNativeFocus(),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 2));
    await result;
    reply.complete({'viewId': 100, 'revision': 1});
    await tester.pump();
    expect(reads, 1);
    expect(focus.observed, isFalse);
    expect(focus.viewId, isNull);
  });

  for (final focused in [true, false]) {
    testWidgets('native snapshot restores missing focus: $focused', (
      tester,
    ) async {
      final focus = WindowInputFocus();
      void changed() {}
      focus.addListener(changed);
      addTearDown(() => focus.removeListener(changed));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => {'viewId': focused ? 100 : null, 'revision': 1},
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      await focus.synchronizeNativeFocus();
      expect(focus.observed, isTrue);
      expect(focus.viewId, focused ? 100 : null);
      expect(focus.source, 'native');
    });
  }

  testWidgets('late snapshot cannot overwrite a newer focused view', (
    tester,
  ) async {
    final focus = WindowInputFocus();
    void changed() {}
    focus.addListener(changed);
    addTearDown(() => focus.removeListener(changed));
    final reply = Completer<Map<String, Object?>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) => reply.future,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    final pending = focus.synchronizeNativeFocus();
    focus.didChangeViewFocus(
      const ViewFocusEvent(
        viewId: 200,
        state: ViewFocusState.focused,
        direction: ViewFocusDirection.undefined,
      ),
    );
    reply.complete({'viewId': 100, 'revision': 1});
    await pending;
    expect(focus.viewId, 200);
    expect(focus.source, 'flutter');
  });

  testWidgets('newer snapshot wins when replies arrive out of order', (
    tester,
  ) async {
    final focus = WindowInputFocus();
    void changed() {}
    focus.addListener(changed);
    addTearDown(() => focus.removeListener(changed));
    final first = Completer<Map<String, Object?>>();
    var reads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) => ++reads == 1
          ? first.future
          : Future.value({'viewId': 200, 'revision': 2}),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    final pending = focus.synchronizeNativeFocus();
    await focus.synchronizeNativeFocus();
    first.complete({'viewId': 100, 'revision': 1});
    await pending;
    expect(focus.viewId, 200);
  });

  testWidgets('blur during a read rechecks keyWindow without reviving it', (
    tester,
  ) async {
    final focus = WindowInputFocus();
    void changed() {}
    focus.addListener(changed);
    addTearDown(() => focus.removeListener(changed));
    final first = Completer<Map<String, Object?>>();
    var reads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) => ++reads == 1
          ? first.future
          : Future.value({'viewId': null, 'revision': 2}),
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    final pending = focus.synchronizeNativeFocus();
    focus.didChangeViewFocus(
      const ViewFocusEvent(
        viewId: 100,
        state: ViewFocusState.unfocused,
        direction: ViewFocusDirection.undefined,
      ),
    );
    first.complete({'viewId': 100, 'revision': 1});
    await pending;
    expect(reads, 2);
    expect(focus.viewId, isNull);
  });

  testWidgets('unmount invalidates an outstanding native snapshot', (
    tester,
  ) async {
    final focus = WindowInputFocus();
    void changed() {}
    focus.addListener(changed);
    final reply = Completer<Map<String, Object?>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) => reply.future,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    final pending = focus.synchronizeNativeFocus();
    focus.removeListener(changed);
    reply.complete({'viewId': 100, 'revision': 1});
    await pending;
    expect(focus.viewId, isNull);
    expect(focus.observed, isFalse);
  });
}
