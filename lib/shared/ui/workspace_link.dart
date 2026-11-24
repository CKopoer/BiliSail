import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../domain/article_address.dart';
import '../../domain/course_address.dart';

class WorkspaceLinkScope extends InheritedWidget {
  const WorkspaceLinkScope({
    super.key,
    required this.openBackground,
    required super.child,
  });

  final ValueChanged<Uri>? openBackground;
  static final _backgroundKey = Object();

  static ValueChanged<Uri>? _backgroundOpener(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WorkspaceLinkScope>()
      ?.openBackground;

  static bool get openingInBackground => Zone.current[_backgroundKey] != null;

  static GestureTapUpCallback? middleClick(
    BuildContext context,
    VoidCallback? open,
  ) {
    final background = _backgroundOpener(context);
    if (background == null || open == null) return null;
    return (details) {
      if (details.kind != PointerDeviceKind.mouse) return;
      // Reuse the link's route builder, including asynchronous queue capture.
      runZoned(open, zoneValues: {_backgroundKey: background});
    };
  }

  @override
  bool updateShouldNotify(WorkspaceLinkScope oldWidget) =>
      openBackground != oldWidget.openBackground;
}

extension WorkspaceLinkNavigation on BuildContext {
  bool openArticleOrCourseLink(Uri target) {
    final location =
        CourseAddress.parse(target)?.location ??
        ArticleAddress.workspaceLocation(target);
    if (location == null) return false;
    openWorkspaceLink(location);
    return true;
  }

  void openWorkspaceLink(String location) {
    final background =
        Zone.current[WorkspaceLinkScope._backgroundKey] as ValueChanged<Uri>?;
    if (background != null) {
      background(Uri.parse(location));
    } else {
      go(location);
    }
  }
}
