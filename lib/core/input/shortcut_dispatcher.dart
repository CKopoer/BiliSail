import 'dart:async';

import 'input_stroke.dart';

enum CommandScope { workspace, page, playback, local }

enum CommandOutcome { completed, failed, stale, noOp, busy }

enum DispatchReason {
  unbound,
  disabled,
  editorReserved,
  controlReserved,
  modalBlocked,
  inactiveWindow,
  unsupported,
  duplicateTarget,
  sequenceTail,
  synthesized,
  executed,
  completed,
  atBoundary,
  failed,
  staleOwner,
  busy,
}

typedef InputCommand = FutureOr<CommandOutcome> Function(InputStroke stroke);

final class DispatchResult<C> {
  const DispatchResult(
    this.reason, {
    this.command,
    this.matched = false,
    this.claimed = false,
    this.executed = false,
    this.scope,
    this.ownerGeneration,
  });
  final DispatchReason reason;
  final C? command;
  final bool matched, claimed, executed;
  final CommandScope? scope;
  final int? ownerGeneration;
}

final class InputTrace<C> {
  const InputTrace(
    this.sequence,
    this.device,
    this.phase,
    this.chord,
    this.fallback,
    this.synthesized,
    this.result, {
    this.elapsedMicros,
    this.logicalKeyId,
    this.physicalKeyId,
    this.viewId,
    this.buttons,
  });
  final int sequence;
  final InputDevice device;
  final InputPhase phase;
  final String? chord;
  final bool fallback, synthesized;
  final DispatchResult<C> result;
  final int? elapsedMicros, logicalKeyId, physicalKeyId, viewId, buttons;
}

final class ShortcutContext {
  const ShortcutContext({
    this.activeWindow = true,
    this.editing = false,
    this.reserveActivation = false,
    this.modal = false,
    this.topRoute,
  });
  final bool activeWindow, editing, reserveActivation, modal;
  final Object? topRoute;
}

final class CommandRegistration<C> {
  CommandRegistration._(
    this.generation,
    this.owner,
    this.scope,
    this.commands,
    this.active,
    this.route,
    this.onCancel,
    this.onNavigate,
    this.revision,
    this.onDispose,
  );
  final Object owner;
  final int generation;
  final CommandScope scope;
  final Map<C, InputCommand> commands;
  final bool Function() active;
  final Object? route;
  final void Function()? onCancel;
  final void Function()? onNavigate;
  final Object? Function()? revision;
  final void Function() onDispose;
  bool disposed = false;
  void dispose() {
    if (disposed) return;
    disposed = true;
    onDispose();
  }
}

final class _Press<C> {
  _Press(this.command, this.target, this.callback, this.stroke)
    : revision = target?.revision?.call();
  final Object? revision;
  final C? command;
  final CommandRegistration<C>? target;
  final InputCommand callback;
  final InputStroke stroke;
  bool cancelled = false;
}

/// One selected owner per physical press. No Flutter or business dependencies.
class ShortcutDispatcher<C> {
  ShortcutDispatcher({
    required this.scopeFor,
    required this.repeats,
    required this.editorException,
  });
  final CommandScope Function(C) scopeFor;
  final bool Function(C) repeats;
  final bool Function(C, ShortcutChord) editorException;
  Map<ShortcutChord, C> _bindings = const {};
  Set<ShortcutChord> _disabled = const {};
  final _targets = <CommandRegistration<C>>[];
  int _registrationGeneration = 0;
  final _presses = <String, _Press<C>>{};
  InputCommand? recording;
  final diagnostics = <InputTrace<C>>[];
  InputStroke? _currentStroke;
  bool _redacted = true;
  bool diagnosticsEnabled = false;
  int barriers = 0;
  void Function(DispatchResult<C>)? onResult;
  final Map<ShortcutChord, C> localBindings = {};
  void replaceBindings(
    Map<ShortcutChord, C> bindings, {
    Set<ShortcutChord> disabled = const {},
  }) {
    cancel();
    _bindings = Map.unmodifiable(bindings);
    _disabled = Set.unmodifiable(disabled);
  }

  CommandRegistration<C> register({
    required Object owner,
    required CommandScope scope,
    required Map<C, InputCommand> commands,
    required bool Function() active,
    Object? route,
    void Function()? onCancel,
    void Function()? onNavigate,
    Object? Function()? revision,
  }) {
    if (_targets.length >= 128) {
      throw StateError('Input target capacity exceeded');
    }
    late final CommandRegistration<C> registration;
    registration = CommandRegistration._(
      ++_registrationGeneration,
      owner,
      scope,
      commands,
      active,
      route,
      onCancel,
      onNavigate,
      revision,
      () {
        _targets.remove(registration);
        _cancelTarget(registration);
      },
    );
    _targets.add(registration);
    return registration;
  }

  void invalidate(CommandRegistration<C> target) => _cancelTarget(target);

  void _cancelTarget(CommandRegistration<C> target) {
    target.onCancel?.call();
    for (final press in _presses.values) {
      if (identical(press.target, target)) press.cancelled = true;
    }
  }

  void cancel({bool keepWorkspace = false}) {
    for (final target in _targets.toList()) {
      if (keepWorkspace && target.scope == CommandScope.workspace) continue;
      _cancelTarget(target);
    }
    for (final press in _presses.values) {
      if (keepWorkspace && press.target?.scope == CommandScope.workspace) {
        continue;
      }
      press.cancelled = true;
    }
  }

  void beforeNavigation() {
    cancel(keepWorkspace: true);
    for (final target in _targets.toList()) {
      if (target.active()) target.onNavigate?.call();
    }
  }

  void resetDevice(InputDevice device) {
    _presses.removeWhere((_, press) => press.stroke.device == device);
  }

  void dispose() {
    cancel();
    _targets.clear();
    _presses.clear();
    diagnostics.clear();
    recording = null;
  }

  DispatchResult<C> _result(
    DispatchResult<C> result, {
    InputStroke? source,
    bool? redacted,
  }) {
    if (diagnosticsEnabled) {
      if (diagnostics.length == 256) diagnostics.removeAt(0);
      final stroke = source ?? _currentStroke;
      if (stroke != null) {
        diagnostics.add(
          InputTrace(
            stroke.sequence,
            stroke.device,
            stroke.phase,
            (redacted ?? _redacted) ? null : stroke.chord?.toString(),
            stroke.physicalFallback,
            stroke.synthesized,
            result,
            elapsedMicros: stroke.elapsedMicros,
            logicalKeyId: (redacted ?? _redacted) ? null : stroke.logicalKeyId,
            physicalKeyId: (redacted ?? _redacted)
                ? null
                : stroke.physicalKeyId,
            viewId: stroke.viewId,
            buttons: (redacted ?? _redacted) ? null : stroke.buttons,
          ),
        );
      }
    }
    onResult?.call(result);
    return result;
  }

  void _execute(_Press<C> press, InputStroke stroke) {
    final redacted = _redacted;
    Future<CommandOutcome>.sync(() => press.callback(stroke)).then(
      (outcome) {
        final target = press.target;
        if (target != null &&
            (target.disposed ||
                !target.active() ||
                target.revision?.call() != press.revision)) {
          outcome = CommandOutcome.stale;
        }
        _result(
          DispatchResult(
            switch (outcome) {
              CommandOutcome.failed => DispatchReason.failed,
              CommandOutcome.stale => DispatchReason.staleOwner,
              CommandOutcome.busy => DispatchReason.busy,
              CommandOutcome.noOp => DispatchReason.atBoundary,
              CommandOutcome.completed => DispatchReason.completed,
            },
            command: press.command,
            matched: true,
            claimed: true,
            executed: outcome == CommandOutcome.completed,
            scope: press.target?.scope,
            ownerGeneration: press.target?.generation,
          ),
          source: stroke,
          redacted: redacted,
        );
      },
      onError: (Object _, StackTrace _) {
        _result(
          DispatchResult(
            DispatchReason.failed,
            command: press.command,
            matched: true,
            claimed: true,
            scope: press.target?.scope,
            ownerGeneration: press.target?.generation,
          ),
          source: stroke,
          redacted: redacted,
        );
      },
    );
  }

  DispatchResult<C> dispatch(InputStroke stroke, ShortcutContext context) {
    _currentStroke = stroke;
    _redacted = recording == null && (context.editing || context.modal);
    final old = _presses[stroke.identity];
    if (old != null) {
      if (stroke.synthesized || stroke.phase == InputPhase.cancel) {
        old.target?.onCancel?.call();
        old.cancelled = true;
      }
      if (stroke.phase == InputPhase.up || stroke.phase == InputPhase.cancel) {
        _presses.remove(stroke.identity);
      }
      final valid =
          !old.cancelled &&
          !stroke.synthesized &&
          context.activeWindow &&
          (!context.modal ||
              old.target == null ||
              (old.target?.scope == CommandScope.local &&
                  identical(old.target?.route, context.topRoute))) &&
          (old.target == null ||
              (!old.target!.disposed &&
                  old.target!.active() &&
                  old.revision == old.target!.revision?.call()));
      if (valid &&
          (stroke.phase == InputPhase.up ||
              (stroke.phase == InputPhase.repeat &&
                  old.command != null &&
                  repeats(old.command as C)))) {
        _execute(old, stroke);
      }
      return _result(
        DispatchResult(
          DispatchReason.sequenceTail,
          command: old.command,
          scope: old.target?.scope,
          ownerGeneration: old.target?.generation,
          matched: true,
          claimed: true,
        ),
      );
    }
    if (stroke.synthesized) {
      return _result(const DispatchResult(DispatchReason.synthesized));
    }
    if (stroke.phase != InputPhase.down) {
      return _result(const DispatchResult(DispatchReason.unbound));
    }
    if (!context.activeWindow) {
      return _result(const DispatchResult(DispatchReason.inactiveWindow));
    }
    if (_presses.length >= 64) {
      return _result(const DispatchResult(DispatchReason.busy, claimed: true));
    }
    final recorder = recording;
    if (recorder != null) {
      final press = _Press<C>(null, null, recorder, stroke);
      _presses[stroke.identity] = press;
      _execute(press, stroke);
      return _result(
        const DispatchResult(
          DispatchReason.executed,
          claimed: true,
          executed: true,
        ),
      );
    }
    final chord = stroke.chord;
    final command = context.modal ? localBindings[chord] : _bindings[chord];
    if (command == null) {
      return _result(
        DispatchResult(
          context.modal
              ? DispatchReason.modalBlocked
              : _disabled.contains(chord)
              ? DispatchReason.disabled
              : DispatchReason.unbound,
        ),
      );
    }
    if (!context.modal &&
        context.editing &&
        !editorException(command, chord!)) {
      return _result(
        DispatchResult(
          DispatchReason.editorReserved,
          command: command,
          matched: true,
        ),
      );
    }
    if (!context.modal &&
        context.reserveActivation &&
        (chord?.key == 'Space' || chord?.key == 'Enter') &&
        scopeFor(command) == CommandScope.playback) {
      return _result(
        DispatchResult(
          DispatchReason.controlReserved,
          command: command,
          matched: true,
        ),
      );
    }
    final targets = _targets
        .where(
          (target) =>
              !target.disposed &&
              target.active() &&
              target.scope ==
                  (context.modal ? CommandScope.local : scopeFor(command)) &&
              target.commands.containsKey(command) &&
              (!context.modal || identical(target.route, context.topRoute)),
        )
        .toList();
    if (targets.length != 1) {
      return _result(
        DispatchResult(
          targets.isEmpty
              ? DispatchReason.unsupported
              : DispatchReason.duplicateTarget,
          command: command,
          matched: true,
        ),
      );
    }
    final target = targets.single;
    final press = _Press(command, target, target.commands[command]!, stroke);
    _presses[stroke.identity] = press;
    _execute(press, stroke);
    return _result(
      DispatchResult(
        DispatchReason.executed,
        command: command,
        matched: true,
        claimed: true,
        executed: true,
        scope: target.scope,
        ownerGeneration: target.generation,
      ),
    );
  }
}
