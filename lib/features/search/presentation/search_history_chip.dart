import 'package:flutter/material.dart';

final class SearchHistoryChip extends StatefulWidget {
  const SearchHistoryChip({
    super.key,
    required this.query,
    required this.onSearch,
    required this.onDelete,
  });
  final String query;
  final VoidCallback onSearch, onDelete;

  @override
  State<SearchHistoryChip> createState() => _SearchHistoryChipState();
}

final class _SearchHistoryChipState extends State<SearchHistoryChip> {
  bool _hovered = false, _longPressed = false, _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(4);
    return Focus(
      onFocusChange: (value) => setState(() => _focused = value),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: TapRegion(
          onTapOutside: (_) {
            if (_longPressed) setState(() => _longPressed = false);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 6),
                  child: Material(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: radius,
                    child: Tooltip(
                      message: widget.query,
                      child: InkWell(
                        borderRadius: radius,
                        onTap: widget.onSearch,
                        onLongPress: () => setState(() => _longPressed = true),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            widget.query,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_hovered || _longPressed || _focused)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Tooltip(
                      message: '删除历史记录：${widget.query}',
                      child: Semantics(
                        button: true,
                        label: '删除历史记录：${widget.query}',
                        child: SizedBox.square(
                          dimension: 24,
                          child: Center(
                            child: Material(
                              color: colors.surfaceContainerHighest,
                              shape: const CircleBorder(),
                              child: InkResponse(
                                onTap: widget.onDelete,
                                customBorder: const CircleBorder(),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.close,
                                    size: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
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
