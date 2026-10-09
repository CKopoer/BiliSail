import 'package:flutter/material.dart';

import '../../features/settings/domain/app_settings.dart';

class PlayerControlsModeSetting extends StatelessWidget {
  const PlayerControlsModeSetting({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PlayerControlsMode value;
  final ValueChanged<PlayerControlsMode> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('播放器控件交互'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in PlayerControlsMode.values)
              ChoiceChip(
                label: Text(mode == PlayerControlsMode.click ? '点击' : '动态'),
                selected: value == mode,
                onSelected: (_) => onChanged(mode),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value == PlayerControlsMode.click
              ? '点击画面切换控件显示与隐藏，鼠标在播放器内移动或操作控件后重新计时，静止 5 秒自动淡出。悬停在控件上、拖动、输入或打开菜单时保持显示，结束后重新计时。'
              : '鼠标移入或移动时淡入控件，静止 2.5 秒或移出画面时淡出。悬停在控件上时保持显示，移开控件后重新计时。点击视频画面播放／暂停；点击直播画面不暂停，也不切换控件。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
