import 'package:material_ui/material_ui.dart';

const desktopCaptionHeight = 44.0;
const desktopCaptionTextStyle = TextStyle(fontSize: 13);
const desktopCaptionButtonStyle = ButtonStyle(
  fixedSize: WidgetStatePropertyAll(Size(46, desktopCaptionHeight)),
  padding: WidgetStatePropertyAll(EdgeInsets.zero),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.standard,
  shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
);

class DesktopCaptionButton extends StatelessWidget {
  const DesktopCaptionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.close = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool close;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    style: close
        ? desktopCaptionButtonStyle.copyWith(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.hovered)
                  ? const Color(0xffc42b1c)
                  : null,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.hovered) ? Colors.white : null,
            ),
          )
        : desktopCaptionButtonStyle,
  );
}
