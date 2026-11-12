import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui/app_notice.dart';
import '../application/playback_information_controller.dart';
import '../application/playback_session.dart';

class PlayerInformationTab extends StatefulWidget {
  const PlayerInformationTab({super.key, this.session});

  final PlaybackSession? session;

  @override
  State<PlayerInformationTab> createState() => _PlayerInformationTabState();
}

class _PlayerInformationTabState extends State<PlayerInformationTab>
    with WidgetsBindingObserver {
  PlaybackInformationController? _information;
  TabController? _tabs;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = switch (WidgetsBinding.instance.lifecycleState) {
      null || AppLifecycleState.resumed => true,
      _ => false,
    };
    _bindSession();
  }

  void _bindSession() {
    final session = widget.session;
    _information = session == null
        ? null
        : PlaybackInformationController(session);
  }

  @override
  void didUpdateWidget(PlayerInformationTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _information?.dispose();
      _bindSession();
      _updateSampling();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabs = DefaultTabController.maybeOf(context);
    if (_tabs != tabs) {
      _tabs?.removeListener(_updateSampling);
      _tabs = tabs;
      _tabs?.addListener(_updateSampling);
    }
    _updateSampling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateSampling();
  }

  void _updateSampling() {
    if (_foreground && (_tabs == null || _tabs?.index == 4)) {
      _information?.start();
    } else {
      _information?.stop();
    }
  }

  Future<void> _copyInformation(String text) async {
    var message = '播放信息已复制';
    try {
      await Clipboard.setData(ClipboardData(text: text))
          .timeout(const Duration(seconds: 3));
    } on PlatformException {
      message = '复制失败，请重试';
    } on MissingPluginException {
      message = '复制失败，请重试';
    } on TimeoutException {
      message = '复制失败，请重试';
    }
    if (mounted) showAppNotice(context, message);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabs?.removeListener(_updateSampling);
    _information?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final information = _information;
    if (information == null) return const Center(child: Text('当前没有播放会话'));
    return ValueListenableBuilder<PlaybackInformation?>(
      valueListenable: information,
      builder: (context, info, _) {
        if (info == null) return const Center(child: Text('等待播放信息…'));
        final snapshot = info.snapshot;
        final native = info.native;
        final diagnostics = native?.diagnostics;
        final dimensions = snapshot.videoDimensions;
        final bufferAhead = snapshot.buffered - snapshot.position;
        final summary = info.hasSource ? '约每秒刷新 · 未提供的参数显示为 —' : '当前没有已加载的媒体';
        const notes =
            '帧率为播放器估算值；缓存速度不是总网速。音画差为音频时钟减视频时钟，正值表示音频领先。丢帧计数随媒体源重建而重置。';
        final sections = <(String, List<(String, String)>)>[
          (
            '播放状态',
            [
              ('播放后端', native?.backend ?? '—'),
              ('状态', _phase(snapshot.phase)),
              ('播放意图', snapshot.desiredPlaying ? '播放' : '暂停'),
              ('媒体类型', info.sourceType),
              ('播放模式', info.audioOnly ? '听视频' : '音视频'),
              ('当前清晰度', info.quality),
              ('播放位置', _time(snapshot.position)),
              ('媒体时长', info.isLive ? '直播' : _time(snapshot.duration)),
              ('播放倍速', '${snapshot.rate.toStringAsFixed(2)}×'),
              ('播放器音量', '${snapshot.volume.toStringAsFixed(0)}%'),
              (
                '缓冲 / 跳转',
                '${_yes(snapshot.isBuffering)} / ${_yes(snapshot.isSeeking)}',
              ),
            ],
          ),
          (
            '视频与输出',
            [
              (
                '视频编码',
                native?.videoCodec ??
                    diagnostics?.videoCodec ??
                    info.videoCodec ??
                    '—',
              ),
              (
                '实际硬解',
                switch (native?.hardwareDecoder) {
                  'no' => '软件解码',
                  final decoder? => decoder,
                  null => '—',
                },
              ),
              (
                '解码尺寸',
                _dimensions(diagnostics?.videoWidth, diagnostics?.videoHeight),
              ),
              ('显示尺寸', _dimensions(dimensions?.width, dimensions?.height)),
              (
                '输出尺寸',
                _dimensions(
                  diagnostics?.outputWidth,
                  diagnostics?.outputHeight,
                ),
              ),
              ('源帧率', _number(native?.sourceFps, ' fps')),
              ('滤镜输出帧率（估算）', _number(native?.outputFps, ' fps')),
              ('视频码率（实时）', _bitrate(native?.videoBitrate)),
              (
                '视频码率（标称）',
                _nominalBitrate(
                  info.videoBandwidth,
                  native?.videoNominalBitrate,
                ),
              ),
              ('像素格式', native?.pixelFormat ?? '—'),
              ('硬解底层像素格式', native?.hardwarePixelFormat ?? '—'),
              ('色彩矩阵', native?.colorMatrix ?? '—'),
              ('色彩范围', native?.colorLevels ?? '—'),
              ('色域原色', native?.colorPrimaries ?? '—'),
              ('传递函数', native?.transferFunction ?? '—'),
              ('视频输出', native?.videoOutput ?? '—'),
              (
                '视频已解码 / 已输出',
                '${_optionalYes(diagnostics?.hasDecodedVideo)} / ${_optionalYes(diagnostics?.hasVideoOutput)}',
              ),
            ],
          ),
          (
            '音频',
            [
              (
                '音频编码',
                native?.audioCodec ??
                    diagnostics?.audioCodec ??
                    info.audioCodec ??
                    '—',
              ),
              ('音频码率（实时）', _bitrate(native?.audioBitrate)),
              (
                '音频码率（标称）',
                _nominalBitrate(
                  info.audioBandwidth,
                  native?.audioNominalBitrate,
                ),
              ),
              (
                '采样率',
                diagnostics?.audioSampleRate == null
                    ? '—'
                    : '${diagnostics?.audioSampleRate} Hz',
              ),
              ('声道数', diagnostics?.audioChannels?.toString() ?? '—'),
              ('均衡增益', _number(native?.audioGainDb, ' dB')),
              ('音频输出', native?.audioOutput ?? '—'),
              ('音频已解码', _optionalYes(diagnostics?.hasDecodedAudio)),
            ],
          ),
          (
            '缓存与同步',
            [
              ('缓冲至', _time(snapshot.buffered)),
              (
                '前向缓冲（播放进度）',
                _time(
                  bufferAhead < Duration.zero ? Duration.zero : bufferAhead,
                ),
              ),
              ('原生缓存时长', _number(native?.cacheSeconds, ' s')),
              ('前向缓存大小', _bytes(native?.cacheBytes?.toDouble())),
              (
                '缓存读取速度',
                native?.cacheSpeed == null
                    ? '—'
                    : '${_bytes(native?.cacheSpeed)}/s',
              ),
              (
                '音画差（A−V）',
                _number(switch (native?.avSyncSeconds) {
                  final seconds? => seconds * 1000,
                  null => null,
                }, ' ms'),
              ),
              ('音频时钟', _number(native?.audioPositionSeconds, ' s')),
              ('视频时钟', _number(native?.videoPositionSeconds, ' s')),
              ('输出丢帧（累计）', native?.frameDrops?.toString() ?? '—'),
              ('解码丢帧（累计）', native?.decoderDrops?.toString() ?? '—'),
            ],
          ),
        ];
        final text = [
          '实时播放信息',
          summary,
          for (final (title, rows) in sections) ...[
            '',
            title,
            for (final (label, value) in rows) '$label：$value',
          ],
          '',
          notes,
        ].join('\n');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(summary, style: Theme.of(context).textTheme.bodySmall),
                  TextButton.icon(
                    onPressed: () => _copyInformation(text),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('复制全部信息'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: const PageStorageKey('player-information-scroll'),
                padding: const EdgeInsets.all(16),
                children: [
                  for (final (title, rows) in sections)
                    _section(context, title, rows),
                  Text(notes, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<(String, String)> rows,
  ) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final labelWidget = Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                );
                final valueWidget = Text(value, softWrap: true);
                if (constraints.maxWidth < 300) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      labelWidget,
                      const SizedBox(height: 2),
                      valueWidget,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 170, child: labelWidget),
                    Expanded(child: valueWidget),
                  ],
                );
              },
            ),
          ),
      ],
    ),
  );
}

String _yes(bool value) => value ? '是' : '否';
String _optionalYes(bool? value) => value == null ? '—' : _yes(value);
String _number(double? value, String unit) =>
    value == null || !value.isFinite ? '—' : '${value.toStringAsFixed(2)}$unit';
String _dimensions(int? width, int? height) =>
    width == null || height == null || width <= 0 || height <= 0
    ? '—'
    : '$width × $height';
String _time(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 1 << 53);
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(seconds ~/ 3600)}:${pad(seconds ~/ 60 % 60)}:${pad(seconds % 60)}';
}

String _nominalBitrate(int? bandwidth, double? native) => _bitrate(
  bandwidth != null && bandwidth > 0 ? bandwidth.toDouble() : native,
);
String _bitrate(double? value) => value == null || value <= 0
    ? '—'
    : value >= 1000000
    ? _number(value / 1000000, ' Mbps')
    : _number(value / 1000, ' kbps');
String _bytes(double? value) => value == null || !value.isFinite
    ? '—'
    : value >= 1048576
    ? _number(value / 1048576, ' MiB')
    : _number(value / 1024, ' KiB');
String _phase(PlaybackPhase phase) => switch (phase) {
  PlaybackPhase.idle => '空闲',
  PlaybackPhase.opening => '加载中',
  PlaybackPhase.ready => '就绪',
  PlaybackPhase.playing => '播放中',
  PlaybackPhase.paused => '已暂停',
  PlaybackPhase.buffering => '缓冲中',
  PlaybackPhase.ended => '已结束',
  PlaybackPhase.failed => '播放失败',
  PlaybackPhase.disposed => '已关闭',
};
