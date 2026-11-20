import 'package:material_ui/material_ui.dart';

import '../../domain/favorite_content_filter.dart';
import 'content_search_field.dart';

class FavoriteContentToolbar extends StatefulWidget {
  const FavoriteContentToolbar({
    super.key,
    required this.title,
    this.onBack,
    this.backTooltip = '返回列表',
    this.playAll,
    this.filter = defaultFavoriteContentFilter,
    this.onChanged,
    this.allowAllFolders = false,
  });

  final String title, backTooltip;
  final VoidCallback? onBack;
  final Widget? playAll;
  final FavoriteContentFilter filter;
  final ValueChanged<FavoriteContentFilter>? onChanged;
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

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = Row(
      children: [
        if (widget.onBack != null)
          IconButton(
            tooltip: widget.backTooltip,
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
          ),
        Expanded(
          child: Text(
            widget.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    Widget header({Widget? filters}) => Row(
      children: [
        Expanded(child: title),
        if (filters != null) ...[
          const SizedBox(width: 12),
          Expanded(flex: 2, child: filters),
          const SizedBox(width: 12),
        ],
        ?widget.playAll,
      ],
    );

    final onChanged = widget.onChanged;
    if (onChanged == null) return header();
    final filter = widget.filter;
    void submit(String text) => onChanged((
      keyword: text.trim(),
      order: filter.order,
      allFolders: filter.allFolders,
    ));

    final scope = widget.allowAllFolders
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
            onSelected: (allFolders) => onChanged((
              keyword: _keyword.text.trim(),
              order: filter.order,
              allFolders: allFolders,
            )),
          )
        : null;
    final search = ValueListenableBuilder(
      valueListenable: _keyword,
      builder: (context, value, _) => ContentSearchField(
        key: const ValueKey('favorite-content-search'),
        controller: _keyword,
        hintText: filter.allFolders ? '搜索我的全部收藏' : '搜索夹内视频',
        searchTooltip: '搜索收藏',
        prefixIcon: scope,
        onSearch: (text) {
          FocusScope.of(context).unfocus();
          submit(text);
        },
        onClear: value.text.isNotEmpty || filter.keyword.isNotEmpty
            ? () {
                _keyword.clear();
                submit('');
              }
            : null,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final inline = constraints.maxWidth >= 600;
        final showOrderLabel = constraints.maxWidth >= (inline ? 760 : 440);
        final filters = Row(
          mainAxisAlignment: inline
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Flexible(
              fit: inline ? FlexFit.loose : FlexFit.tight,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: inline ? 260 : double.infinity,
                ),
                child: search,
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<FavoriteContentOrder>(
              key: const ValueKey('favorite-content-sort'),
              tooltip: '排序方式（${_label(filter.order)}）',
              icon: showOrderLabel ? null : const Icon(Icons.sort),
              onSelected: (order) => onChanged((
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
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: inline
              ? header(filters: filters)
              : Column(
                  children: [header(), const SizedBox(height: 8), filters],
                ),
        );
      },
    );
  }
}
