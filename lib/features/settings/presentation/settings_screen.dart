import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/page_tab_style.dart';
import '../../../shared/ui/paging_tab_strip.dart';
import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/retained_tab_view.dart';
import '../../../shared/ui/system_font_picker.dart';
import '../../../shared/ui/danmaku_settings_controls.dart';
import '../../../shared/ui/player_controls_mode_setting.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../domain/playback_rates.dart';
import '../application/settings_controller.dart';
import '../application/app_update_controller.dart';
import '../domain/app_update.dart';
import '../domain/app_settings.dart';
import '../domain/settings_category.dart';
import 'shortcut_settings_section.dart';
import 'recommendation_settings_section.dart';
import 'cdn_settings_tile.dart';

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
    this.onCategoryChanged,
  });
  final SettingsCategory category;
  final ValueChanged<SettingsCategory>? onCategoryChanged;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

final class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late SettingsCategory _category = widget.category;
  final _categoryPages = <SettingsCategory, Widget>{};
  bool _resetting = false;
  // The retained settings page must not own the home channel strip's progress.
  late final _progress = TabPagingProgress(widget.category.index.toDouble());

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) _category = widget.category;
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _selectCategory(SettingsCategory category) {
    final onChanged = widget.onCategoryChanged;
    if (onChanged == null) {
      setState(() => _category = category);
    } else {
      onChanged(category);
    }
  }

  Future<void> _resetSettings() async {
    setState(() => _resetting = true);
    try {
      final confirmed = await showAppDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('恢复默认设置'),
          content: const Text(
            '将所有应用设置（包括快捷键）恢复为当前平台的默认值，并立即保存。账号、观看记录和下载内容不受影响。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await ref.read(settingsControllerProvider.notifier).resetToDefaults();
      if (mounted) showAppNotice(context, '已恢复当前平台的默认设置');
    } catch (_) {
      if (mounted) showAppNotice(context, '恢复默认设置失败，请重试');
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.start,
            spacing: 12,
            overflowSpacing: 4,
            children: [
              Text(
                '设置',
                key: const ValueKey('settings-page-title'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextButton.icon(
                key: const ValueKey('reset-settings'),
                onPressed:
                    _resetting ||
                        !ref.watch(settingsControllerProvider).hasValue
                    ? null
                    : _resetSettings,
                icon: const Icon(Icons.restore),
                label: const Text('恢复默认设置'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: PageTabStyle.barHeight,
          child: ScrollConfiguration(
            behavior: const SmoothScrollBehavior(horizontalMouseWheel: true),
            child: SingleChildScrollView(
              key: const ValueKey('settings-category-strip'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: PagingTabStrip<SettingsCategory>(
                tabs: SettingsCategory.values,
                value: _category,
                progress: _progress,
                itemKey: (category) =>
                    ValueKey('settings-category-${category.name}'),
                buttonStyle: PageTabStyle.buttonStyle(context),
                labelBuilder: (context, category) =>
                    PageTabStyle.label(category.label),
                onSelected: _selectCategory,
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RetainedTabView<SettingsCategory>(
            tabs: SettingsCategory.values,
            value: _category,
            viewKey: const ValueKey('settings-category-swipe'),
            progress: _progress,
            onChanged: _selectCategory,
            // Categories read settings through their own Consumer. Navigation
            // changes the selection, not the retained form's configuration.
            pageBuilder: (context, category, active) =>
                _categoryPages.putIfAbsent(
                  category,
                  () => _SettingsCategoryPage(category: category),
                ),
          ),
        ),
      ],
    );
  }
}

final class _SettingsCategoryPage extends ConsumerStatefulWidget {
  const _SettingsCategoryPage({required this.category});
  final SettingsCategory category;
  @override
  ConsumerState<_SettingsCategoryPage> createState() =>
      _SettingsCategoryPageState();
}

final class _SettingsCategoryPageState
    extends ConsumerState<_SettingsCategoryPage> {
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
    bool enabled = true,
  ]) => _SettingSlider(
    title: title,
    value: value,
    min: min,
    max: max,
    suffix: suffix,
    continuous: continuous,
    enabled: enabled,
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
                            WorkspaceNavigationMode.dualTabs: '双标签页',
                            WorkspaceNavigationMode.multipleTabs: '多标签页',
                          }, controller.setNavigationMode),
                          const Text(
                            'Android 默认单标签页，按访问顺序返回；从播放页进入 UP 主空间等页面后，返回原播放页并保留状态。其他平台默认双标签页：Windows 和 macOS 使用独立播放窗口；Android 在应用内切换浏览与播放页面。多标签页可分别保留多个页面。切换模式保留未关闭页面。macOS 切换到双标签页模式后，需要重启应用。',
                            style: TextStyle(fontSize: 12),
                          ),
                          _choices('导航栏模式', s.navigationBarMode, const {
                            NavigationBarMode.automatic: '自动',
                            NavigationBarMode.bottom: '底栏',
                            NavigationBarMode.sidebar: '侧边栏',
                          }, controller.setNavigationBarMode),
                          const Text(
                            '自动模式根据窗口宽度切换底栏和侧边栏；也可固定使用底栏或侧边栏。',
                            style: TextStyle(fontSize: 12),
                          ),
                          _choices('侧栏样式', s.sidebarStyle, const {
                            SidebarStyle.automatic: '随窗口宽度',
                            SidebarStyle.expanded: '完整侧栏',
                            SidebarStyle.compact: '图标文字上下',
                          }, controller.setSidebarStyle),
                          const Text(
                            '使用侧边栏时生效；随窗口宽度模式在 1600 起展开。可用左上角按钮完全收起或展开，保留当前页面和侧栏样式。',
                            style: TextStyle(fontSize: 12),
                          ),
                          _choices('应用主题', s.theme, const {
                            AppThemePreference.system: '跟随系统',
                            AppThemePreference.light: '浅色',
                            AppThemePreference.dark: '深色',
                          }, controller.setTheme),
                          _choices('界面字体', s.font, const {
                            AppFontPreference.harmonyOsSans: 'HarmonyOS Sans',
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
                          const SizedBox(height: 20),
                          _slider(
                            '滚轮阻尼比',
                            s.wheelDampingRatio,
                            .5,
                            2,
                            controller.setWheelDampingRatio,
                          ),
                          const Text(
                            '用于桌面鼠标滚轮，释放滑块后生效，默认 1.30。小于 1 更有弹性，大于 1 收尾更缓和。',
                            style: TextStyle(fontSize: 12),
                          ),
                          TextButton(
                            key: const ValueKey('reset-wheel-damping-ratio'),
                            onPressed: s.wheelDampingRatio == 1.3
                                ? null
                                : () => _save(
                                    () => controller.setWheelDampingRatio(1.3),
                                  ),
                            child: const Text('恢复默认阻尼比'),
                          ),
                        ]),
                      if (widget.category == SettingsCategory.shortcuts)
                        _section('快捷键', [
                          ShortcutSettingsSection(
                            settings: s.shortcuts,
                            save: (value) => controller.setShortcuts(value),
                          ),
                        ]),
                      if (widget.category == SettingsCategory.recommendation)
                        _section('推荐流设置', [
                          RecommendationSettingsSection(
                            settings: s.recommendations,
                            save: (change) => controller.update(
                              (current) => current.copyWith(
                                recommendations: change(
                                  current.recommendations,
                                ),
                              ),
                            ),
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
                          _toggle(
                            '滑动调节亮度和音量',
                            s.fullscreenSwipeControls,
                            controller.setFullscreenSwipeControls,
                            '普通和全屏画面均可用，触摸左侧上下滑动调亮度，右侧调音量',
                          ),
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
                            '进入播放页默认显示评论区',
                            s.defaultShowComments,
                            controller.setDefaultShowComments,
                            '打开视频或影视时优先显示评论区；关闭时默认显示简介',
                          ),
                          _toggle(
                            '自动播放',
                            s.autoPlay,
                            controller.setAutoPlay,
                            '打开视频后开始播放',
                          ),
                          _toggle(
                            '视频卡悬停播放',
                            s.videoCardHoverPlayback,
                            controller.setVideoCardHoverPlayback,
                            '鼠标停留在视频卡上时静音播放预览，关闭可减少资源和流量占用',
                          ),
                          _toggle(
                            '高能进度条',
                            s.highEnergyProgressEnabled,
                            controller.setHighEnergyProgressEnabled,
                            '显示视频热度曲线；有章节时优先显示章节',
                          ),
                          _toggle(
                            '连续播放',
                            s.continuousPlayback,
                            controller.setContinuousPlayback,
                            '播放完毕后自动播放下一 P、合集中下一个视频或影视下一集；到末尾停止',
                          ),
                          _toggle(
                            '连续播放相关视频',
                            s.continuousRelatedPlayback,
                            controller.setContinuousRelatedPlayback,
                            '当前视频的分 P／合集播完后继续播放相关视频；稍后再看、播放队列和影视仍在末尾停止',
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
                          _choices('视频默认清晰度', s.preferredQuality, const {
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
                          _choices(
                            '直播默认清晰度',
                            s.preferredLiveQuality,
                            AppSettings.liveQualityOptions,
                            controller.setPreferredLiveQuality,
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('直播流偏好'),
                            subtitle: Text(
                              '${s.liveStreamPreference.label}；可在直播播放页选择并记住组合',
                            ),
                            trailing: s.liveStreamPreference.isAutomatic
                                ? null
                                : TextButton(
                                    onPressed: () => _save(
                                      () => controller.setLiveStreamPreference(
                                        LiveStreamPreference.automatic,
                                      ),
                                    ),
                                    child: const Text('恢复自动'),
                                  ),
                          ),
                          const Text(
                            '用于新打开的直播间；自动由服务端选择清晰度，权限和直播源限制仍适用。当前直播间的手动选择保持不变。',
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
                          _toggle(
                            '全局音量记忆',
                            s.rememberVolumeGlobally,
                            controller.setRememberVolumeGlobally,
                            '开启后忽略默认音量，记住最近使用的音量，重启应用后继续使用',
                          ),
                          _slider(
                            '默认音量',
                            s.defaultVolume,
                            0,
                            100,
                            controller.setDefaultVolume,
                            '%',
                            true,
                            !s.rememberVolumeGlobally,
                          ),
                          Text(
                            s.rememberVolumeGlobally
                                ? '全局音量记忆已开启，默认音量暂不生效；关闭后，应用下次启动使用默认音量'
                                : '启动时使用默认音量；播放页修改后，本次运行中的后续播放继承修改后的音量',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ]),
                      if (widget.category == SettingsCategory.playback)
                        _section('CDN 线路', [
                          CdnSettingsTile(preference: s.mediaCdn),
                          const Text(
                            '自动沿用接口调度；运营商偏好优先使用返回线路，也可选择具体 CDN 节点。连接失败时尝试原始备用地址。',
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
                            VideoCodecPreference.dolbyVision: '杜比视界 / dvh1',
                          }, controller.setPreferredVideoCodec),
                          const Text(
                            '用于视频和影视：先选择可用清晰度，再选择编码。直播在播放页独立选择协议、格式与编码；杜比实际显示效果取决于设备和输出。',
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
                          _choices('优先音质', s.preferredAudioQuality, {
                            for (final quality in AudioQualityPreference.values)
                              quality: quality.label,
                          }, controller.setPreferredAudioQuality),
                          const Text(
                            '适用于视频和影视；优先所选音质，缺少时回退到普通 AAC。下次加载播放源时生效。',
                          ),
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
                            240,
                            controller.setSubtitleBottomPadding,
                            ' px',
                          ),
                        ]),
                      if (widget.category == SettingsCategory.sponsorBlock)
                        _section('空降助手', [
                          const Text(
                            '开启后向第三方 bsbsb.top 查询当前视频片段，不传账号。默认手动提示并选中全部类别，也可关闭或改为自动跳过。',
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
                          _toggle(
                            '检查预发布更新',
                            s.checkPrereleaseUpdates,
                            controller.setCheckPrereleaseUpdates,
                            '开启后，手动和自动检查更新都会包含预发布版本（pre-release）。',
                          ),
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
        const Text('每天首次打开应用时会自动检查更新，同一版本仅自动提醒一次（不区分构建号）。'),
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
    this.enabled = true,
  });
  final String title, suffix;
  final double value, min, max;
  final Future<void> Function(double) save;
  final bool continuous;
  final bool enabled;
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
          onChanged: widget.enabled ? (v) => setState(() => _draft = v) : null,
          onChangeEnd: widget.enabled
              ? (v) async {
                  await widget.save(v);
                  if (mounted) setState(() => _draft = null);
                }
              : null,
        ),
      ],
    );
  }
}
