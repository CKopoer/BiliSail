import 'package:material_ui/material_ui.dart';

import '../../domain/favorite_content_filter.dart';

class FavoriteContentToolbar extends StatefulWidget {
  const FavoriteContentToolbar({
    super.key,
    required this.filter,
    required this.onChanged,
    this.allowAllFolders = false,
  });

  final FavoriteContentFilter filter;
  final ValueChanged<FavoriteContentFilter> onChanged;
  final bool allowAllFolders;

  @override
  State<FavoriteContentToolbar> createState() => _FavoriteContentToolbarState();
}

class _FavoriteContentToolbarState extends State<FavoriteContentToolbar> {
  late final _keyword = TextEditingController(text: widget.filter.keyword);

  static String _label(FavoriteContentOrder order) => switch (order) {
    FavoriteContentOrder.recentlySaved => '最近收藏',
    FavoriteContentOrder.mostPlayed => '最多播放',
    FavoriteContentOrder.recentlyPublished => '最近投稿',
  };

  void _submit(String text) {
    widget.onChanged((
      keyword: text.trim(),
      order: widget.filter.order,
      allFolders: widget.filter.allFolders,
    ));
  }

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = widget.filter;
    final search = TextField(
      key: const ValueKey('favorite-content-search'),
      controller: _keyword,
      textInputAction: TextInputAction.search,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: filter.allFolders ? '搜索我的全部收藏' : '搜索夹内视频',
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        prefixIcon: widget.allowAllFolders
            ? PopupMenuButton<bool>(
                key: const ValueKey('favorite-search-scope'),
                tooltip: '搜索范围',
                icon: Icon(
                  filter.allFolders
                      ? Icons.folder_copy_outlined
                      : Icons.folder_open_outlined,
                  size: 20,
                ),
                itemBuilder: (context) => [
                  CheckedPopupMenuItem(
                    value: false,
                    checked: !filter.allFolders,
                    child: const Text('当前收藏夹'),
                  ),
                  CheckedPopupMenuItem(
                    value: true,
                    checked: filter.allFolders,
                    child: const Text('我的全部收藏'),
                  ),
                ],
                onSelected: (allFolders) => widget.onChanged((
                  keyword: _keyword.text.trim(),
                  order: filter.order,
                  allFolders: allFolders,
                )),
              )
            : null,
        suffixIcon: ValueListenableBuilder(
          valueListenable: _keyword,
          builder: (context, value, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value.text.isNotEmpty || filter.keyword.isNotEmpty)
                IconButton(
                  tooltip: '清除搜索',
                  onPressed: () {
                    _keyword.clear();
                    _submit('');
                  },
                  icon: const Icon(Icons.close, size: 18),
                ),
              IconButton(
                tooltip: '搜索收藏',
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  _submit(_keyword.text);
                },
                icon: const Icon(Icons.search, size: 20),
              ),
            ],
          ),
        ),
      ),
      onSubmitted: _submit,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final showOrderLabel = constraints.maxWidth >= 440;
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 8),
                PopupMenuButton<FavoriteContentOrder>(
                  key: const ValueKey('favorite-content-sort'),
                  tooltip: '排序方式（${_label(filter.order)}）',
                  icon: showOrderLabel ? null : const Icon(Icons.sort),
                  onSelected: (order) => widget.onChanged((
                    keyword: _keyword.text.trim(),
                    order: order,
                    allFolders: filter.allFolders,
                  )),
                  itemBuilder: (context) => [
                    for (final order in FavoriteContentOrder.values)
                      CheckedPopupMenuItem(
                        value: order,
                        checked: filter.order == order,
                        child: Text(_label(order)),
                      ),
                  ],
                  child: showOrderLabel
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.sort, size: 20),
                              const SizedBox(width: 8),
                              Text(_label(filter.order)),
                            ],
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
