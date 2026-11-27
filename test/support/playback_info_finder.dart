import 'package:bilisail/shared/ui/playback_sidebar_toggle.dart';
import 'package:flutter_test/flutter_test.dart';

/// Page tests inject a player stub and exercise the action supplied to its toolbar.
Finder findPlaybackInfo(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is PlaybackInfoScope && widget.tooltip == tooltip,
);

void togglePlaybackInfo(WidgetTester tester, Finder info) =>
    tester.widget<PlaybackInfoScope>(info).onToggle();
