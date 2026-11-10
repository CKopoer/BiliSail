import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/local_image.dart';
import 'app_notice.dart';
import 'dynamic_publish_forms.dart';

/// Local preview and rectangular cropping; GIFs remain animated and unchanged.
class DynamicImageEditor extends StatefulWidget {
  const DynamicImageEditor({super.key, required this.image});
  final LocalImage image;
  @override
  State<DynamicImageEditor> createState() => _DynamicImageEditorState();
}

class _DynamicImageEditorState extends State<DynamicImageEditor> {
  bool _crop = false, _busy = false;
  Rect _selection = const Rect.fromLTWH(.1, .1, .8, .8);
  Offset? _start;
  double _ratio = 1;
  @override
  void initState() {
    super.initState();
    _dimensions();
  }

  Future<void> _dimensions() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(widget.image.bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (mounted) {
        setState(() => _ratio = descriptor!.width / descriptor.height);
      }
    } catch (_) {
      // Preview's error builder keeps the original available for removal.
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    ui.Codec? codec;
    ui.Image? source, cropped;
    ui.Picture? picture;
    try {
      codec = await ui.instantiateImageCodec(widget.image.bytes);
      source = (await codec.getNextFrame()).image;
      final rect = Rect.fromLTRB(
        (_selection.left * source.width).roundToDouble(),
        (_selection.top * source.height).roundToDouble(),
        (_selection.right * source.width).roundToDouble(),
        (_selection.bottom * source.height).roundToDouble(),
      );
      final width = rect.width.round().clamp(1, source.width),
          height = rect.height.round().clamp(1, source.height);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        source,
        rect,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint(),
      );
      picture = recorder.endRecording();
      cropped = await picture.toImage(width, height);
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      if (data == null || data.lengthInBytes > LocalImage.maxBytes) {
        showAppNotice(context, '裁剪后的图片超过10 MB，请选择更小的区域');
        return;
      }
      Navigator.pop(
        context,
        LocalImage(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          'image/png',
        ),
      );
    } catch (_) {
      if (mounted) showAppNotice(context, '无法裁剪这张图片，原图已保留');
    } finally {
      source?.dispose();
      cropped?.dispose();
      picture?.dispose();
      codec?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: DynamicFormDialog(
      title: '图片预览',
      canClose: !_busy,
      body: Column(
        children: [
          Expanded(
            child: _crop
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final size = applyBoxFit(
                        BoxFit.contain,
                        Size(_ratio, 1),
                        constraints.biggest,
                      ).destination;
                      return Center(
                        child: SizedBox(
                          width: size.width,
                          height: size.height,
                          child: LayoutBuilder(
                            builder: (context, box) => GestureDetector(
                              key: const ValueKey('dynamic-crop-surface'),
                              onPanStart: (d) => _start = Offset(
                                (d.localPosition.dx / box.maxWidth).clamp(0, 1),
                                (d.localPosition.dy / box.maxHeight).clamp(
                                  0,
                                  1,
                                ),
                              ),
                              onPanUpdate: (d) {
                                final start = _start;
                                if (start == null) return;
                                final end = Offset(
                                  (d.localPosition.dx / box.maxWidth).clamp(
                                    0,
                                    1,
                                  ),
                                  (d.localPosition.dy / box.maxHeight).clamp(
                                    0,
                                    1,
                                  ),
                                );
                                final rect = Rect.fromPoints(start, end);
                                if (rect.width >= .02 && rect.height >= .02) {
                                  setState(() => _selection = rect);
                                }
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(
                                    widget.image.bytes,
                                    fit: BoxFit.fill,
                                    cacheWidth: 1000,
                                  ),
                                  CustomPaint(
                                    painter: _CropPainter(_selection),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : InteractiveViewer(
                    minScale: .5,
                    maxScale: 5,
                    child: Center(
                      child: Image.memory(
                        widget.image.bytes,
                        fit: BoxFit.contain,
                        cacheWidth: 1600,
                        errorBuilder: (_, _, _) => const Text('图片无法预览'),
                      ),
                    ),
                  ),
          ),
          if (_crop)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('拖动选择需要保留的区域'),
            ),
        ],
      ),
      actions: [
        if (widget.image.mimeType != 'image/gif')
          TextButton.icon(
            onPressed: _busy ? null : () => setState(() => _crop = !_crop),
            icon: const Icon(Icons.crop),
            label: Text(_crop ? '取消裁剪' : '裁剪'),
          ),
        if (_crop)
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? '处理中…' : '应用裁剪'),
          ),
      ],
    ),
  );
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.selection);
  final Rect selection;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      selection.left * size.width,
      selection.top * size.height,
      selection.right * size.width,
      selection.bottom * size.height,
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(rect),
      Paint()..color = Colors.black54,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.selection != selection;
}
