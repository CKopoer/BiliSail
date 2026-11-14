import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Edits the ordered widths for two through twelve columns on one scale.
class VideoGridBreakpointEditor extends StatefulWidget {
  const VideoGridBreakpointEditor({
    super.key,
    required this.values,
    required this.onChanged,
  });

  final List<int> values;
  final ValueChanged<List<int>> onChanged;

  @override
  State<VideoGridBreakpointEditor> createState() =>
      _VideoGridBreakpointEditorState();
}

class _VideoGridBreakpointEditorState extends State<VideoGridBreakpointEditor> {
  static const _minimum = 200;
  static const _maximum = 12000;
  final _focus = FocusNode();
  late final _input = TextEditingController(
    text: '${widget.values[_selected]}',
  );
  var _selected = 2;
  var _rangeMaximum = 4000;
  var _focused = false;
  int? _dragging;

  int get _lower =>
      _selected == 0 ? _minimum : widget.values[_selected - 1] + 1;
  int get _upper =>
      _selected == 10 ? _maximum : widget.values[_selected + 1] - 1;

  @override
  void initState() {
    super.initState();
    _expandRange();
  }

  void _expandRange() {
    if (widget.values.last > _rangeMaximum) {
      _rangeMaximum = widget.values.last <= 6000 ? 6000 : _maximum;
    }
  }

  @override
  void didUpdateWidget(VideoGridBreakpointEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _expandRange();
    if (oldWidget.values[_selected] != widget.values[_selected] &&
        int.tryParse(_input.text) != widget.values[_selected]) {
      _input.text = '${widget.values[_selected]}';
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _input.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (_selected != index) {
      setState(() {
        _selected = index;
        _input.text = '${widget.values[index]}';
      });
    }
    _focus.requestFocus();
  }

  void _change(int value) {
    final next = value.clamp(_lower, _upper);
    if (next == widget.values[_selected]) return;
    widget.onChanged([...widget.values]..[_selected] = next);
  }

  double _position(int value, double width) =>
      12 + (value - _minimum) / (_rangeMaximum - _minimum) * (width - 24);

  int _nearest(double x, double width) {
    var index = _selected;
    var distance = (_position(widget.values[index], width) - x).abs();
    for (var i = 0; i < widget.values.length; i++) {
      final candidate = (_position(widget.values[i], width) - x).abs();
      if (candidate < distance) {
        index = i;
        distance = candidate;
      }
    }
    return index;
  }

  void _move(double x, double width) {
    final value =
        _minimum + (x - 12) / (width - 24) * (_rangeMaximum - _minimum);
    // Dragging uses ten-pixel steps. The input and arrow keys allow exact values.
    _change(((value / 10).round() * 10).clamp(_minimum, _rangeMaximum));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.grid_view_rounded, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('列数切换宽度', style: text.titleSmall)),
                DropdownButton<int>(
                  key: const ValueKey('video-grid-scale'),
                  value: _rangeMaximum,
                  isDense: true,
                  underline: const SizedBox(),
                  style: text.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  items: [
                    for (final maximum in [4000, 6000, 12000])
                      DropdownMenuItem(
                        value: maximum,
                        enabled: maximum >= widget.values.last,
                        child: Text('刻度 $maximum'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _rangeMaximum = value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            FocusableActionDetector(
              focusNode: _focus,
              onShowFocusHighlight: (value) => setState(() => _focused = value),
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.arrowLeft):
                    _AdjustBreakpoint(-1),
                SingleActivator(LogicalKeyboardKey.arrowRight):
                    _AdjustBreakpoint(1),
                SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
                    _AdjustBreakpoint(-10),
                SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
                    _AdjustBreakpoint(10),
              },
              actions: {
                _AdjustBreakpoint: CallbackAction<_AdjustBreakpoint>(
                  onInvoke: (intent) {
                    _change(widget.values[_selected] + intent.delta);
                    return null;
                  },
                ),
              },
              child: Semantics(
                excludeSemantics: true,
                label: '${_selected + 2} 列起阈值',
                value: '${widget.values[_selected]} 逻辑像素',
                increasedValue:
                    '${(widget.values[_selected] + 1).clamp(_lower, _upper)} 逻辑像素',
                decreasedValue:
                    '${(widget.values[_selected] - 1).clamp(_lower, _upper)} 逻辑像素',
                onIncrease: () => _change(widget.values[_selected] + 1),
                onDecrease: () => _change(widget.values[_selected] - 1),
                child: SizedBox(
                  height: 76,
                  child: LayoutBuilder(
                    builder: (context, bounds) {
                      final width = bounds.maxWidth;
                      return MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: GestureDetector(
                          key: const ValueKey('video-grid-multi-thumb-track'),
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) => _select(
                            _nearest(details.localPosition.dx, width),
                          ),
                          onTapUp: (details) =>
                              _move(details.localPosition.dx, width),
                          onHorizontalDragDown: (details) {
                            _dragging = _nearest(
                              details.localPosition.dx,
                              width,
                            );
                            _select(_dragging ?? _selected);
                          },
                          onHorizontalDragStart: (details) =>
                              _move(details.localPosition.dx, width),
                          onHorizontalDragUpdate: (details) =>
                              _move(details.localPosition.dx, width),
                          onHorizontalDragEnd: (_) => _dragging = null,
                          onHorizontalDragCancel: () => _dragging = null,
                          child: SizedBox(
                            height: 76,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _BreakpointPainter(
                                      positions: [
                                        for (final value in widget.values)
                                          _position(value, width),
                                      ],
                                      selected: _selected,
                                      colors: colors,
                                      focused: _focused,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left:
                                      (_position(
                                                widget.values[_selected],
                                                width,
                                              ) -
                                              28)
                                          .clamp(0.0, math.max(0, width - 56)),
                                  top: 0,
                                  child: IgnorePointer(
                                    child: Container(
                                      width: 56,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.primaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${widget.values[_selected]}',
                                        textAlign: TextAlign.center,
                                        style: text.labelMedium?.copyWith(
                                          color: colors.onPrimaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  bottom: 0,
                                  child: Text(
                                    '200',
                                    style: text.labelSmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Text(
                                    '$_rangeMaximum',
                                    style: text.labelSmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < widget.values.length; i++)
                  ChoiceChip(
                    key: ValueKey('video-grid-column-${i + 2}'),
                    label: Text('${i + 2} 列'),
                    selected: i == _selected,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _select(i),
                    tooltip: '${i + 2} 列：${widget.values[i]} 逻辑像素起',
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const ValueKey('video-grid-exact-width'),
              controller: _input,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '${_selected + 2} 列起的精确宽度',
                suffixText: '逻辑像素',
                helperText: '范围 $_lower–$_upper；滑块按从左到右递增',
                helperMaxLines: 2,
              ),
              onChanged: (text) {
                final value = int.tryParse(text);
                if (value != null && value >= _lower && value <= _upper) {
                  _change(value);
                }
              },
              validator: (text) {
                final value = int.tryParse(text ?? '');
                return value == null || value < _lower || value > _upper
                    ? '请输入 $_lower–$_upper 之间的整数'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            Text(
              '拖动滑块调整，也可先点选列数。方向键微调 1，Shift＋方向键调整 10。',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdjustBreakpoint extends Intent {
  const _AdjustBreakpoint(this.delta);
  final int delta;
}

class _BreakpointPainter extends CustomPainter {
  const _BreakpointPainter({
    required this.positions,
    required this.selected,
    required this.colors,
    required this.focused,
  });
  final List<double> positions;
  final int selected;
  final ColorScheme colors;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    const y = 43.0;
    final line = Paint()
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      const Offset(12, y),
      Offset(size.width - 12, y),
      line..color = colors.surfaceContainerHighest,
    );
    canvas.drawLine(
      Offset(selected == 0 ? 12 : positions[selected - 1], y),
      Offset(positions[selected], y),
      line..color = colors.primary,
    );
    for (var i = 0; i < positions.length; i++) {
      if (i == selected) continue;
      canvas.drawCircle(
        Offset(positions[i], y),
        5,
        Paint()..color = colors.surface,
      );
      canvas.drawCircle(
        Offset(positions[i], y),
        5,
        Paint()
          ..color = colors.primary.withValues(alpha: .65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    final center = Offset(positions[selected], y);
    canvas.drawCircle(
      center,
      focused ? 15 : 12,
      Paint()..color = colors.primary.withValues(alpha: .12),
    );
    canvas.drawCircle(center, 8, Paint()..color = colors.primary);
    canvas.drawCircle(center, 3, Paint()..color = colors.onPrimary);
  }

  @override
  bool shouldRepaint(_BreakpointPainter oldDelegate) =>
      positions != oldDelegate.positions ||
      selected != oldDelegate.selected ||
      colors != oldDelegate.colors ||
      focused != oldDelegate.focused;
}
