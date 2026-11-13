import 'dart:convert';
import 'dart:io';

import 'package:bilisail/features/playback/application/casting_controller.dart';
import 'package:bilisail/features/playback/data/dlna_cast_repository.dart';
import 'package:bilisail/features/playback/domain/casting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import '../../support/bilibili_cast_projection.dart';
import '../../support/casting_fakes.dart';

void main() {
  for (final request in [
    const CastMediaRequest(
      aid: '170001',
      cid: '99',
      quality: 80,
      position: Duration(seconds: 37),
      danmakuEnabled: false,
    ),
    const CastMediaRequest(
      episodeId: '123',
      seasonId: '456',
      cid: '789',
      quality: 80,
      position: Duration(seconds: 83),
    ),
    const CastMediaRequest.live(roomId: '42', quality: 400),
  ]) {
    for (final enhanced in [false, true]) {
      test('${enhanced ? '1.8.9 receiver resolves identity with initial danmaku and seek' : 'advertised Nirvana service still receives a playable URL by default'}: ${request.isLive ? 'live' : request.episodeId ?? 'UGC'}', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final devices = DlnaCastRepository();
        final media = FakeCastMedia();
        final source = ValueNotifier(0);
        var localPauses = 0;
        final actions = <String>[];
        Uri? televisionUri;
        String? metadata;
        var televisionCanLoad = false;
        var televisionInitialDanmaku = false;
        var televisionPosition = 0;
        Map<String, Object?>? projection;
        final controller = CastingController(
          request: request,
          title: '云视听兼容回归',
          mediaRepository: media,
          deviceRepository: devices,
          source: source,
          isCurrent: () => true,
          pauseLocal: () async {
            localPauses++;
          },
          trackLifetime: (_) => () {},
        );
        addTearDown(() async {
          controller.dispose();
          source.dispose();
          await server.close(force: true);
        });
        final device = DlnaCastRepository.parseDescription(
          '''
<root><device>
<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
<friendlyName>我的小电视</friendlyName><UDN>uuid:tv</UDN>
<serviceList>
<service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><controlURL>/av</controlURL></service>
<service><serviceType>urn:app-bilibili-com:service:NirvanaControl:3</serviceType><controlURL>/nirvana</controlURL></service>
</serviceList></device></root>''',
          Uri.parse('http://127.0.0.1:${server.port}/device.xml'),
        ).single;
        server.listen((message) async {
          final xml = XmlDocument.parse(
            await utf8.decoder.bind(message).join(),
          );
          final action = message.headers
              .value('soapaction')!
              .split('#')
              .last
              .replaceAll('"', '');
          actions.add(action);
          String value(String name) => xml.descendants
              .whereType<XmlElement>()
              .singleWhere((node) => node.name.local == name)
              .innerText;
          if (action == 'SetAVTransportURI') {
            televisionUri = Uri.parse(value('CurrentURI'));
            metadata = value('CurrentURIMetaData');
            final descriptions = XmlDocument.parse(metadata!).descendants
                .whereType<XmlElement>()
                .where((node) => node.name.local == 'longDescription');
            if (descriptions.isNotEmpty) {
              projection = decodeCastProjection(descriptions.single.innerText);
            }
          }
          if (action == 'Play') {
            // A successful SOAP response only acknowledges the command. It does
            // not prove the TV can subsequently load an identity-only URI. The
            // 1.8.9 receiver requires autoNext for its content-resolution path;
            // otherwise bilibili://projection becomes an empty direct URL.
            final content = projection;
            final autoNext = content?['autoNext'] ?? content?['an'];
            final canResolveContent =
                content != null &&
                autoNext == true &&
                ((content['aid'] as int? ?? 0) > 0 ||
                    (content['seasonId'] as int? ??
                            content['sid'] as int? ??
                            0) >
                        0 ||
                    (content['ct'] == 3 &&
                        (content['roomId'] as int? ?? 0) > 0));
            televisionCanLoad =
                const ['http', 'https'].contains(televisionUri?.scheme) ||
                canResolveContent;
            if (canResolveContent) {
              televisionInitialDanmaku =
                  (content['isOpen'] ?? content['io']) == true;
              final version = content['mobileVersion'] ?? content['mv'] ?? 0;
              final seek = num.parse(
                '${content['seekTs'] ?? content['sk'] ?? 0}',
              );
              televisionPosition = (version as int) < 6240000
                  ? seek ~/ 1000
                  : seek.toInt();
            }
          }
          message.response.write('<Envelope><${action}Response/></Envelope>');
          await message.response.close();
        });

        controller.setTelevisionDanmaku(enhanced);
        await controller.connect(device);

        expect(
          televisionCanLoad,
          isTrue,
          reason: 'An identity-only URI without autoNext produces an empty media resource in 1.8.9',
        );
        expect(media.receiversResolve, [enhanced]);
        if (enhanced) {
          expect(televisionUri?.scheme, 'bilibili');
          expect(televisionPosition, request.position.inSeconds);
          expect(
            televisionInitialDanmaku,
            request.danmakuEnabled,
            reason: 'danmakuSwitchSave does not set the initial isOpen state',
          );
          expect(actions, ['SetAVTransportURI', 'Play', 'SetDanmakuSwitch']);
        } else {
          expect(
            televisionUri.toString(),
            'https://cdn.example/video.mp4?sign=fixture',
          );
          expect(metadata, isNot(contains('longDescription')));
          expect(actions, ['SetAVTransportURI', 'Play']);
        }
        expect(localPauses, 1);
        expect(controller.message, isNull);
      });
    }
  }
}
