import 'package:flutter/widgets.dart';

import '../../domain/content_link.dart';

class ContentLinkScope extends InheritedWidget {
  const ContentLinkScope({super.key, required this.link, required super.child});
  final ContentLink link;
  static ContentLink of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentLinkScope>()?.link ??
      const ContentLink();
  @override
  bool updateShouldNotify(ContentLinkScope oldWidget) => link != oldWidget.link;
}
