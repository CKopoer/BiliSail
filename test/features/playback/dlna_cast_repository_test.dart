import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/playback/data/dlna_cast_repository.dart';
import 'package:bilisail/features/playback/domain/casting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

String _description({
  String base = '',
  String control = '/control',
  String type = 'MediaRenderer',
}) =>
    '''
<root xmlns="urn:schemas-upnp-org:device-1-0">$base<device>
<deviceType>urn:schemas-upnp-org:device:$type:1</deviceType>
<friendlyName>客厅 &amp; 电视</friendlyName><UDN>uuid:fixture-tv</UDN>
<serviceList><service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
<controlURL>$control</controlURL></service></serviceList></device></root>''';

void main() {
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
      uri,
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
