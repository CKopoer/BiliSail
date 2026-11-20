import 'package:material_ui/material_ui.dart';

class ContentSearchField extends StatelessWidget {
  const ContentSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onSearch,
    this.focusNode,
    this.searchTooltip,
    this.prefixIcon,
    this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onSearch;
  final FocusNode? focusNode;
  final String? searchTooltip;
  final Widget? prefixIcon;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    final submit = IconButton(
      tooltip: searchTooltip ?? hintText,
      onPressed: () => onSearch(controller.text),
      icon: const Icon(Icons.search, size: 20),
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerLow,
        border: border,
        enabledBorder: border,
        prefixIcon: prefixIcon ?? const Icon(Icons.search, size: 18),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        suffixIcon: onClear == null
            ? submit
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '清除搜索',
                    onPressed: onClear,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                  submit,
                ],
              ),
      ),
      onSubmitted: onSearch,
    );
  }
}
