import 'dart:async';

import 'package:flutter/material.dart';

/// Shows one transient notice above the app's routes without blocking input.
void showAppNotice(BuildContext context, String message) {
  final host = context.findAncestorStateOfType<_AppNoticeHostState>();
  if (host == null) {
    throw FlutterError('showAppNotice requires an AppNoticeHost ancestor.');
  }
  host.show(message);
}

/// Install through MaterialApp.builder so dialogs and fullscreen share a host.
class AppNoticeHost extends StatefulWidget {
  const AppNoticeHost({super.key, required this.child});

  final Widget child;

  static Widget builder(BuildContext context, Widget? child) =>
      AppNoticeHost(child: child ?? const SizedBox.shrink());

  @override
  State<AppNoticeHost> createState() => _AppNoticeHostState();
}

class _AppNoticeHostState extends State<AppNoticeHost> {
  Timer? _dismissTimer;
  String? _message;

  void show(String message) {
    _dismissTimer?.cancel();
    setState(() => _message = message);
    _dismissTimer = Timer(const Duration(milliseconds: 1500), () {
      setState(() => _message = null);
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (message != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SafeArea(
                  minimum: const EdgeInsets.all(16),
                  child: Align(
                    alignment: const Alignment(0, .35),
                    child: Semantics(
                      liveRegion: true,
                      child: Material(
                        color: theme.colorScheme.inverseSurface.withValues(
                          alpha: .95,
                        ),
                        elevation: 4,
                        shadowColor: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Text(
                            message,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onInverseSurface,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
