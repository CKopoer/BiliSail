import '../../../core/platform/local_image_picker.dart';
import '../domain/comment_composer.dart';

import 'package:image_picker/image_picker.dart';

Future<List<CommentLocalImage>> pickCommentImages(
  int remaining, {
  ImagePicker? imagePicker,
}) async => [
  for (final image in await pickLocalImages(
    remaining,
    imagePicker: imagePicker,
    label: '评论图片',
  ))
    CommentLocalImage(image.bytes, image.mimeType),
];
