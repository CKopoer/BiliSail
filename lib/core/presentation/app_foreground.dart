import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appForegroundProvider = NotifierProvider.autoDispose<_Foreground, bool>(
  _Foreground.new,
);

final class _Foreground extends Notifier<bool> {
  @override
  bool build() {
    final listener = AppLifecycleListener(
      onStateChange: (value) {
        state = value == AppLifecycleState.resumed;
      },
    );
    ref.onDispose(listener.dispose);
    final current = WidgetsBinding.instance.lifecycleState;
    return current == null || current == AppLifecycleState.resumed;
  }
}
