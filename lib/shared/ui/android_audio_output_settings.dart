import 'package:bili_player/android_audio_output.dart';
import 'package:material_ui/material_ui.dart';

class AndroidAudioOutputSettings extends StatelessWidget {
  const AndroidAudioOutputSettings({
    super.key,
    required this.value,
    required this.onDriver,
    required this.onMode,
  });

  final AndroidAudioOutput value;
  final ValueChanged<AndroidAudioDriver> onDriver;
  final ValueChanged<OpenSlPerformanceMode> onMode;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _choice(
        '音频输出',
        value.driver,
        AndroidAudioDriver.values,
        (d) => d.label,
        switch (value.driver) {
          AndroidAudioDriver.auto => '依次尝试 OpenSL ES、AAudio、AudioTrack。',
          AndroidAudioDriver.opensles => '固定使用 OpenSL ES，可调整下方性能模式。',
          AndroidAudioDriver.aaudio => '固定使用 Android 原生 AAudio 输出。',
          AndroidAudioDriver.audiotrack => '固定使用系统 AudioTrack 输出。',
        },
        onDriver,
      ),
      _choice(
        'OpenSL ES 性能模式',
        value.mode,
        OpenSlPerformanceMode.values,
        (m) => m.label,
        value.driver.mayUseOpenSl
            ? switch (value.mode) {
                OpenSlPerformanceMode.latency => '优先低延迟，系统音效可能受限。',
                OpenSlPerformanceMode.none => '允许设备音效，外放低频偏少时可尝试。',
                OpenSlPerformanceMode.latencyEffects => '兼顾低延迟和系统音效，取决于设备支持。',
                OpenSlPerformanceMode.powerSaving => '优先省电，允许系统音效。',
              }
            : '仅在实际使用 OpenSL ES 时生效。',
        value.driver.mayUseOpenSl ? onMode : null,
      ),
    ],
  );

  Widget _choice<T>(
    String title,
    T value,
    List<T> values,
    String Function(T) label,
    String hint,
    ValueChanged<T>? change,
  ) => ListTile(
    title: Text(title),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<T>(
          isExpanded: true,
          value: value,
          items: [
            for (final item in values)
              DropdownMenuItem(value: item, child: Text(label(item))),
          ],
          onChanged: change == null
              ? null
              : (item) {
                  if (item != null) change(item);
                },
        ),
        Text(hint),
      ],
    ),
  );
}
