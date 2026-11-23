import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../shared/ui/app_dialog.dart';

/// User-hosted PGC resolver endpoints. No account credential controls live here.
final class PgcResolverSettingsSection extends StatelessWidget {
  const PgcResolverSettingsSection({
    super.key,
    required this.enabled,
    required this.servers,
    required this.defaultRegion,
    required this.onEnabledChanged,
    required this.onServerChanged,
    required this.onDefaultRegionChanged,
  });

  final bool enabled;
  final Map<String, String> servers;
  final String defaultRegion;
  final Future<void> Function(bool enabled) onEnabledChanged;
  final Future<void> Function(String region, String value) onServerChanged;
  final Future<void> Function(String region) onDefaultRegionChanged;

  static const _labels = {
    'hk': '香港／澳门',
    'tw': '台湾',
    'sea': '东南亚',
    'cn': '中国大陆',
  };

  @override
  Widget build(BuildContext context) {
    final configured = servers.values.where((url) => url.isNotEmpty).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('番剧地区解锁'),
          subtitle: Text(
            enabled
                ? '已配置 $configured 个地区；详情或播放被地区拒绝时回退到自建服务器'
                : '需要自行准备兼容 BBZQ 的解析服务器，默认不发送账号凭据',
          ),
          value: enabled,
          onChanged: (value) => unawaited(onEnabledChanged(value)),
        ),
        if (enabled) ...[
          for (final region in _labels.keys)
            ListTile(
              key: ValueKey('pgc-resolver-$region'),
              contentPadding: EdgeInsets.zero,
              title: Text(_labels[region]!),
              subtitle: Text(
                servers[region]?.isNotEmpty == true ? servers[region]! : '未配置',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => unawaited(_editServer(context, region)),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('默认解析地区'),
            subtitle: const Text('优先询问该地区；失败后按港澳、台湾、东南亚、大陆顺序继续'),
            trailing: DropdownButton<String>(
              key: const ValueKey('pgc-resolver-default-region'),
              value: defaultRegion,
              items: [
                const DropdownMenuItem(value: '', child: Text('自动')),
                for (final region in _labels.keys)
                  DropdownMenuItem(
                    value: region,
                    child: Text(_labels[region]!),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  unawaited(onDefaultRegionChanged(value));
                }
              },
            ),
          ),
          const Text(
            '仅官方详情或取流被拒绝时尝试解析。账号 Cookie 与访问密钥默认不发送；'
            '搜索合并、字幕补源和番剧下载不在本次接入范围。',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ],
    );
  }

  Future<void> _editServer(BuildContext context, String region) async {
    final form = GlobalKey<FormState>();
    var next = servers[region] ?? '';
    var saving = false;
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('${_labels[region]}解析服务器'),
          content: Form(
            key: form,
            child: TextFormField(
              initialValue: next,
              enabled: !saving,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://resolver.example.com',
                helperText: '留空可停用该地区；支持 HTTP/HTTPS，不包含账号信息',
              ),
              onChanged: (value) => next = value,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return null;
                final uri = Uri.tryParse(text);
                final valid =
                    uri != null &&
                    const {'http', 'https'}.contains(uri.scheme) &&
                    uri.host.isNotEmpty &&
                    uri.userInfo.isEmpty &&
                    !uri.hasQuery &&
                    !uri.hasFragment;
                return valid ? null : '请输入有效的 HTTP/HTTPS 服务器地址';
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (form.currentState?.validate() != true) return;
                      setState(() => saving = true);
                      try {
                        await onServerChanged(region, next.trim());
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (_) {
                        if (dialogContext.mounted) {
                          setState(() => saving = false);
                        }
                      }
                    },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
