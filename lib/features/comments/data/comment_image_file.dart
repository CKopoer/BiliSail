import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String?> saveCommentImageFile(Uint8List png) async {
  final name = 'BiliSail-comment-${DateTime.now().microsecondsSinceEpoch}.png';
  if (Platform.isLinux) {
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );
    if (location == null) return null;
    await XFile.fromData(png, mimeType: 'image/png').saveTo(location.path);
    return location.path;
  }
  final documents = await getApplicationDocumentsDirectory();
  final directory = Directory(p.join(documents.path, 'BiliSail', '评论'));
  await directory.create(recursive: true);
  final file = File(p.join(directory.path, name));
  final temp = await File('${file.path}.partial').create(exclusive: true);
  try {
    await temp.writeAsBytes(png, flush: true);
    await temp.rename(file.path);
    return file.path;
  } finally {
    if (await temp.exists()) await temp.delete();
  }
}
