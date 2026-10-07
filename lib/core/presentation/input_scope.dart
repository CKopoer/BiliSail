import 'dart:async';

import 'package:flutter/widgets.dart';

import '../input/shortcut_dispatcher.dart';
import '../input/input_stroke.dart';
import 'app_input_host.dart';

class InputScope<C> extends InheritedWidget {
  const InputScope({
    super.key,
    required this.dispatcher,
    required this.routes,
    required super.child,
  });
  final ShortcutDispatcher<C> dispatcher;
  final InputRouteObserver routes;
  static InputScope<T>? of<T>(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InputScope<T>>();
  @override
  bool updateShouldNotify(InputScope<C> oldWidget) =>
      dispatcher != oldWidget.dispatcher;
}

/// Explicit protection for native editors, custom overlays and player surfaces.
class InputProtection extends InheritedWidget {
  const InputProtection({
    super.key,
    this.editing = false,
    this.reserveActivation = false,
    this.playerSurface = false,
    this.activationFocus,
    required super.child,
  });
  final bool editing, reserveActivation, playerSurface;
  final FocusNode? activationFocus;
  static InputProtection? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<InputProtection>();
  @override
  bool updateShouldNotify(InputProtection oldWidget) => true;
}

/// Non-route overlays/native input regions explicitly isolate underlying targets.
class InputBarrier<C> extends StatefulWidget {
  const InputBarrier({super.key, required this.child});
  final Widget child;
  @override
  State<InputBarrier<C>> createState() => _InputBarrierState<C>();
}

class _InputBarrierState<C> extends State<InputBarrier<C>> {
  ShortcutDispatcher<C>? _dispatcher;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dispatcher = InputScope.of<C>(context)?.dispatcher;
    if (identical(dispatcher, _dispatcher)) return;
    if (_dispatcher != null) _dispatcher!.barriers--;
    _dispatcher = dispatcher;
    if (dispatcher != null) {
      dispatcher.barriers++;
      dispatcher.cancel();
    }
  }

  @override
  void dispose() {
    if (_dispatcher != null) _dispatcher!.barriers--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class CommandTargetScope<C> extends StatefulWidget {
  const CommandTargetScope({
    super.key,
    required this.scope,
    required this.commands,
    required this.child,
    this.active = true,
    this.onCancel,
    this.onNavigate,
    this.merge = const {},
    this.revision,
  });
  final CommandScope scope;
  final Map<C, InputCommand> commands;
  final bool active;
  final VoidCallback? onCancel;
  final VoidCallback? onNavigate;
  final Set<C> merge;
  final Object? Function()? revision;
  final Widget child;
  @override
  State<CommandTargetScope<C>> createState() => _CommandTargetScopeState<C>();
}

class _CommandTargetScopeState<C> extends State<CommandTargetScope<C>> {
  CommandRegistration<C>? _registration;
  InputScope<C>? _input;
  final _pending = <C>{};
  FutureOr<CommandOutcome> _invoke(C command, InputStroke stroke) {
    if (_pending.contains(command)) return CommandOutcome.busy;
    final result =
        widget.commands[command]?.call(stroke) ?? CommandOutcome.stale;
    if (result is Future<CommandOutcome> && widget.merge.contains(command)) {
      _pending.add(command);
      return result.whenComplete(() => _pending.remove(command));
    }
    return result;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final input = InputScope.of<C>(context);
    if (_input?.dispatcher == input?.dispatcher && _registration != null) {
      return;
    }
    _registration?.dispose();
    _input = input;
    _register();
  }

  void _register() {
    _registration = _input?.dispatcher.register(
      owner: this,
      scope: widget.scope,
      commands: {
        for (final command in widget.commands.keys)
          command: (stroke) => _invoke(command, stroke),
      },
      active: () => mounted && widget.active,
      route: ModalRoute.of(context),
      onCancel: () => widget.onCancel?.call(),
      onNavigate: () => widget.onNavigate?.call(),
      revision: () => widget.revision?.call(),
    );
  }

  @override
  void didUpdateWidget(covariant CommandTargetScope<C> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) {
      final registration = _registration;
      if (registration != null) _input?.dispatcher.invalidate(registration);
    }
    if (oldWidget.commands.keys
            .toSet()
            .difference(widget.commands.keys.toSet())
            .isNotEmpty ||
        widget.commands.keys
            .toSet()
            .difference(oldWidget.commands.keys.toSet())
            .isNotEmpty) {
      _registration?.dispose();
      _register();
    }
  }

  @override
  void dispose() {
    _registration?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
