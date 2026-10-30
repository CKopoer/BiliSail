import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lets the workspace place its navigation control in a page-owned toolbar.
class PageToolbarLeading extends InheritedWidget {
  const PageToolbarLeading({
    super.key,
    required this.leading,
    required super.child,
  });

  final Widget? leading;

  static Widget? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageToolbarLeading>()?.leading;

  @override
  bool updateShouldNotify(PageToolbarLeading oldWidget) =>
      leading != oldWidget.leading;
}

/// A page title and actions that keep their touch targets at narrow widths.
class PageToolbar extends StatelessWidget {
  const PageToolbar({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final leading = PageToolbarLeading.maybeOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(leading == null ? 20 : 8, 12, 8, 4),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size.square(48),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Below the width of the controls themselves, allow scrolling
            // instead of shrinking or overlapping their touch targets.
            final minimumWidth =
                (actions.length + (leading == null ? 0 : 1)) * 48.0 + 48;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(constraints.maxWidth, minimumWidth),
                child: Row(
                  children: [
                    ?leading,
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
