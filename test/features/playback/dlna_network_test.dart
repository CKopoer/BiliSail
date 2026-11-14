import 'dart:io';

import 'package:bilisail/features/playback/data/dlna_cast_repository.dart';
import 'package:bilisail/features/playback/data/dlna_network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'IPv6 spelling is normalized without accepting another host or zone',
    () {
      final location = Uri.parse('http://[fe80::abcd%2517]:9958/device.xml');
      expect(
        sameDlnaHost(
          location,
          Uri.parse('http://[FE80:0:0:0:0:0:0:ABCD]:9958/av'),
        ),
        isTrue,
      );
      expect(
        sameDlnaHost(location, Uri.parse('http://[fe80::abcd%2518]:9958/av')),
        isFalse,
      );
      expect(
        sameDlnaHost(location, Uri.parse('http://[fe80::abce]:9958/av')),
        isFalse,
      );
      expect(DlnaHost.parse('fe80::1%25')?.zone, '25');
      expect(DlnaHost.parse('fe80::1%2525', uriHost: true)?.zone, '25');
      expect(DlnaHost.parse('fe80::1%25')?.socketAddress.address, 'fe80::1%25');
    },
  );

  test('link-local discovery retains the receiving interface through URLs and TCP addresses', () {
    final network = DlnaNetworkAddress(
      InternetAddress('fe80::1234'),
      17,
      name: 'Ethernet',
    );
    final peer = InternetAddress('fe80::abcd%17');
    final location = network.location(
      'http://[FE80:0::ABCD]:9958/device.xml',
      peer,
    )!;
    expect(location.host, 'fe80::abcd%2517');
    expect(
      network
          .scoped(DlnaHost.parse(location.host, uriHost: true)!.address)
          .address,
      'fe80::abcd%17',
    );
    expect(network.source.address, 'fe80::1234%17');
    expect(network.scoped(InternetAddress('ff02::c')).address, 'ff02::c%17');
    expect(
      network.scoped(InternetAddress('2001:db8::1')).address,
      '2001:db8::1',
    );
    expect(
      resolveDlnaUri(location, 'http://[fe80::abcd]:9958/av')!.host,
      location.host,
    );
    expect(resolveDlnaUri(location, '../av')!.host, location.host);
    expect(
      resolveDlnaUri(location, 'http://[fe80::abcd%2518]:9958/av'),
      isNull,
    );
  });

  test(
    'equal link-local addresses on two interfaces remain separate endpoints',
    () {
      final first = DlnaNetworkAddress(InternetAddress('fe80::1234'), 17);
      final second = DlnaNetworkAddress(InternetAddress('fe80::1234'), 18);
      final peer = InternetAddress('fe80::abcd');
      const text = 'http://[fe80::abcd]:9958/device.xml';
      expect(first.key, isNot(second.key));
      expect(first.location(text, peer), isNot(second.location(text, peer)));
    },
  );

  test('advertised endpoints cannot change peer, scheme, credentials or interface scope', () {
    final network = DlnaNetworkAddress(InternetAddress('fe80::1234'), 17);
    final peer = InternetAddress('fe80::abcd%17');
    for (final text in [
      'http://[fe80::abce]:9958/device.xml',
      'http://[fe80::abcd%2518]:9958/device.xml',
      'http://user:pass@[fe80::abcd]:9958/device.xml',
      'http://[fe80::abcd]:9958/device.xml#fragment',
      'file://[fe80::abcd]/device.xml',
      'not a URL',
    ]) {
      expect(network.location(text, peer), isNull, reason: text);
    }
    expect(
      network.location(
        'http://[fe80::abcd]:9958/device.xml',
        InternetAddress('fe80::abcd%18'),
      ),
      isNull,
    );
    final ipv4 = DlnaNetworkAddress(InternetAddress('192.168.1.1'), 17);
    expect(
      ipv4
          .location(
            'http://192.168.1.2:9958/device.xml',
            InternetAddress('192.168.1.2'),
          )!
          .host,
      '192.168.1.2',
    );
    expect(
      ipv4.location(
        'http://192.168.1.3:9958/device.xml',
        InternetAddress('192.168.1.2'),
      ),
      isNull,
    );
  });

  test(
    'IPv6 XML resolution preserves the interface and the same-host boundary',
    () {
      final location = Uri.parse('http://[fe80::abcd%2517]:9958/device.xml');
      String xml(String base, String control, String extension) =>
          '''
<root>$base<device><deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
<friendlyName>IPv6 TV</friendlyName><UDN>uuid:v6</UDN><serviceList>
<service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><controlURL>$control</controlURL></service>
<service><serviceType>urn:app-bilibili-com:service:NirvanaControl:3</serviceType><controlURL>$extension</controlURL></service>
</serviceList></device></root>''';
      final device = DlnaCastRepository.parseDescription(
        xml(
          '<URLBase>http://[FE80:0::ABCD]:9958/base/</URLBase>',
          '../av',
          'http://[fe80::abcd]:9958/nirvana',
        ),
        location,
      ).single;
      expect(device.controlUri.host, location.host);
      expect(device.controlUri.path, '/av');
      expect(device.bilibiliService!.controlUri.host, location.host);
      expect(
        DlnaCastRepository.parseDescription(
          xml('', 'http://[fe80::abcd%2518]:9958/av', '/nirvana'),
          location,
        ),
        isEmpty,
      );
      expect(
        DlnaCastRepository.parseDescription(
          xml(
            '<URLBase>http://[fe80::abce]:9958/</URLBase>',
            '/av',
            '/nirvana',
          ),
          location,
        ),
        isEmpty,
      );
    },
  );

  test(
    'IPv4 socket binds its source and sets the portable IP_MULTICAST_IF option',
    () async {
      final socket = _RawSocket();
      InternetAddress? bound;
      final transport = IoDlnaDiscoveryTransport(
        socketBinder: (address, port) async {
          bound = address;
          expect(port, 0);
          return socket;
        },
      );
      final channel = await transport.bind(
        DlnaNetworkAddress(InternetAddress('192.168.23.215'), 11),
      );
      expect(bound!.address, '192.168.23.215');
      expect(socket.options.single.level, RawSocketOption.levelIPv4);
      expect(
        socket.options.single.option,
        RawSocketOption.IPv4MulticastInterface,
      );
      expect(socket.options.single.value, [192, 168, 23, 215]);
      expect(socket.hops, 2);
      expect(socket.writes, isFalse);
      channel.close();
      expect(socket.closed, isTrue);
    },
  );

  test(
    'IPv6 socket binds a scoped source and selects the interface index',
    () async {
      final socket = _RawSocket();
      InternetAddress? bound;
      final transport = IoDlnaDiscoveryTransport(
        socketBinder: (address, _) async {
          bound = address;
          return socket;
        },
      );
      await transport.bind(
        DlnaNetworkAddress(InternetAddress('fe80::1234'), 17),
      );
      expect(bound!.address, 'fe80::1234%17');
      final option = socket.options.single;
      expect(option.level, RawSocketOption.levelIPv6);
      expect(option.option, RawSocketOption.IPv6MulticastInterface);
      expect(
        option.value,
        RawSocketOption.fromInt(option.level, option.option, 17).value,
      );
    },
  );

  test('a failed multicast option closes the already-created socket', () async {
    final socket = _RawSocket()..failOption = true;
    final transport = IoDlnaDiscoveryTransport(
      socketBinder: (_, _) async => socket,
    );
    await expectLater(
      transport.bind(DlnaNetworkAddress(InternetAddress('192.168.1.1'), 11)),
      throwsA(isA<SocketException>()),
    );
    expect(socket.closed, isTrue);
  });
}

class _RawSocket extends Fake implements RawDatagramSocket {
  final options = <RawSocketOption>[];
  var closed = false, failOption = false, writes = true;
  var hops = 0;
  @override
  set writeEventsEnabled(bool value) => writes = value;
  @override
  set multicastHops(int value) => hops = value;
  @override
  void setRawOption(RawSocketOption option) {
    if (failOption) throw const SocketException('interface disappeared');
    options.add(option);
  }

  @override
  void close() => closed = true;
}
