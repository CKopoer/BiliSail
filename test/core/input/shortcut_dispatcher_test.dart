import 'package:bilisail/app/shortcut_coordinator.dart';
import 'package:bilisail/core/input/input_stroke.dart';
import 'package:bilisail/core/input/shortcut_dispatcher.dart';
import 'package:bilisail/domain/shortcut_command.dart';
import 'package:flutter_test/flutter_test.dart';

InputStroke stroke(
  String key,
  InputPhase phase, {
  String id = 'physical',
  bool synthetic = false,
}) => InputStroke(
  identity: id,
  device: InputDevice.keyboard,
  phase: phase,
  sequence: 1,
  chord: ShortcutChord.parse(key),
  synthesized: synthetic,
  elapsedMicros: 10,
  logicalKeyId: 0x27,
  physicalKeyId: 0x70034,
  viewId: 3,
);

void main() {
  test('diagnostics are bounded and redact editor chords', () {
    final input = ShortcutCoordinator();
    addTearDown(input.dispose);
    input.diagnosticsEnabled = true;
    for (var i = 0; i < 300; i++) {
      input.dispatch(
        stroke('Quote', InputPhase.down, id: '$i'),
        const ShortcutContext(editing: true),
      );
    }
    expect(input.diagnostics.length, 256);
    expect(input.diagnostics.every((trace) => trace.chord == null), isTrue);
    expect(
      input.diagnostics.every(
        (trace) =>
            trace.logicalKeyId == null &&
            trace.physicalKeyId == null &&
            trace.buttons == null,
      ),
      isTrue,
    );
    expect(input.diagnostics.last.result.reason, DispatchReason.editorReserved);
  });
  test('diagnostics include safe input identifiers and target generation', () {
    final input = ShortcutCoordinator();
    addTearDown(input.dispose);
    input.diagnosticsEnabled = true;
    final registration = input.register(
      owner: 'player',
      scope: CommandScope.playback,
      commands: {ShortcutAction.faster: (_) => CommandOutcome.completed},
      active: () => true,
    );
    final result = input.dispatch(
      stroke('Quote', InputPhase.down),
      const ShortcutContext(),
    );
    final trace = input.diagnostics.last;
    expect(trace.logicalKeyId, 0x27);
    expect(trace.physicalKeyId, 0x70034);
    expect(trace.elapsedMicros, 10);
    expect(trace.viewId, 3);
    expect(result.scope, CommandScope.playback);
    expect(result.ownerGeneration, registration.generation);
  });
  test(
    'source revision invalidates repeats without handing them to a new source',
    () {
      final input = ShortcutCoordinator();
      addTearDown(input.dispose);
      var generation = 1, calls = 0;
      input.register(
        owner: 'player',
        scope: CommandScope.playback,
        commands: {
          ShortcutAction.volumeUp: (_) {
            calls++;
            return CommandOutcome.completed;
          },
        },
        active: () => true,
        revision: () => generation,
      );
      input.dispatch(
        stroke('ArrowUp', InputPhase.down),
        const ShortcutContext(),
      );
      generation++;
      expect(
        input
            .dispatch(
              stroke('ArrowUp', InputPhase.repeat),
              const ShortcutContext(),
            )
            .claimed,
        isTrue,
      );
      expect(calls, 1);
    },
  );

  test('frozen owner, repeats, stale handles and release modifiers', () {
    final input = ShortcutCoordinator();
    addTearDown(input.dispose);
    final received = <InputPhase>[];
    var firstActive = true;
    final first = input.register(
      owner: 'first',
      scope: CommandScope.playback,
      commands: {
        ShortcutAction.seekForward: (event) {
          received.add(event.phase);
          return CommandOutcome.completed;
        },
      },
      active: () => firstActive,
    );
    expect(
      input
          .dispatch(
            stroke('ArrowRight', InputPhase.down),
            const ShortcutContext(),
          )
          .claimed,
      isTrue,
    );
    firstActive = false;
    first.dispose();
    var newCalls = 0;
    input.register(
      owner: 'second',
      scope: CommandScope.playback,
      commands: {
        ShortcutAction.seekForward: (_) {
          newCalls++;
          return CommandOutcome.completed;
        },
      },
      active: () => true,
    );
    first.dispose();
    input.dispatch(
      stroke('Shift+ArrowRight', InputPhase.up),
      const ShortcutContext(),
    );
    expect(received, [InputPhase.down]);
    expect(newCalls, 0);
    input.dispatch(
      stroke('ArrowRight', InputPhase.repeat),
      const ShortcutContext(),
    );
    expect(newCalls, 0);
    input.dispatch(
      stroke('ArrowRight', InputPhase.down),
      const ShortcutContext(),
    );
    expect(newCalls, 1);
  });
  test('editor exceptions, modal protection and exact modifiers', () {
    final input = ShortcutCoordinator();
    addTearDown(input.dispose);
    var closes = 0;
    input.register(
      owner: 'workspace',
      scope: CommandScope.workspace,
      commands: {
        ShortcutAction.closeTab: (_) {
          closes++;
          return CommandOutcome.completed;
        },
      },
      active: () => true,
    );
    expect(
      input
          .dispatch(
            stroke('Ctrl+W', InputPhase.down),
            const ShortcutContext(editing: true),
          )
          .claimed,
      isTrue,
    );
    input.dispatch(
      stroke('W', InputPhase.up),
      const ShortcutContext(editing: true),
    );
    expect(
      closes,
      2,
    ); // release belongs to the chosen target; adapter ignores it
    expect(
      input
          .dispatch(
            stroke('Ctrl+W', InputPhase.down),
            const ShortcutContext(modal: true),
          )
          .claimed,
      isFalse,
    );
    expect(
      input
          .dispatch(
            stroke('Ctrl+W', InputPhase.down),
            const ShortcutContext(activeWindow: false),
          )
          .claimed,
      isFalse,
    );
    expect(
      input
          .dispatch(
            stroke('Shift+Quote', InputPhase.down),
            const ShortcutContext(),
          )
          .reason,
      DispatchReason.unbound,
    );
    expect(
      input
          .dispatch(
            stroke('Quote', InputPhase.down),
            const ShortcutContext(editing: true),
          )
          .reason,
      DispatchReason.editorReserved,
    );
  });
  test('duplicate registration never picks the last target', () {
    final input = ShortcutCoordinator();
    addTearDown(input.dispose);
    var calls = 0;
    for (final owner in ['a', 'b']) {
      input.register(
        owner: owner,
        scope: CommandScope.page,
        commands: {
          ShortcutAction.refresh: (_) {
            calls++;
            return CommandOutcome.completed;
          },
        },
        active: () => true,
      );
    }
    expect(
      input
          .dispatch(stroke('F5', InputPhase.down), const ShortcutContext())
          .reason,
      DispatchReason.duplicateTarget,
    );
    expect(calls, 0);
  });
  test('one-shot repeats and synthesized releases do not execute commands', () {
    final input = ShortcutCoordinator();
    addTearDown(input.dispose);
    var calls = 0, cancels = 0;
    input.register(
      owner: 'player',
      scope: CommandScope.playback,
      commands: {
        ShortcutAction.faster: (_) {
          calls++;
          return CommandOutcome.completed;
        },
      },
      active: () => true,
      onCancel: () => cancels++,
    );
    input.dispatch(
      stroke('Quote', InputPhase.down, synthetic: true),
      const ShortcutContext(),
    );
    expect(calls, 0);
    input.dispatch(stroke('Quote', InputPhase.down), const ShortcutContext());
    input.dispatch(stroke('Quote', InputPhase.repeat), const ShortcutContext());
    input.dispatch(
      stroke('Quote', InputPhase.up, synthetic: true),
      const ShortcutContext(),
    );
    expect(calls, 1);
    expect(cancels, 1);
  });
  test('recording keeps tails exclusive after recording scope exits', () {
    final input = ShortcutCoordinator();
    addTearDown(input.dispose);
    var captured = 0;
    input.recording = (_) {
      captured++;
      return CommandOutcome.completed;
    };
    expect(
      input
          .dispatch(
            stroke('Ctrl+W', InputPhase.down),
            const ShortcutContext(modal: true),
          )
          .claimed,
      isTrue,
    );
    input.recording = null;
    expect(
      input
          .dispatch(
            stroke('Ctrl+W', InputPhase.repeat),
            const ShortcutContext(),
          )
          .claimed,
      isTrue,
    );
    expect(
      input
          .dispatch(stroke('W', InputPhase.up), const ShortcutContext())
          .claimed,
      isTrue,
    );
    expect(captured, 2);
  });
}
