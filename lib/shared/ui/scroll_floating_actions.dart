import 'package:flutter/material.dart';

/// Compact, keyboard-accessible list actions that stay outside the scroll area.
final class ScrollFloatingActions extends StatelessWidget {
  const ScrollFloatingActions({
    super.key,
    required this.onRefresh,
    required this.refreshTooltip,
    this.onToTop,
  });

  final VoidCallback onRefresh;
  final String refreshTooltip;
  final VoidCallback? onToTop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = ButtonStyle(
      fixedSize: const WidgetStatePropertyAll(Size.square(48)),
      minimumSize: const WidgetStatePropertyAll(Size.square(48)),
      maximumSize: const WidgetStatePropertyAll(Size.square(48)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      backgroundColor: WidgetStatePropertyAll(colors.surface),
      foregroundColor: WidgetStatePropertyAll(colors.onSurfaceVariant),
      side: WidgetStatePropertyAll(BorderSide(color: colors.outlineVariant)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      elevation: const WidgetStatePropertyAll(1),
      shadowColor: WidgetStatePropertyAll(
        colors.shadow.withValues(alpha: 0.15),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: refreshTooltip,
          onPressed: onRefresh,
          style: style,
          icon: const Icon(Icons.refresh_rounded, size: 22),
        ),
        if (onToTop != null) ...[
          const SizedBox(height: 8),
          Tooltip(
            message: '回到顶部',
            child: TextButton(
              onPressed: onToTop,
              style: style,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.arrow_upward_rounded, size: 20),
                  Text(
                    '顶部',
                    textScaler: MediaQuery.textScalerOf(context)
                        .clamp(maxScaleFactor: 1.3),
                    style: const TextStyle(fontSize: 10, height: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
