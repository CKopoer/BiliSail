import 'dart:convert';
import 'dart:io';

import 'package:bilisail/features/playback/application/casting_controller.dart';
import 'package:bilisail/features/playback/data/dlna_cast_repository.dart';
import 'package:bilisail/features/playback/domain/casting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import '../../support/casting_fakes.dart';

void main() {
  for (final request in [
    const CastMediaRequest(aid: '170001', cid: '99', quality: 80),
    const CastMediaRequest(episodeId: '123', cid: '789', quality: 80),
    const CastMediaRequest.live(roomId: '42', quality: 400),
  ]) {
    test(
      'advertised Nirvana service still receives a playable URL by default: ${request.isLive ? 'live' : request.episodeId ?? 'UGC'}',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final devices = DlnaCastRepository();
        final media = FakeCastMedia();
        final source = ValueNotifier(0);
        var localPauses = 0;
        final actions = <String>[];
        Uri? televisionUri;
        String? metadata;
        var televisionCanLoad = false;
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
          }
          if (action == 'Play') {
            // A successful SOAP response only acknowledges the command. It does
            // not prove the TV can subsequently load an identity-only URI.
            televisionCanLoad = const [
              'http',
              'https',
            ].contains(televisionUri?.scheme);
          }
          message.response.write('<Envelope><${action}Response/></Envelope>');
          await message.response.close();
        });

        await controller.connect(device);

        expect(
          televisionUri.toString(),
          'https://cdn.example/video.mp4?sign=fixture',
        );
        expect(televisionCanLoad, isTrue);
        expect(media.receiversResolve, [false]);
        expect(metadata, isNot(contains('longDescription')));
        expect(actions, ['SetAVTransportURI', 'Play']);
        expect(localPauses, 1);
        expect(controller.message, isNull);
      },
    );
  }
}
