import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../../domain/app_failure.dart';
import '../domain/casting.dart';

/// Bilibili's UPnP extension identifies the content so the receiver can fetch
/// its own streams and danmaku. This fixed protocol key is not account security.
/// Wire format reviewed against NeoBV's MIT NvaExtDecoder; see dlna-casting.md.
String encodeBilibiliCastProjection(CastMedia media) {
  final request = media.request;
  int? id(String? value) => value == null ? null : int.tryParse(value);
  final roomId = id(media.roomId ?? request.roomId);
  final aid = id(media.aid ?? request.aid);
  final cid = id(request.cid);
  final episodeId = id(request.episodeId);
  final seasonId = id(request.seasonId);
  if ((request.isLive
          ? roomId == null || roomId <= 0
          : cid == null || cid <= 0 || (episodeId ?? aid ?? 0) <= 0) ||
      request.quality < 0 ||
      request.position.isNegative ||
      !request.speed.isFinite ||
      request.speed <= 0) {
    throw const AppFailure(AppFailureKind.protocol, '当前内容缺少有效的 B站投屏信息');
  }
  final contentType = request.isLive ? 3 : (episodeId == null ? 0 : 1);
  final position = request.isLive ? 0 : request.position.inSeconds;
  final payload = <String, Object>{
    'aid': aid ?? 0,
    'cid': cid ?? 0,
    'oid': request.isLive ? roomId! : (episodeId ?? aid!),
    'eid': episodeId ?? 0,
    'sid': seasonId ?? 0,
    'ct': contentType,
    'epId': episodeId ?? 0,
    'seasonId': seasonId ?? 0,
    if (request.isLive) 'roomId': roomId!,
    'sk': '$position',
    'seekTs': position,
    'qn': request.quality,
    'userDesireQn': request.quality,
    'userDesireSpeed': request.speed,
    'danmakuSwitchSave': request.danmakuEnabled,
    'proj_type': 1,
    // Credentials are deliberately absent; the TV uses its own account.
  };
  final compressed = ZLibEncoder(raw: true)
      .convert(utf8.encode(jsonEncode(payload)));
  final key = Uint8List.fromList(utf8.encode('1pzhA828t4i.6Oq@'));
  final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
    ..init(
      true,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), key),
        null,
      ),
    );
  return base64Url
      .encode(cipher.process(Uint8List.fromList(compressed)))
      .replaceAll('=', '');
}
