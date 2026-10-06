import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/application/system_fonts_controller.dart';

final class SystemFontPicker extends ConsumerWidget {
  const SystemFontPicker({
    super.key,
    required this.family,
    required this.onSelected,
  });
  final String? family;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(systemFontCatalogProvider).supported) {
      return const Text('此平台暂不提供已安装字体列表，可使用内置字体或系统默认');
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(family == null ? '选择系统字体' : '系统字体：$family'),
      subtitle: const Text('从已安装字体中搜索并预览'),
      trailing: const Icon(Icons.font_download_outlined),
      onTap: () async {
        final selected = await showDialog<String>(
          context: context,
          builder: (_) => _SystemFontDialog(selected: family),
        );
        if (context.mounted && selected != null) onSelected(selected);
      },
    );
  }
}

final class _SystemFontDialog extends ConsumerStatefulWidget {
  const _SystemFontDialog({required this.selected});
  final String? selected;
  @override
  ConsumerState<_SystemFontDialog> createState() => _SystemFontDialogState();
}

final class _SystemFontDialogState extends ConsumerState<_SystemFontDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择系统字体'),
    content: SizedBox(
      width: 520,
      height: 440,
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: '搜索字体',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value.toLowerCase()),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ref
                .watch(systemFontFamiliesProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Center(child: Text('读取系统字体失败，请刷新重试')),
                  data: (families) {
                    final matches = families
                        .where(
                          (name) => name.toLowerCase().contains(_query.trim()),
                        )
                        .toList();
                    return Column(
                      children: [
                        if (widget.selected != null &&
                            !families.contains(widget.selected))
                          const Text('已选字体当前不可用，文字由系统回退显示；可重新选择'),
                        Expanded(
                          child: matches.isEmpty
                              ? const Center(child: Text('没有匹配的系统字体'))
                              : ListView.builder(
                                  itemCount: matches.length,
                                  itemBuilder: (context, index) {
                                    final family = matches[index];
                                    return ListTile(
                                      title: Text(family),
                                      subtitle: Text(
                                        '哔帆 BiliSail · Aa 0123456789',
                                        style: TextStyle(fontFamily: family),
                                      ),
                                      trailing: family == widget.selected
                                          ? const Icon(Icons.check)
                                          : null,
                                      onTap: () =>
                                          Navigator.pop(context, family),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => ref.invalidate(systemFontFamiliesProvider),
        child: const Text('刷新字体列表'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  );
}
