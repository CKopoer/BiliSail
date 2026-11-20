import 'package:material_ui/material_ui.dart';

class PostCardSurface extends StatelessWidget {
  const PostCardSurface({
    super.key,
    required this.child,
    this.onTap,
    this.onMore,
  }) : _sliver = false;

  const PostCardSurface.sliver({super.key, required Widget sliver})
    : child = sliver,
      onTap = null,
      onMore = null,
      _sliver = true;

  final Widget child;
  final VoidCallback? onTap, onMore;
  final bool _sliver;

  static TextStyle? bodyStyleOf(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontSize: 15, height: 22 / 15);

  static TextStyle? titleStyleOf(
    BuildContext context, {
    required bool inDetail,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return inDetail
        ? textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)
        : textTheme.titleSmall;
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerLow;
    const radius = BorderRadius.all(Radius.circular(12));
    const padding = EdgeInsets.all(16);
    if (_sliver) {
      return DecoratedSliver(
        decoration: BoxDecoration(color: color, borderRadius: radius),
        sliver: SliverPadding(padding: padding, sliver: child),
      );
    }
    return Material(
      color: color,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // A reading card has no primary tap action, even if it has a menu.
        hoverColor: onTap == null ? Colors.transparent : null,
        onLongPress: onMore,
        onSecondaryTap: onMore,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
