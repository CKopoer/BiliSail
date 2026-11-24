import 'package:flutter/widgets.dart';

import 'workspace_activity.dart';

/// Page-local back steps run before the workspace changes or closes a page.
final class PageBackController extends ChangeNotifier {
  final _handlers = <_PageBackHandlerState>[];
  bool _notificationPending = false;
  bool _disposed = false;

  bool get canGoBack => _handlers.any((handler) => handler.enabled);

  bool goBack() {
    for (final handler in _handlers.reversed.toList()) {
      if (handler.enabled && handler.widget.onBack()) return true;
    }
    return false;
  }

  void _changed() {
    if (_disposed || _notificationPending) return;
    _notificationPending = true;
    // Descendants register during build; update shell chrome after that frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationPending = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _handlers.clear();
    super.dispose();
  }
}

final class PageBackScope extends InheritedWidget {
  const PageBackScope({
    super.key,
    required this.controller,
    this.route,
    required super.child,
  });

  final PageBackController controller;

  /// A scope inside a popup owns only the handlers on that route.
  final ModalRoute<Object?>? route;

  static PageBackController? maybeOf(
    BuildContext context,
    ModalRoute<Object?>? currentRoute,
  ) {
    final scope = context.dependOnInheritedWidgetOfExactType<PageBackScope>();
    if (currentRoute is PopupRoute && scope?.route != currentRoute) return null;
    return scope?.controller;
  }

  @override
  bool updateShouldNotify(PageBackScope oldWidget) =>
      controller != oldWidget.controller || route != oldWidget.route;
}

final class PageBackHandler extends StatefulWidget {
  const PageBackHandler({
    super.key,
    required this.enabled,
    required this.onBack,
    required this.child,
  });

  final bool enabled;
  final bool Function() onBack;
  final Widget child;

  @override
  State<PageBackHandler> createState() => _PageBackHandlerState();
}

final class _PageBackHandlerState extends State<PageBackHandler> {
  PageBackController? _controller;
  bool _active = true;
  ModalRoute<Object?>? _route;

  bool get enabled => mounted && _active && widget.enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = WorkspaceActivity.isActive(context);
    _route = ModalRoute.of(context);
    final controller = PageBackScope.maybeOf(context, _route);
    if (_controller != controller) {
      _controller?._handlers.remove(this);
      _controller?._changed();
      _controller = controller;
      _controller?._handlers.add(this);
    }
    _controller?._changed();
  }

  @override
  void didUpdateWidget(PageBackHandler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _controller?._changed();
  }

  @override
  void dispose() {
    _controller?._handlers.remove(this);
    _controller?._changed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _controller != null
      ? widget.child
      : PopScope<Object?>(
          canPop: !enabled,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && enabled && (_route?.isCurrent ?? true)) {
              widget.onBack();
            }
          },
          child: widget.child,
        );
}
