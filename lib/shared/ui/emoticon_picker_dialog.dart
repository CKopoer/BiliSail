import 'package:flutter/material.dart';

/// Shared presentation only; each caller owns loading and selecting its items.
final class EmoticonPickerDialog extends StatelessWidget {
  const EmoticonPickerDialog({
    super.key,
    required this.title,
    required this.loading,
    required this.packageNames,
    required this.packageBuilder,
    required this.emptyMessage,
    required this.onRetry,
    this.message,
    this.hint,
  });

  final String title, emptyMessage;
  final bool loading;
  final List<String> packageNames;
  final IndexedWidgetBuilder packageBuilder;
  final VoidCallback onRetry;
  final String? message, hint;

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: Text(title),
    contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    content: SizedBox(
      width: 480,
      height: 360,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : message != null
          ? Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message ?? '', textAlign: TextAlign.center),
                    TextButton(onPressed: onRetry, child: const Text('重试')),
                  ],
                ),
              ),
            )
          : packageNames.isEmpty
          ? Center(child: Text(emptyMessage, textAlign: TextAlign.center))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hint case final hint?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      hint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Expanded(
                  child: _PackageTabs(
                    names: packageNames,
                    packageBuilder: packageBuilder,
                  ),
                ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}

final class _PackageTabs extends StatefulWidget {
  const _PackageTabs({required this.names, required this.packageBuilder});
  final List<String> names;
  final IndexedWidgetBuilder packageBuilder;

  @override
  State<_PackageTabs> createState() => _PackageTabsState();
}

final class _PackageTabsState extends State<_PackageTabs>
    with TickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: widget.names.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _PackageTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.names.length != widget.names.length) {
      final index = _tabs.index.clamp(0, widget.names.length - 1);
      _tabs.dispose();
      _tabs = TabController(
        length: widget.names.length,
        initialIndex: index,
        vsync: this,
      );
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          for (final name in widget.names)
            Tab(
              child: Tooltip(
                message: name,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Expanded(
        child: AnimatedBuilder(
          animation: _tabs,
          builder: (context, _) => KeyedSubtree(
            key: ValueKey(_tabs.index),
            child: widget.packageBuilder(context, _tabs.index),
          ),
        ),
      ),
    ],
  );
}
