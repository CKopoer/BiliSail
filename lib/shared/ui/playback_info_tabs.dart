import 'package:flutter/material.dart';

import 'paging_tab_strip.dart';
import 'retained_tab_view.dart';

/// Shared sidebar navigation; the player stays outside the retained pager.
final class PlaybackInfoTabs extends StatefulWidget {
  const PlaybackInfoTabs({
    super.key,
    required this.labels,
    required this.value,
    required this.onChanged,
    required this.pageBuilder,
    required this.viewKey,
    this.itemKey,
    this.trailing,
    this.compact = false,
    this.preloadPages = false,
  });

  final List<Widget> labels;
  final int value;
  final ValueChanged<int> onChanged;
  final RetainedTabPageBuilder<int> pageBuilder;
  final Key viewKey;
  final Key Function(int)? itemKey;
  final Widget? trailing;
  final bool compact;
  final bool preloadPages;

  @override
  State<PlaybackInfoTabs> createState() => _PlaybackInfoTabsState();
}

final class _PlaybackInfoTabsState extends State<PlaybackInfoTabs> {
  late final _progress = TabPagingProgress(widget.value.toDouble());

  @override
  Widget build(BuildContext context) {
    final tabs = List<int>.generate(widget.labels.length, (index) => index);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: PagingTabStrip<int>(
                  tabs: tabs,
                  value: widget.value,
                  onSelected: widget.onChanged,
                  progress: _progress,
                  itemKey: widget.itemKey,
                  labelBuilder: (_, tab) => widget.labels[tab],
                  spacing: 0,
                  fullWidthIndicator: true,
                  indicatorHeight: widget.compact ? 2 : 3,
                  unselectedColor: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                  buttonStyle: TextButton.styleFrom(
                    padding: widget.compact
                        ? const EdgeInsets.fromLTRB(16, 11, 16, 9)
                        : const EdgeInsets.fromLTRB(17, 15, 17, 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: const RoundedRectangleBorder(),
                    textStyle: widget.compact
                        ? Theme.of(context).textTheme.labelLarge
                        : Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
            ?widget.trailing,
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: RetainedTabView<int>(
            tabs: tabs,
            value: widget.value,
            onChanged: widget.onChanged,
            progress: _progress,
            viewKey: widget.viewKey,
            pageBuilder: widget.pageBuilder,
            preloadPages: widget.preloadPages,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }
}
