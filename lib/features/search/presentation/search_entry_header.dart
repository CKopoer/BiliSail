import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/bili_icons.dart';
import '../application/search_discovery_controller.dart';
import 'search_discovery_panel.dart';

final class SearchEntryHeader extends StatefulWidget {
  const SearchEntryHeader({
    super.key,
    required this.controller,
    required this.onSearch,
    this.leading,
    this.trailing,
    this.navigation,
    this.inlineNavigation = false,
  });
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final Widget? leading, trailing, navigation;
  final bool inlineNavigation;
  @override
  State<SearchEntryHeader> createState() => _SearchEntryHeaderState();
}

final class _SearchEntryHeaderState extends State<SearchEntryHeader> {
  final _overlay = OverlayPortalController();
  final _link = LayerLink();
  final _anchor = GlobalKey();
  final _focus = FocusNode();
  final _tapGroup = Object();
  bool _open = false;
  bool _mobileOpen = false;
  bool _mobile = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (_focus.hasFocus && !_mobile) _show();
  }

  void _show() {
    if (_open) return;
    setState(() => _open = true);
    _overlay.show();
  }

  void _close() {
    if (!_open) return;
    _overlay.hide();
    _focus.unfocus();
    setState(() => _open = false);
  }

  void _submit(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    _close();
    widget.controller.text = query;
    unawaited(
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(searchDiscoveryControllerProvider.notifier).remember(query),
    );
    widget.onSearch(query);
  }

  Future<void> _openMobile() async {
    if (_mobileOpen) return;
    _mobileOpen = true;
    _focus.unfocus();
    final container = ProviderScope.containerOf(context, listen: false);
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => UncontrolledProviderScope(
          container: container,
          child: _SearchPage(
            initialQuery: widget.controller.text,
            onChanged: (value) {
              if (mounted) widget.controller.text = value;
            },
          ),
        ),
      ),
    );
    _mobileOpen = false;
    if (mounted && result != null) _submit(result);
  }

  @override
  void didUpdateWidget(covariant SearchEntryHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _close();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = _mobile = constraints.maxWidth < 600;
      if (mobile && _open) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _close();
        });
      }
      final inline = widget.inlineNavigation;
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260);
      final toolWidth = inline
          ? (constraints.maxWidth >= 1300 ? 470.0 : 380.0)
          : constraints.maxWidth;
      final expandedWidth = math.min(480.0, constraints.maxWidth - 20);
      final tools = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            if (widget.leading case final leading?)
              _collapsingTool(leading, inline: inline, duration: duration),
            Expanded(
              child: CompositedTransformTarget(
                link: _link,
                child: TapRegion(
                  groupId: _tapGroup,
                  onTapOutside: (_) => _close(),
                  child: SizedBox(
                    key: _anchor,
                    height: 36,
                    child: CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.escape):
                            _close,
                      },
                      child: TextField(
                        key: const ValueKey('workspace-search'),
                        controller: widget.controller,
                        focusNode: _focus,
                        readOnly: mobile,
                        onTap: mobile ? _openMobile : _show,
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(fontSize: 13),
                        onSubmitted: _submit,
                        decoration: InputDecoration(
                          hintText: '搜索视频、UP 主、番剧',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          suffixIcon: IconButton(
                            tooltip: '搜索',
                            onPressed: mobile
                                ? _openMobile
                                : () => widget.controller.text.trim().isEmpty
                                      ? _show()
                                      : _submit(widget.controller.text),
                            icon: const Icon(BiliIcons.search, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.trailing case final trailing?)
              _collapsingTool(trailing, inline: inline, duration: duration),
          ],
        ),
      );
      return OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (context) {
          final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
          final width = inline && _open
              ? expandedWidth - 20
              : box?.size.width ?? expandedWidth;
          final bottom = box == null
              ? 90.0
              : box.localToGlobal(Offset(0, box.size.height)).dy;
          final height = math.max(
            0.0,
            math.min(
              520.0,
              MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom -
                  bottom -
                  16,
            ),
          );
          return Positioned.fill(
            child: Stack(
              children: [
                CompositedTransformFollower(
                  link: _link,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomLeft,
                  offset: const Offset(0, 6),
                  child: TapRegion(
                    groupId: _tapGroup,
                    child: SizedBox(
                      width: width,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: height),
                        child: CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.escape):
                                _close,
                          },
                          child: Material(
                            elevation: 8,
                            shadowColor: Colors.black26,
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: SearchDiscoveryPanel(onSearch: _submit),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        child: SizedBox(
          height: inline ? 58 : 52,
          child: Stack(
            children: [
              if (inline && widget.navigation != null)
                Positioned.fill(
                  left: toolWidth,
                  child: IgnorePointer(
                    ignoring: _open,
                    child: ExcludeFocus(
                      excluding: _open,
                      child: ExcludeSemantics(
                        excluding: _open,
                        child: TweenAnimationBuilder<double>(
                          duration: duration,
                          tween: Tween(end: _open ? 1 : 0),
                          builder: (context, value, child) => Opacity(
                            opacity: 1 - value,
                            child: ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: value * 5,
                                sigmaY: value * 5,
                              ),
                              child: child,
                            ),
                          ),
                          child: widget.navigation,
                        ),
                      ),
                    ),
                  ),
                ),
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeInOutCubic,
                left: inline && _open
                    ? (constraints.maxWidth - expandedWidth) / 2
                    : 0,
                width: inline && _open ? expandedWidth : toolWidth,
                top: 0,
                bottom: 0,
                child: tools,
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _collapsingTool(
    Widget child, {
    required bool inline,
    required Duration duration,
  }) => TweenAnimationBuilder<double>(
    duration: duration,
    tween: Tween(end: inline && _open ? 0 : 1),
    child: child,
    builder: (context, value, child) => ClipRect(
      child: Align(
        widthFactor: value,
        child: IgnorePointer(
          ignoring: inline && _open,
          child: ExcludeFocus(
            excluding: inline && _open,
            child: Opacity(opacity: value, child: child),
          ),
        ),
      ),
    ),
  );
}

final class _SearchPage extends StatefulWidget {
  const _SearchPage({required this.initialQuery, required this.onChanged});
  final String initialQuery;
  final ValueChanged<String> onChanged;
  @override
  State<_SearchPage> createState() => _SearchPageState();
}

final class _SearchPageState extends State<_SearchPage> {
  late final _text = TextEditingController(text: widget.initialQuery);
  @override
  void initState() {
    super.initState();
    _text.addListener(() => widget.onChanged(_text.text));
  }

  void _submit(String value) {
    if (value.trim().isNotEmpty) Navigator.of(context).pop(value.trim());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('search-discovery-page'),
    appBar: AppBar(
      leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      titleSpacing: 0,
      title: TextField(
        key: const ValueKey('search-page-input'),
        controller: _text,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: _submit,
        decoration: InputDecoration(
          hintText: '搜索视频、UP 主、番剧',
          suffixIcon: IconButton(
            tooltip: '清空输入',
            onPressed: _text.clear,
            icon: const Icon(Icons.close, size: 18),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _submit(_text.text),
          child: const Text('搜索'),
        ),
      ],
    ),
    body: SafeArea(top: false, child: SearchDiscoveryPanel(onSearch: _submit)),
  );
}
