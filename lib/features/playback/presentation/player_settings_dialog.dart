import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/playback_rates.dart';
import '../../../shared/ui/danmaku_settings_controls.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/app_settings.dart';

Future<void> showPlayerSettings(BuildContext context, {int tab = 0}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _PlayerSettingsDialog(tab: tab),
    );

class _PlayerSettingsDialog extends ConsumerStatefulWidget {
  const _PlayerSettingsDialog({required this.tab});
  final int tab;
  @override
  ConsumerState<_PlayerSettingsDialog> createState() =>
      _PlayerSettingsDialogState();
}

class _PlayerSettingsDialogState extends ConsumerState<_PlayerSettingsDialog> {
  String? _error;
  Future<void> _update(AppSettings Function(AppSettings) change) async {
    try {
      await ref.read(settingsControllerProvider.notifier).update(change);
      if (mounted && _error != null) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = '设置保存失败，请重试');
    }
  }

  Widget _switch(
    String label,
    bool value,
    AppSettings Function(AppSettings, bool) change,
  ) => SwitchListTile(
    title: Text(label),
    value: value,
    onChanged: (value) =>
        unawaited(_update((current) => change(current, value))),
  );
  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    AppSettings Function(AppSettings, double) change, {
    String? suffix,
    Key? key,
    int? divisions,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text('$label  ${suffix ?? value.toStringAsFixed(2)}'),
      ),
      Slider(
        key: key,
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: (value) =>
            unawaited(_update((current) => change(current, value))),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider).asData?.value;
    if (settings == null) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final s = settings;
    return DefaultTabController(
      length: 4,
      initialIndex: widget.tab,
      child: Dialog(
        child: SizedBox(
          width: 540,
          height: 570,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('播放器设置', style: TextStyle(fontSize: 18)),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: '播放'),
                  Tab(text: '弹幕'),
                  Tab(text: '字幕'),
                  Tab(text: '空降助手'),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView(
                      children: [
                        _switch(
                          '自动播放新视频',
                          s.autoPlay,
                          (c, v) => c.copyWith(autoPlay: v),
                        ),
                        _switch(
                          '隐藏控件时显示底部进度条',
                          s.showCollapsedProgress,
                          (c, v) => c.copyWith(showCollapsedProgress: v),
                        ),
                        _switch(
                          '记住播放进度（本地优先，云端补充）',
                          s.resumePlayback,
                          (c, v) => c.copyWith(resumePlayback: v),
                        ),
                        ListTile(
                          title: const Text('默认清晰度'),
                          subtitle: DropdownButton<int>(
                            isExpanded: true,
                            value: s.preferredQuality,
                            items: [
                              for (final q in AppSettings.supportedQualities)
                                DropdownMenuItem(
                                  value: q,
                                  child: Text(qualityLabel(q)),
                                ),
                            ],
                            onChanged: (q) {
                              if (q != null) {
                                unawaited(
                                  _update(
                                    (c) => c.copyWith(preferredQuality: q),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        ListTile(
                          title: const Text('默认倍速'),
                          subtitle: DropdownButton<double>(
                            isExpanded: true,
                            value: s.defaultPlaybackRate,
                            items: [
                              for (final rate in PlaybackRates.values)
                                DropdownMenuItem(
                                  value: rate,
                                  child: Text('${rate}x'),
                                ),
                            ],
                            onChanged: (rate) {
                              if (rate != null) {
                                unawaited(
                                  _update(
                                    (c) =>
                                        c.copyWith(defaultPlaybackRate: rate),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        _slider(
                          '音量',
                          s.defaultVolume,
                          0,
                          100,
                          (c, v) => c.copyWith(defaultVolume: v),
                          suffix: '${s.defaultVolume.round()}%',
                        ),
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('默认清晰度、自动播放和续播用于新视频；倍速与音量也会应用到当前播放。'),
                        ),
                      ],
                    ),
                    ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        DanmakuSettingsControls(
                          settings: s,
                          save: (change) async {
                            await ref
                                .read(settingsControllerProvider.notifier)
                                .update(change);
                          },
                        ),
                      ],
                    ),
                    ListView(
                      children: [
                        _switch(
                          '默认开启字幕',
                          s.subtitlesEnabled,
                          (c, v) => c.copyWith(subtitlesEnabled: v),
                        ),
                        _slider(
                          '字幕字号',
                          s.subtitleFontScale,
                          .5,
                          2,
                          (c, v) => c.copyWith(subtitleFontScale: v),
                        ),
                        _slider(
                          '背景透明度',
                          s.subtitleBackgroundOpacity,
                          0,
                          1,
                          (c, v) => c.copyWith(subtitleBackgroundOpacity: v),
                        ),
                        _slider(
                          '底部距离',
                          s.subtitleBottomPadding,
                          0,
                          120,
                          (c, v) => c.copyWith(subtitleBottomPadding: v),
                          suffix: '${s.subtitleBottomPadding.round()} px',
                        ),
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('有可用字幕时自动选择第一条；控制栏可切换语言或关闭。'),
                        ),
                      ],
                    ),
                    ListView(
                      children: [
                        ListTile(
                          title: const Text('跳过方式'),
                          subtitle: DropdownButton<SponsorBlockMode>(
                            isExpanded: true,
                            value: s.sponsorBlockMode,
                            items: const [
                              DropdownMenuItem(
                                value: SponsorBlockMode.disabled,
                                child: Text('关闭'),
                              ),
                              DropdownMenuItem(
                                value: SponsorBlockMode.manual,
                                child: Text('提示并手动跳过'),
                              ),
                              DropdownMenuItem(
                                value: SponsorBlockMode.automatic,
                                child: Text('自动跳过'),
                              ),
                            ],
                            onChanged: (mode) {
                              if (mode != null) {
                                unawaited(
                                  _update(
                                    (c) => c.copyWith(sponsorBlockMode: mode),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        for (final category
                            in AppSettings.supportedSponsorCategories)
                          CheckboxListTile(
                            title: Text(sponsorLabel(category)),
                            value: s.sponsorBlockCategories.contains(category),
                            onChanged: (enabled) => unawaited(
                              _update(
                                (c) => c.copyWith(
                                  sponsorBlockCategories: enabled == true
                                      ? {
                                          ...c.sponsorBlockCategories,
                                          category,
                                        }.toList()
                                      : c.sponsorBlockCategories
                                            .where((v) => v != category)
                                            .toList(),
                                ),
                              ),
                            ),
                          ),
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            '开启后向 bsbsb.top 查询当前 BV / CID 的社区片段。不会传递账号 Cookie，不上报跳过次数，也不提交片段。手动回看已跳过片段时不会反复自动跳过。',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String sponsorLabel(String category) => switch (category) {
  'sponsor' => '赞助广告',
  'intro' => '片头',
  'outro' => '片尾',
  'selfpromo' => '自我推广',
  'interaction' => '互动提醒',
  'preview' => '预告',
  _ => category,
};
String qualityLabel(int q) => switch (q) {
  16 => '360P',
  32 => '480P',
  64 => '720P',
  80 => '1080P',
  112 => '1080P+',
  116 => '1080P60',
  120 => '4K',
  125 => 'HDR',
  126 => '杜比视界',
  127 => '8K',
  _ => '$q',
};
