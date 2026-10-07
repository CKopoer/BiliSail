import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/system_font_picker.dart';
import '../../../shared/ui/danmaku_settings_controls.dart';
import '../../../shared/ui/player_controls_mode_setting.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../domain/playback_rates.dart';
import '../application/settings_controller.dart';
import '../application/app_update_controller.dart';
import '../domain/app_update.dart';
import '../domain/app_settings.dart';
import '../domain/settings_category.dart';
import 'shortcut_settings_section.dart';

const _usageNotice = <Widget>[
  Text('本应用是哔哩哔哩第三方客户端，视频、影视、直播及相关内容均来自哔哩哔哩，与官方无隶属关系。'),
  SizedBox(height: 8),
  Text('本程序仅供学习交流与编程技术研究使用。'),
  SizedBox(height: 8),
  Text('如果侵犯了您的合法权益，请及时联系开发者，我们会第一时间处理并删除相关内容。'),
];

final class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.category = SettingsCategory.appearance,
  });
  final SettingsCategory category;
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

final class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _save(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        showAppNotice(context, '设置保存失败，请重试');
      }
    }
  }

  Widget _toggle(
    String title,
    bool value,
    Future<void> Function(bool)? save, [
    String? description,
  ]) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: description == null ? null : Text(description),
    value: value,
    onChanged: save == null ? null : (v) => _save(() => save(v)),
  );
  Widget _choices<T>(
    String title,
    T value,
    Map<T, String> choices,
    Future<void> Function(T) save,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in choices.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: value == entry.key,
                onSelected: (_) => _save(() => save(entry.key)),
              ),
          ],
        ),
      ],
    ),
  );
  Widget _slider(
    String title,
    double value,
    double min,
    double max,
    Future<void> Function(double) save, [
    String suffix = '',
    bool continuous = false,
  ]) => _SettingSlider(
    title: title,
    value: value,
    min: min,
    max: max,
    suffix: suffix,
    continuous: continuous,
    save: (v) => _save(() => save(v)),
  );
  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final controller = ref.read(settingsControllerProvider.notifier);
    return ListView(
      key: PageStorageKey('settings-${widget.category.name}'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text('设置', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(widget.category.label),
        const SizedBox(height: 18),
        ref
            .watch(settingsControllerProvider)
            .when(
              loading: () => const StateView.loading(),
              error: (_, _) => StateView.error(
                message: '设置加载失败',
                onAction: () => ref.invalidate(settingsControllerProvider),
              ),
              data: (s) => Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.category == SettingsCategory.appearance)
                        _section('外观', [
                          _choices('页面导航模式', s.navigationMode, const {
                            WorkspaceNavigationMode.singlePage: '单标签页',
                            WorkspaceNavigationMode.multipleTabs: '多标签页',
                          }, controller.setNavigationMode),
                          const Text(
                            'Windows 和 macOS 默认多标签页，Android 默认单标签页。可手动切换；单标签页支持顶部返回按钮和系统返回。',
                            style: TextStyle(fontSize: 12),
                          ),
                          _choices('应用主题', s.theme, const {
                            AppThemePreference.system: '跟随系统',
                            AppThemePreference.light: '浅色',
                            AppThemePreference.dark: '深色',
                          }, controller.setTheme),
                          _choices('界面字体', s.font, const {
                            AppFontPreference.harmonyOsSans: 'HarmonyOS Sans',
                            AppFontPreference.alibabaPuHuiTi: '阿里巴巴普惠体 3.0',
                            AppFontPreference.system: '系统默认',
                          }, controller.setFont),
                          SystemFontPicker(
                            family: s.font == AppFontPreference.installed
                                ? s.systemFontFamily
                                : null,
                            onSelected: (family) =>
                                _save(() => controller.setSystemFont(family)),
                          ),
                          Text(
                            '字体预览：哔哩哔哩 BiliSail（哔帆） · Aa 0123456789',
                            style: TextStyle(fontFamily: s.fontFamily),
                          ),
                        ]),
                      if (widget.category == SettingsCategory.shortcuts)
                        _section('快捷键', [
                          ShortcutSettingsSection(
                            settings: s.shortcuts,
                            save: (value) => controller.setShortcuts(value),
                          ),
                        ]),
                      if (widget.category == SettingsCategory.cache)
                        _section('缓存', [
                          _toggle(
                            '缓存图片',
                            s.cacheImages,
                            controller.setCacheImages,
                            '共享封面和头像缓存，减少切换页面时的重复加载。关闭后停止读取和写入图片缓存，当前已显示的图片保留。',
                          ),
                        ]),
                      if (widget.category == SettingsCategory.playback)
                        _section('播放', [
                          PlayerControlsModeSetting(
                            value: s.playerControlsMode,
                            onChanged: (mode) => unawaited(
                              _save(
                                () => controller.setPlayerControlsMode(mode),
                              ),
                            ),
                          ),
                          _toggle(
                            '隐藏控件时显示底部进度条',
                            s.showCollapsedProgress,
                            controller.setShowCollapsedProgress,
                            '视频和影视播放时，在画面底部显示细进度条',
                          ),
                          _toggle(
                            '自动播放',
                            s.autoPlay,
                            controller.setAutoPlay,
                            '打开视频后开始播放',
                          ),
                          _toggle(
                            '允许多个标签页同时播放',
                            s.allowConcurrentPlayback,
                            s.navigationMode ==
                                    WorkspaceNavigationMode.multipleTabs
                                ? controller.setAllowConcurrentPlayback
                                : null,
                            '仅在多标签页模式下生效；关闭后切换播放标签会暂停其他标签',
                          ),
                          _toggle(
                            '记住播放进度',
                            s.resumePlayback,
                            controller.setResumePlayback,
                            '优先从本地记录继续观看，没有本地记录时使用云端进度',
                          ),
                          _choices('优先清晰度', s.preferredQuality, const {
                            16: '360P',
                            32: '480P',
                            64: '720P',
                            80: '1080P',
                            112: '1080P+',
                            116: '1080P 60',
                            120: '4K',
                            125: 'HDR',
                            126: '杜比视界',
                            127: '8K',
                          }, controller.setPreferredQuality),
                          const Text(
                            '按接口返回的可用清晰度选择；权限和片源限制仍适用',
                            style: TextStyle(fontSize: 12),
                          ),
                          _choices('默认播放倍速', s.defaultPlaybackRate, {
                            for (final rate in PlaybackRates.values)
                              rate: '${rate}x',
                          }, controller.setDefaultPlaybackRate),
                          const Text(
                            '启动时使用默认倍速；播放页修改后，本次运行中的后续视频继承修改后的倍速',
                            style: TextStyle(fontSize: 12),
                          ),
                          _slider(
                            '默认音量',
                            s.defaultVolume,
                            0,
                            100,
                            controller.setDefaultVolume,
                            '%',
                            true,
                          ),
                        ]),
                      if (widget.category == SettingsCategory.playback)
                        _section('CDN 线路', [
                          _choices('视频 CDN', s.mediaCdn, const {
                            MediaCdnPreference.automatic: '自动（默认）',
                            MediaCdnPreference.regular: '优先常规 CDN',
                            MediaCdnPreference.tencent: '优先腾讯云',
                            MediaCdnPreference.huawei: '优先华为云',
                            MediaCdnPreference.alibaba: '优先阿里云',
                            MediaCdnPreference.baidu: '优先百度云',
                          }, controller.setMediaCdn),
                          const Text(
                            '自动使用哔哩哔哩返回的线路，由系统或代理的 DNS 解析节点。其他选项优先选择接口提供的对应线路，连接失败时尝试备用地址。',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          const Text('适用于视频、影视和悬停预览，下次加载播放源时生效。'),
                        ]),
                      if (widget.category == SettingsCategory.playback)
                        _section('视频编解码', [
                          _choices('优先视频编码', s.preferredVideoCodec, const {
                            VideoCodecPreference.h264: 'H.264 / AVC（默认）',
                            VideoCodecPreference.hevc: 'H.265 / HEVC',
                            VideoCodecPreference.av1: 'AV1',
                          }, controller.setPreferredVideoCodec),
                          const Text(
                            '用于视频和影视：先选择可用清晰度，再优先使用所选编码。片源缺少首选编码时回退到其他可用编码；直播继续使用 H.264 线路。',
                            style: TextStyle(fontSize: 12),
                          ),
                          _choices('视频解码方式', s.videoDecoding, const {
                            VideoDecodingPreference.automatic: '自动（优先硬解）',
                            VideoDecodingPreference.software: '软件解码',
                          }, controller.setVideoDecoding),
                          const Text(
                            '自动模式在设备支持时使用硬件解码，不可用时使用软件解码。软件解码可能增加 CPU 占用和耗电。解码方式适用于视频、影视和直播。',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          const Text('下次打开或重新加载播放源时生效。'),
                        ]),
                      if (widget.category == SettingsCategory.danmaku)
                        _section('弹幕', [
                          DanmakuSettingsControls(
                            settings: s,
                            save: (change) async {
                              await controller.update(change);
                            },
                          ),
                        ]),
                      if (widget.category == SettingsCategory.subtitles)
                        _section('字幕', [
                          _toggle(
                            '默认显示字幕',
                            s.subtitlesEnabled,
                            controller.setSubtitlesEnabled,
                            '存在可用字幕时自动选择',
                          ),
                          _slider(
                            '字幕字号',
                            s.subtitleFontScale,
                            .5,
                            2,
                            controller.setSubtitleFontScale,
                            '×',
                          ),
                          _slider(
                            '字幕背景不透明度',
                            s.subtitleBackgroundOpacity,
                            0,
                            1,
                            controller.setSubtitleBackgroundOpacity,
                          ),
                          _slider(
                            '字幕底部距离',
                            s.subtitleBottomPadding,
                            0,
                            120,
                            controller.setSubtitleBottomPadding,
                            ' px',
                          ),
                        ]),
                      if (widget.category == SettingsCategory.sponsorBlock)
                        _section('空降助手', [
                          const Text(
                            '开启后向第三方 bsbsb.top 查询当前视频片段，不传账号。可手动提示或自动跳过所选类别。默认关闭。',
                          ),
                          _choices('工作模式', s.sponsorBlockMode, const {
                            SponsorBlockMode.disabled: '关闭',
                            SponsorBlockMode.manual: '手动提示',
                            SponsorBlockMode.automatic: '自动跳过',
                          }, controller.setSponsorBlockMode),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final entry in const {
                                'sponsor': '赞助广告',
                                'intro': '片头',
                                'outro': '片尾',
                                'selfpromo': '自我推广',
                                'interaction': '互动提醒',
                                'preview': '预告',
                              }.entries)
                                FilterChip(
                                  label: Text(entry.value),
                                  selected: s.sponsorBlockCategories.contains(
                                    entry.key,
                                  ),
                                  onSelected: (selected) => _save(
                                    () => controller.setSponsorBlockCategories(
                                      selected
                                          ? [
                                              ...s.sponsorBlockCategories,
                                              entry.key,
                                            ]
                                          : s.sponsorBlockCategories
                                                .where((v) => v != entry.key)
                                                .toList(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ]),
                      if (widget.category == SettingsCategory.about)
                        _section('关于', [
                          const _AboutSettingsContent(),
                          const SizedBox(height: 12),
                          ..._usageNotice,
                        ]),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

final class _AboutSettingsContent extends ConsumerWidget {
  const _AboutSettingsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(installedAppVersionProvider);
    final update = ref.watch(appUpdateControllerProvider);
    final controller = ref.read(appUpdateControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('一个专注观看体验的跨平台 Bilibili 第三方客户端'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('BiliSail（哔帆）'),
          subtitle: Text(
            version.value?.label ?? (version.hasError ? '版本信息暂不可用' : '正在读取版本…'),
          ),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'BiliSail（哔帆）',
            applicationVersion: version.value?.label ?? '',
            children: const [
              Text('一个专注观看体验的跨平台 Bilibili 第三方客户端'),
              SizedBox(height: 12),
              ..._usageNotice,
            ],
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('GitHub'),
          subtitle: Text(AppUpdateLinks.repository.toString()),
          trailing: const Icon(Icons.open_in_new),
          onTap: () async {
            final opened = await controller.openRepository();
            if (!opened && context.mounted) {
              showAppNotice(context, '无法打开浏览器，请复制 GitHub 地址访问');
            }
          },
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: update.checking
              ? null
              : () => unawaited(controller.checkManually()),
          icon: update.checking
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update_alt),
          label: Text(update.checking ? '正在检查更新…' : '检查更新'),
        ),
        const SizedBox(height: 8),
        const Text('每天首次打开应用时会自动检查更新。'),
        if (update.message case final message?) ...[
          const SizedBox(height: 8),
          Text(message),
        ],
      ],
    );
  }
}

final class _SettingSlider extends StatefulWidget {
  const _SettingSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.save,
    this.continuous = false,
  });
  final String title, suffix;
  final double value, min, max;
  final Future<void> Function(double) save;
  final bool continuous;
  @override
  State<_SettingSlider> createState() => _SettingSliderState();
}

final class _SettingSliderState extends State<_SettingSlider> {
  double? _draft;
  @override
  Widget build(BuildContext context) {
    final value = (_draft ?? widget.value).clamp(widget.min, widget.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.title} · ${value.toStringAsFixed(value < 4 ? 2 : 0)}${widget.suffix}',
        ),
        Slider(
          value: value,
          min: widget.min,
          max: widget.max,
          divisions: widget.continuous
              ? null
              : ((widget.max - widget.min) * (widget.max <= 3 ? 20 : 1))
                    .round(),
          onChanged: (v) => setState(() => _draft = v),
          onChangeEnd: (v) async {
            await widget.save(v);
            if (mounted) setState(() => _draft = null);
          },
        ),
      ],
    );
  }
}
