import 'package:flutter/widgets.dart';

/// Keeps small layout results across lazy card disposal, without retaining UI.
final class TextMeasurementCacheScope extends StatefulWidget {
  const TextMeasurementCacheScope({super.key, required this.child});

  final Widget child;

  static TextMeasurementCache? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_TextMeasurementCacheScope>()
      ?.cache;

  @override
  State<TextMeasurementCacheScope> createState() =>
      _TextMeasurementCacheScopeState();
}

final class _TextMeasurementCacheScopeState
    extends State<TextMeasurementCacheScope> {
  final _cache = TextMeasurementCache();

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_cache.clear);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_cache.clear);
    _cache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _TextMeasurementCacheScope(cache: _cache, child: widget.child);
}

final class _TextMeasurementCacheScope extends InheritedWidget {
  const _TextMeasurementCacheScope({required this.cache, required super.child});

  final TextMeasurementCache cache;

  @override
  bool updateShouldNotify(_TextMeasurementCacheScope oldWidget) =>
      cache != oldWidget.cache;
}

/// Each grid owns at most 512 widths and 512 overflow flags. Keys must contain
/// every layout input; values never hold painters, paragraphs, images or widgets.
final class TextMeasurementCache {
  static const maximumEntries = 512;
  final _widths = <Object, double>{};
  final _overflows = <Object, bool>{};

  double width(Object key, double Function() measure) =>
      _read(_widths, key, measure);

  bool overflows(Object key, bool Function() measure) =>
      _read(_overflows, key, measure);

  T _read<T extends Object>(
    Map<Object, T> entries,
    Object key,
    T Function() measure,
  ) {
    final cached = entries.remove(key);
    if (cached != null) {
      entries[key] = cached;
      return cached;
    }
    final value = measure();
    if (entries.length == maximumEntries) entries.remove(entries.keys.first);
    entries[key] = value;
    return value;
  }

  void clear() {
    _widths.clear();
    _overflows.clear();
  }
}
