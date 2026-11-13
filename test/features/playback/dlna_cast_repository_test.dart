import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/playback/data/dlna_cast_repository.dart';
import 'package:bilisail/features/playback/domain/casting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:xml/xml.dart';

String _description({
  String base = '',
  String control = '/control',
  String type = 'MediaRenderer',
  String? bilibiliControl,
}) =>
    '''
<root xmlns="urn:schemas-upnp-org:device-1-0">$base<device>
<deviceType>urn:schemas-upnp-org:device:$type:1</deviceType>
<friendlyName>客厅 &amp; 电视</friendlyName><UDN>uuid:fixture-tv</UDN>
<serviceList><service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
<controlURL>$control</controlURL></service>
${bilibiliControl == null ? '' : '<service><serviceType>urn:app-bilibili-com:service:NirvanaControl:3</serviceType><controlURL>$bilibiliControl</controlURL></service>'}
</serviceList></device></root>''';

void main() {
  test('TV danmaku switch uses advertised Nirvana endpoint and excludes InstanceID', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final repository = DlnaCastRepository();
    addTearDown(() async {
      repository.dispose();
      await server.close(force: true);
    });
    final device = DlnaCastRepository.parseDescription(
      _description(bilibiliControl: '/bilibili/nirvana'),
      Uri.parse('http://127.0.0.1:${server.port}/device.xml'),
    ).single;
    final switches = <String>[];
    server.listen((request) async {
      expect(request.uri.path, '/bilibili/nirvana');
      expect(
        request.headers.value('soapaction'),
        '"urn:app-bilibili-com:service:NirvanaControl:3#SetDanmakuSwitch"',
      );
      final xml = XmlDocument.parse(await utf8.decoder.bind(request).join());
      final elements = xml.descendants.whereType<XmlElement>();
      expect(elements.where((e) => e.name.local == 'InstanceID'), isEmpty);
      switches.add(
        elements.singleWhere((e) => e.name.local == 'DesiredSwitch').innerText,
      );
      request.response.write(
        '<Envelope><SetDanmakuSwitchResponse/></Envelope>',
      );
      await request.response.close();
    });
    for (final enabled in [true, false]) {
      await repository.setDanmaku(
        device,
        enabled,
        cancellation: RequestCancellation(),
      );
    }
    expect(switches, ['1', '0']);
  });

  test(
    'Bilibili capability requires an advertised service on the same host',
    () {
      final location = Uri.parse('http://192.168.1.2:9958/bilibili/device.xml');
      final capable = DlnaCastRepository.parseDescription(
        _description(bilibiliControl: 'NirvanaControl/action'),
        location,
      ).single;
      expect(
        capable.bilibiliService?.controlUri.toString(),
        'http://192.168.1.2:9958/bilibili/NirvanaControl/action',
      );
      for (final control in [
        null,
        'http://other.example/nirvana',
        'file:///nirvana',
        '',
      ]) {
        final ordinary = DlnaCastRepository.parseDescription(
          _description(bilibiliControl: control),
          location,
        ).single;
        expect(ordinary.bilibiliService, isNull);
      }
    },
  );

  for (final request in [
    const CastMediaRequest(
      aid: '170001',
      cid: '99',
      quality: 80,
      position: Duration(seconds: 37),
      speed: 1.5,
      danmakuEnabled: false,
    ),
    const CastMediaRequest(
      episodeId: '123',
      seasonId: '456',
      cid: '789',
      quality: 80,
    ),
    const CastMediaRequest.live(roomId: '42', quality: 400),
  ]) {
    test(
      'Bilibili handoff identifies ${request.isLive ? 'live' : request.episodeId ?? 'UGC'} without credentials',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final repository = DlnaCastRepository();
        addTearDown(() async {
          repository.dispose();
          await server.close(force: true);
        });
        final device = DlnaCastRepository.parseDescription(
          _description(bilibiliControl: '/nirvana'),
          Uri.parse('http://127.0.0.1:${server.port}/device.xml'),
        ).single;
        final bodies = <String>[];
        server.listen((message) async {
          expect(message.headers.value('cookie'), isNull);
          expect(message.headers.value('authorization'), isNull);
          bodies.add(await utf8.decoder.bind(message).join());
          message.response.write(
            '<Envelope><SetAVTransportURIResponse/></Envelope>',
          );
          await message.response.close();
        });
        await repository.setMedia(
          device,
          CastMedia(request: request),
          '测试 <电视> & 弹幕',
          cancellation: RequestCancellation(),
        );
        final body = XmlDocument.parse(bodies.single);
        String value(XmlDocument xml, String name) => xml.descendants
            .whereType<XmlElement>()
            .singleWhere((n) => n.name.local == name)
            .innerText;
        expect(
          value(body, 'CurrentURI'),
          'bilibili://projection?proj_source=bilibili&_nva_ext_=',
        );
        final metadata = XmlDocument.parse(value(body, 'CurrentURIMetaData'));
        expect(value(metadata, 'title'), '测试 <电视> & 弹幕');
        final payload = _decodeProjection(value(metadata, 'longDescription'));
        expect(
          payload['cid'],
          request.cid == null ? 0 : int.parse(request.cid!),
        );
        expect(
          payload['aid'],
          request.aid == null ? 0 : int.parse(request.aid!),
        );
        expect(
          payload['eid'],
          request.episodeId == null ? 0 : int.parse(request.episodeId!),
        );
        expect(
          payload['sid'],
          request.seasonId == null ? 0 : int.parse(request.seasonId!),
        );
        expect(payload['roomId'], request.isLive ? 42 : null);
        expect(
          payload['ct'],
          request.isLive
              ? 3
              : request.episodeId == null
              ? 0
              : 1,
        );
        expect(payload['seekTs'], request.position.inSeconds);
        expect(payload['userDesireQn'], request.quality);
        expect(payload['userDesireSpeed'], request.speed);
        expect(payload['danmakuSwitchSave'], request.danmakuEnabled);
        expect(payload.keys, isNot(anyElement(contains('key'))));
        expect(payload.keys, isNot(anyElement(contains('token'))));
        expect(bodies, hasLength(1));
      },
    );
  }
  test(
    'description resolves relative control URL and rejects foreign endpoints',
    () {
      final location = Uri.parse(
        'http://192.168.1.2:8000/description/device.xml',
      );
      final result = DlnaCastRepository.parseDescription(
        _description(control: '../control'),
        location,
      );
      expect(result.single.name, '客厅 & 电视');
      expect(
        result.single.controlUri.toString(),
        'http://192.168.1.2:8000/control',
      );
      for (final xml in [
        _description(control: 'http://other.example/control'),
        _description(base: '<URLBase>http://other.example/</URLBase>'),
        _description(type: 'MediaServer'),
        '<malformed>',
      ]) {
        expect(DlnaCastRepository.parseDescription(xml, location), isEmpty);
      }
    },
  );
  test('real UDP discovery deduplicates responses and stops at its deadline', () async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final repository = DlnaCastRepository(
      searchDuration: const Duration(milliseconds: 350),
      discoveryAddress: InternetAddress.loopbackIPv4,
      discoveryPort: udp.port,
    );
    addTearDown(() async {
      repository.dispose();
      udp.close();
      await http.close(force: true);
    });
    http.listen((request) async {
      request.response.write(_description());
      await request.response.close();
    });
    udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = udp.receive();
      if (packet == null) return;
      udp.send(
        ascii.encode(
          'HTTP/1.1 200 OK\r\nLOCATION: http://127.0.0.1:${http.port}/device.xml\r\n\r\n',
        ),
        packet.address,
        packet.port,
      );
    });
    final devices = await repository
        .discover(cancellation: RequestCancellation())
        .toList()
        .timeout(const Duration(seconds: 3));
    expect(devices.map((device) => device.id), ['uuid:fixture-tv']);
  });
  test('SOAP preserves signed URL and Unicode title with no credentials or replay', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final repository = DlnaCastRepository();
    addTearDown(() async {
      repository.dispose();
      await server.close(force: true);
    });
    final device = CastDevice(
      id: 'tv',
      name: '电视',
      controlUri: Uri.parse('http://127.0.0.1:${server.port}/control'),
      serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
    );
    final actions = <String>[], bodies = <String>[];
    var fail = false;
    server.listen((request) async {
      expect(request.headers.value('cookie'), isNull);
      expect(request.headers.value('authorization'), isNull);
      final action = request.headers
          .value('soapaction')!
          .split('#')
          .last
          .replaceAll('"', '');
      actions.add(action);
      bodies.add(await utf8.decoder.bind(request).join());
      request.response.headers.contentType = ContentType('text', 'xml');
      request.response.write(
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
        '${fail ? '<s:Fault/>' : '<u:${action}Response xmlns:u="${device.serviceType}"/>'}'
        '</s:Body></s:Envelope>',
      );
      await request.response.close();
    });
    final uri = Uri.parse('https://cdn.example/video.mp4?sign=a%2Bb&expires=1');
    await repository.setMedia(
      device,
      CastMedia(
        request: const CastMediaRequest(aid: '1', cid: '2', quality: 80),
        uri: uri,
      ),
      '标题 <你好> & TV',
      cancellation: RequestCancellation(),
    );
    await repository.command(
      device,
      CastCommand.play,
      cancellation: RequestCancellation(),
    );
    final document = XmlDocument.parse(bodies.first);
    String value(String name) => document.descendants
        .whereType<XmlElement>()
        .singleWhere((node) => node.name.local == name)
        .innerText;
    expect(value('CurrentURI'), uri.toString());
    expect(bodies.first, isNot(contains('bilibili://')));
    expect(bodies.first, isNot(contains('longDescription')));
    final metadata = XmlDocument.parse(value('CurrentURIMetaData'));
    expect(
      metadata.descendants
          .whereType<XmlElement>()
          .singleWhere((node) => node.name.local == 'title')
          .innerText,
      '标题 <你好> & TV',
    );
    fail = true;
    await expectLater(
      repository.command(
        device,
        CastCommand.pause,
        cancellation: RequestCancellation(),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(actions, ['SetAVTransportURI', 'Play', 'Pause']);
  });
  test(
    'cancelling pending HTTP closes request and returns cancelled',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final arrived = Completer<void>();
      server.listen((request) {
        arrived.complete();
      });
      final repository = DlnaCastRepository();
      addTearDown(() async {
        repository.dispose();
        await server.close(force: true);
      });
      final token = RequestCancellation();
      final result = repository.command(
        CastDevice(
          id: 'tv',
          name: 'tv',
          controlUri: Uri.parse('http://127.0.0.1:${server.port}/control'),
          serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
        ),
        CastCommand.play,
        cancellation: token,
      );
      final check = expectLater(
        result,
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            AppFailureKind.cancelled,
          ),
        ),
      );
      await arrived.future;
      token.cancel();
      await check;
    },
  );
}

// Decode as an independent receiver: AES-CBC/PKCS7, then raw DEFLATE JSON.
Map<String, Object?> _decodeProjection(String value) {
  final key = Uint8List.fromList(utf8.encode('1pzhA828t4i.6Oq@'));
  final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
    ..init(
      false,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), key),
        null,
      ),
    );
  final decoded = cipher.process(base64Url.decode(base64Url.normalize(value)));
  return (jsonDecode(
    utf8.decode(ZLibDecoder(raw: true).convert(decoded)),
  ) as Map).cast<String, Object?>();
}
