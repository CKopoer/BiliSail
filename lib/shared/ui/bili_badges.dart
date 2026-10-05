import 'package:flutter/widgets.dart';

class BiliLevelBadge extends StatelessWidget {
  const BiliLevelBadge({super.key, required this.level, this.size = 22});
  final int level;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '等级 $level',
    child: Image.asset(
      'assets/icons/lv${level.clamp(0, 6)}.png',
      width: size,
      height: size / 2,
      fit: BoxFit.contain,
    ),
  );
}

class BiliVerifyBadge extends StatelessWidget {
  const BiliVerifyBadge({super.key, required this.type, this.size = 16});
  final int type;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (type != 0 && type != 1) return const SizedBox.shrink();
    return Semantics(
      label: type == 0 ? '个人认证' : '机构认证',
      child: Image.asset(
        'assets/icons/verify$type.png',
        width: size,
        height: size,
      ),
    );
  }
}

class BiliUpBadge extends StatelessWidget {
  const BiliUpBadge({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'UP主',
    child: Image.asset(
      'assets/icons/up.png',
      width: size,
      height: size / 2,
      fit: BoxFit.contain,
    ),
  );
}
