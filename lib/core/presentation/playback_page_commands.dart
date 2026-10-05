import 'package:flutter/widgets.dart';

class PlaybackPageCommands extends InheritedWidget {
  const PlaybackPageCommands({
    super.key,
    required this.previousPart,
    required this.nextPart,
    required this.toggleInfo,
    required super.child,
  });
  final VoidCallback previousPart, nextPart, toggleInfo;
  static PlaybackPageCommands? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaybackPageCommands>();
  @override
  bool updateShouldNotify(PlaybackPageCommands oldWidget) => true;
}
