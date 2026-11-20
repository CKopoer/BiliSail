import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide SearchController;

import '../../../shared/ui/paging_tab_strip.dart';
import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../application/search_controller.dart';
import '../domain/search_result.dart';

/// The workspace header and result page share the enclosing tab's controller.
final class SearchCategoryBar extends ConsumerWidget {
  const SearchCategoryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (selected, counts) = ref.watch(
      searchControllerProvider.select(
        (state) => (state.category, state.counts),
      ),
    );
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      height: 58,
      child: ScrollConfiguration(
        behavior: const SmoothScrollBehavior(horizontalMouseWheel: true)
            .copyWith(
              dragDevices: {
                ...const SmoothScrollBehavior().dragDevices,
                PointerDeviceKind.mouse,
              },
            ),
        child: SingleChildScrollView(
          key: const ValueKey('search-category-strip'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: PagingTabStrip(
            tabs: SearchCategory.values,
            value: selected,
            itemKey: (category) => ValueKey('search-category-${category.name}'),
            onSelected: ref
                .read(searchControllerProvider.notifier)
                .selectCategory,
            buttonStyle: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 9),
              textStyle: theme.textTheme.labelLarge,
            ),
            unselectedColor: colors.onSurfaceVariant,
            labelBuilder: (context, category) => Row(
              spacing: 5,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(category.label),
                if (counts[category] case final total?)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: category == selected
                          ? colors.primaryContainer
                          : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Text(
                        total > 99 ? '99+' : '$total',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: category == selected
                              ? colors.onPrimaryContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
