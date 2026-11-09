import 'package:flutter/material.dart';

/// Shows a Material dialog inside the caller's window, including desktop views.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  bool? requestFocus,
  AnimationStyle? animationStyle,
}) {
  assert(debugCheckHasMaterialLocalizations(context));
  var navigator = Navigator.of(context);
  if (useRootNavigator) {
    // A secondary View can be anchored below the browser's Navigator. Stop at
    // that View so a playback dialog never lands in the browser window.
    context.visitAncestorElements((element) {
      if (element.widget is View) return false;
      if (element is StatefulElement && element.state is NavigatorState) {
        navigator = element.state as NavigatorState;
      }
      return true;
    });
  }
  // Flutter 3.47.6 showDialog switches to a native dialog window once desktop
  // windowing is enabled. Push the Material route explicitly so every workspace
  // mode keeps the same overlay, focus trap and modal shortcut isolation.
  return navigator.push<T>(
    DialogRoute<T>(
      context: context,
      builder: (context) =>
          _KeyboardAvoidingDialog(child: Builder(builder: builder)),
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierDismissible: barrierDismissible,
      barrierColor:
          barrierColor ??
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      settings: routeSettings,
      anchorPoint: anchorPoint,
      traversalEdgeBehavior:
          traversalEdgeBehavior ?? TraversalEdgeBehavior.closedLoop,
      fullscreenDialog: fullscreenDialog,
      requestFocus: requestFocus,
      animationStyle: animationStyle,
    ),
  );
}

/// The OS already animates the keyboard inset. Consume it immediately before
/// Dialog adds its margins, so Dialog's default animation cannot lag behind
/// the keyboard. Keep the child mounted and avoid applying the inset twice.
class _KeyboardAvoidingDialog extends StatelessWidget {
  const _KeyboardAvoidingDialog({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: child,
    ),
  );
}
