import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../application/search_controller.dart';
import '../domain/search_result.dart';

/// The workspace header and result page share the enclosing tab's controller.
final class SearchCategoryBar extends ConsumerWidget {
  const SearchCategoryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = ref.watch(
      searchControllerProvider.select(
        (state) => (state.category, state.counts),
      ),
    );
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      height: 58,
      child: ScrollConfiguration(
        behavior: const SmoothScrollBehavior(horizontalMouseWheel: true),
        child: SingleChildScrollView(
          key: const ValueKey('search-category-strip'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              for (final category in SearchCategory.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Semantics(
                    selected: navigation.$1 == category,
                    button: true,
                    child: TextButton(
                      key: ValueKey('search-category-${category.name}'),
                      onPressed: () => ref
                          .read(searchControllerProvider.notifier)
                          .selectCategory(category),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        foregroundColor: navigation.$1 == category
                            ? colors.primary
                            : colors.onSurface,
                        textStyle: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(category.label),
                              if (navigation.$2[category] case final int total)
                                Padding(
                                  padding: const EdgeInsets.only(left: 5),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: colors.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      child: Text(
                                        total > 99 ? '99+' : '$total',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 20,
                            height: 2,
                            color: navigation.$1 == category
                                ? colors.primary
                                : Colors.transparent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
