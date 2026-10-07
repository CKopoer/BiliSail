import 'package:bilisail/app/shortcut_coordinator.dart';
import 'package:bilisail/core/presentation/app_input_host.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Mounts the same root host/observer as BiliApp, including isolated UI tests.
class InputTestApp extends StatefulWidget {
  const InputTestApp({
    super.key,
    this.home,
    this.theme,
    this.builder,
    this.navigatorObservers = const [],
    this.shortcuts = const ShortcutSettings.defaults(),
  }) : routerConfig = null;
  const InputTestApp.router({
    super.key,
    required this.routerConfig,
    this.builder,
    this.theme,
    this.shortcuts = const ShortcutSettings.defaults(),
  }) : home = null,
       navigatorObservers = const [];
  final GoRouter? routerConfig;
  final Widget? home;
  final ThemeData? theme;
  final TransitionBuilder? builder;
  final List<NavigatorObserver> navigatorObservers;
  final ShortcutSettings shortcuts;
  @override
  State<InputTestApp> createState() => _InputTestAppState();
}

class _InputTestAppState extends State<InputTestApp> {
  final input = ShortcutCoordinator();
  @override
  void initState() {
    super.initState();
    widget.routerConfig?.routerDelegate.builder.observers.add(input.routes);
    for (final route
        in widget.routerConfig?.configuration.routes ?? <RouteBase>[]) {
      if (route is ShellRoute) route.observers?.add(input.routes.child());
    }
  }

  Widget _builder(BuildContext context, Widget? child) => AppInputHost<Object>(
    dispatcher: input,
    routes: input.routes,
    child: widget.builder?.call(context, child) ?? child ?? const SizedBox(),
  );
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    input.configure(widget.shortcuts);
    if (widget.routerConfig case final GoRouter router) {
      return MaterialApp.router(
        routerConfig: router,
        theme: widget.theme,
        builder: _builder,
      );
    }
    return MaterialApp(
      home: widget.home,
      theme: widget.theme,
      builder: _builder,
      navigatorObservers: [...widget.navigatorObservers, input.routes],
    );
  }
}
