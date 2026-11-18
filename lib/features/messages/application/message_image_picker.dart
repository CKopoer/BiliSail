import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/message_composer.dart';

final messageImagePickerProvider =
    Provider<Future<MessageLocalImage?> Function({int? viewId})>(
      (ref) => throw UnimplementedError('Message image picker'),
    );
