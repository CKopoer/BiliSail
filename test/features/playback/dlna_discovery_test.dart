import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/playback/data/dlna_cast_repository.dart';
import 'package:bilisail/features/playback/data/dlna_network.dart';
import 'package:bilisail/features/playback/domain/casting.dart';
import 'package:flutter_test/flutter_test.dart';

final _v4 = DlnaNetworkAddress(InternetAddress.loopbackIPv4, 0);
final _v6 = DlnaNetworkAddress(InternetAddress.loopbackIPv6, 0);

String _description(
  String id, {
  bool enhanced = false,
  String control = '/av',
}) =>
    '''
<root><device><deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
<friendlyName>$id</friendlyName><UDN>uuid:$id</UDN><serviceList>
<service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><controlURL>$control</controlURL></service>
${enhanced ? '<service><serviceType>urn:app-bilibili-com:service:NirvanaControl:3</serviceType><controlURL>/nirvana</controlURL></service>' : ''}
</serviceList></device></root>''';

void _reply(_Socket socket, InternetAddress address, Uri location) {
  socket.emit(
    Datagram(
      ascii.encode('HTTP/1.1 200 OK\r\nLOCATION: $location\r\n\r\n'),
      address,
      1900,
    ),
  );
}

Future<void> _until(bool Function() condition) async {
  await (() async {
    while (!condition()) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  })().timeout(const Duration(seconds: 3));
}

void main() {
  test(
    'every source is searched independently, with IPv4 and scoped IPv6 targets',
    () async {
      final networks = [
        DlnaNetworkAddress(InternetAddress('192.168.1.2'), 11),
        DlnaNetworkAddress(InternetAddress('10.0.0.2'), 12),
        DlnaNetworkAddress(InternetAddress('fe80::1234'), 11),
        DlnaNetworkAddress(InternetAddress('2001:db8::1234'), 11),
      ];
      final sockets = <_Socket>[];
      final transport = _Transport([...networks, networks.first], (
        network,
      ) async {
        final socket = _Socket();
        sockets.add(socket);
        return socket;
      });
      final repository = DlnaCastRepository(discoveryTransport: transport);
      addTearDown(repository.dispose);
      final token = RequestCancellation();
      final result = repository.discover(cancellation: token).toList();
      await _until(
        () =>
            sockets.length == 4 &&
            sockets.every((socket) => socket.sent.length == 3),
      );
      expect(
        transport.bound.map((network) => network.key).toSet(),
        networks.map((network) => network.key).toSet(),
      );
      expect(sockets[0].sent.first.target.address, '239.255.255.250');
      expect(sockets[1].sent.first.target.address, '239.255.255.250');
      for (final socket in sockets.skip(2)) {
        expect(socket.sent.first.target.address, 'ff02::c%11');
        expect(socket.sent.first.text, contains('HOST: [ff02::c]:1900\r\n'));
      }
      token.cancel();
      expect(await result, isEmpty);
      expect(sockets.every((socket) => socket.closed), isTrue);
    },
  );

  test('a failed VPN bind, unsupported family and broken sender do not hide a healthy interface', () async {
    final broken = _Socket()..sendError = const SocketException('send failed');
    final good = _Socket();
    final networks = List.generate(
      4,
      (i) => DlnaNetworkAddress(InternetAddress('10.0.$i.1'), i + 1),
    );
    final transport = _Transport(networks, (network) async {
      switch (network.interfaceIndex) {
        case 1:
          throw const SocketException('VPN unavailable');
        case 2:
          throw UnsupportedError('IPv6 unavailable');
        case 3:
          return broken;
        default:
          return good;
      }
    });
    final repository = DlnaCastRepository(discoveryTransport: transport);
    addTearDown(repository.dispose);
    final token = RequestCancellation();
    final result = repository.discover(cancellation: token).toList();
    await _until(() => good.sent.length == 3);
    expect(broken.closed, isTrue);
    token.cancel();
    expect(await result, isEmpty);
    expect(good.closed, isTrue);
  });

  test('all unusable interfaces report a network error', () async {
    final repository = DlnaCastRepository(
      discoveryTransport: _Transport([_v4], (_) async {
        throw const SocketException('unavailable');
      }),
    );
    addTearDown(repository.dispose);
    await expectLater(
      repository.discover(cancellation: RequestCancellation()).toList(),
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', AppFailureKind.network),
      ),
    );
  });

  test('the global deadline includes interface enumeration', () async {
    final enumeration = Completer<List<DlnaNetworkAddress>>();
    final transport = _Transport([], (_) async => _Socket())
      ..listing = enumeration.future;
    final repository = DlnaCastRepository(
      discoveryTransport: transport,
      searchDuration: const Duration(milliseconds: 40),
    );
    addTearDown(repository.dispose);
    expect(
      await repository
          .discover(cancellation: RequestCancellation())
          .toList()
          .timeout(const Duration(seconds: 2)),
      isEmpty,
    );
    enumeration.complete([_v4]);
    await Future<void>.delayed(Duration.zero);
    expect(transport.bound, isEmpty);
  });

  test(
    'a bind that finishes after cancellation immediately closes its socket',
    () async {
      final bind = Completer<DlnaDiscoverySocket>();
      final transport = _Transport([_v4], (_) => bind.future);
      final repository = DlnaCastRepository(discoveryTransport: transport);
      addTearDown(repository.dispose);
      final token = RequestCancellation();
      final result = repository.discover(cancellation: token).toList();
      await _until(() => transport.bound.isNotEmpty);
      token.cancel();
      expect(await result, isEmpty);
      final socket = _Socket();
      bind.complete(socket);
      await _until(() => socket.closed);
      expect(socket.sent, isEmpty);
    },
  );

  test(
    'disposing or cancelling the result stream closes every socket',
    () async {
      for (final dispose in [false, true]) {
        final sockets = <_Socket>[];
        final transport = _Transport([_v4, _v6], (_) async {
          final socket = _Socket();
          sockets.add(socket);
          return socket;
        });
        final repository = DlnaCastRepository(discoveryTransport: transport);
        final sub = repository
            .discover(cancellation: RequestCancellation())
            .listen((_) {});
        await _until(
          () =>
              sockets.length == 2 &&
              sockets.every((socket) => socket.sent.isNotEmpty),
        );
        if (dispose) {
          repository.dispose();
        } else {
          await sub.cancel().timeout(const Duration(seconds: 1));
        }
        await _until(() => sockets.every((socket) => socket.closed));
        await sub.cancel();
        repository.dispose();
      }
    },
  );

  test(
    'search re-enumerates interfaces and repeats each target only once',
    () async {
      final sockets = <_Socket>[];
      final transport = _Transport([_v4], (_) async {
        final socket = _Socket();
        sockets.add(socket);
        return socket;
      });
      final repository = DlnaCastRepository(discoveryTransport: transport);
      addTearDown(repository.dispose);
      final firstToken = RequestCancellation();
      final first = repository.discover(cancellation: firstToken).toList();
      await _until(() => sockets.isNotEmpty && sockets.first.sent.length == 6);
      firstToken.cancel();
      await first;
      transport.networks = [_v6];
      final secondToken = RequestCancellation();
      final second = repository.discover(cancellation: secondToken).toList();
      await _until(() => sockets.length == 2 && sockets.last.sent.length == 3);
      secondToken.cancel();
      await second;
      expect(transport.enumerations, 2);
      expect(transport.bound, [_v4, _v6]);
    },
  );

  test(
    'a hanging description cannot block a renderer on another interface',
    () async {
      final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final slowArrived = Completer<void>();
      final slow = _Socket(), fast = _Socket();
      var requests = 0;
      http.listen((request) async {
        requests++;
        if (request.uri.path == '/slow') {
          slowArrived.complete();
          return;
        }
        request.response.write(_description('fast'));
        await request.response.close();
      });
      final routes = [
        DlnaNetworkAddress(InternetAddress.loopbackIPv4, 1),
        DlnaNetworkAddress(InternetAddress.loopbackIPv4, 2),
      ];
      final repository = DlnaCastRepository(
        discoveryTransport: _Transport(
          routes,
          (network) async => network.interfaceIndex == 1 ? slow : fast,
        ),
      );
      addTearDown(() async {
        repository.dispose();
        await http.close(force: true);
      });
      final token = RequestCancellation();
      final found = Completer<CastDevice>();
      final sub = repository.discover(cancellation: token).listen((device) {
        if (!found.isCompleted) found.complete(device);
      });
      await _until(() => slow.sent.isNotEmpty && fast.sent.isNotEmpty);
      _reply(
        slow,
        InternetAddress.loopbackIPv4,
        Uri.parse('http://127.0.0.1:${http.port}/slow'),
      );
      await slowArrived.future;
      for (var i = 0; i < 5; i++) {
        _reply(
          fast,
          InternetAddress.loopbackIPv4,
          Uri.parse('http://127.0.0.1:${http.port}/fast'),
        );
      }
      expect(
        (await found.future.timeout(const Duration(seconds: 2))).id,
        'uuid:fast',
      );
      expect(requests, 2);
      token.cancel();
      await sub.cancel();
    },
  );

  test('real IPv6 UDP and HTTP discovery and SOAP work over loopback', () async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv6, 0);
    final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv6, 0);
    final repository = DlnaCastRepository(
      discoveryAddress: InternetAddress.loopbackIPv6,
      discoveryPort: udp.port,
      searchDuration: const Duration(milliseconds: 400),
    );
    final posts = <String>[];
    http.listen((request) async {
      if (request.method == 'GET') {
        request.response.write(_description('v6', enhanced: true));
      } else {
        final action = request.headers
            .value('soapaction')!
            .split('#')
            .last
            .replaceAll('"', '');
        posts.add(action);
        await request.drain<void>();
        request.response.write('<Envelope><${action}Response/></Envelope>');
      }
      await request.response.close();
    });
    udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = udp.receive();
      if (packet == null) return;
      udp.send(
        ascii.encode(
          'HTTP/1.1 200 OK\r\nLOCATION: http://[0:0:0:0:0:0:0:1]:${http.port}/device.xml\r\n\r\n',
        ),
        packet.address,
        packet.port,
      );
    });
    addTearDown(() async {
      repository.dispose();
      udp.close();
      await http.close(force: true);
    });
    final devices = await repository
        .discover(cancellation: RequestCancellation())
        .toList();
    expect(devices, hasLength(1));
    expect(devices.single.controlUri.host, '::1');
    await repository.command(
      devices.single,
      CastCommand.play,
      cancellation: RequestCancellation(),
    );
    await repository.setDanmaku(
      devices.single,
      true,
      cancellation: RequestCancellation(),
    );
    expect(posts, ['Play', 'SetDanmakuSwitch']);
  });

  test('dual-stack endpoints merge by UDN and a failed IPv4 connection falls back to IPv6', () async {
    final ipv4 = await _Renderer.create(InternetAddress.loopbackIPv4);
    final ipv6 = await _Renderer.create(InternetAddress.loopbackIPv6);
    final pair = await _discoverPair(ipv4, ipv6);
    addTearDown(() async {
      pair.repository.dispose();
      await ipv4.close();
      await ipv6.close();
    });
    expect(pair.devices.map((device) => device.id).toSet(), {'uuid:pair'});
    expect(ipv4.gets, 1);
    expect(ipv6.gets, 1);
    final device = pair.devices.last;
    expect(device.controlUri.host, '127.0.0.1');
    await ipv4.close();
    await pair.repository.command(
      device,
      CastCommand.play,
      cancellation: RequestCancellation(),
    );
    await pair.repository.command(
      device,
      CastCommand.pause,
      cancellation: RequestCancellation(),
    );
    expect(ipv6.posts, ['Play', 'Pause']);
    expect(ipv6.peers.every((peer) => peer == '::1'), isTrue);
  });

  for (final drop in [false, true]) {
    test(
      '${drop ? 'lost SOAP reply' : 'SOAP Fault'} never replays a command on another endpoint',
      () async {
        final ipv4 = await _Renderer.create(InternetAddress.loopbackIPv4);
        final ipv6 = await _Renderer.create(InternetAddress.loopbackIPv6);
        final pair = await _discoverPair(ipv4, ipv6);
        addTearDown(() async {
          pair.repository.dispose();
          await ipv4.close();
          await ipv6.close();
        });
        ipv4.drop = drop;
        ipv4.fault = !drop;
        await expectLater(
          pair.repository.command(
            pair.devices.last,
            CastCommand.play,
            cancellation: RequestCancellation(),
          ),
          throwsA(isA<AppFailure>()),
        );
        expect(ipv4.posts, ['Play']);
        expect(ipv6.posts, isEmpty);
      },
    );
  }

  test('a later IPv6 endpoint can upgrade Nirvana capability without borrowing another host service', () async {
    final ipv4 = await _Renderer.create(InternetAddress.loopbackIPv4);
    final ipv6 = await _Renderer.create(
      InternetAddress.loopbackIPv6,
      enhanced: true,
    );
    final pair = await _discoverPair(ipv4, ipv6);
    addTearDown(() async {
      pair.repository.dispose();
      await ipv4.close();
      await ipv6.close();
    });
    expect(pair.devices.map((device) => device.id).toSet(), {'uuid:pair'});
    expect(pair.devices.first.bilibiliService, isNull);
    final device = pair.devices.last;
    expect(device.bilibiliService, isNotNull);
    await pair.repository.setMedia(
      device,
      CastMedia(
        request: const CastMediaRequest(aid: '1', cid: '2', quality: 80),
        aid: '1',
        receiverResolves: true,
      ),
      'TV',
      cancellation: RequestCancellation(),
    );
    await pair.repository.setDanmaku(
      device,
      true,
      cancellation: RequestCancellation(),
    );
    expect(ipv4.posts, isEmpty);
    expect(ipv6.posts, ['SetAVTransportURI', 'SetDanmakuSwitch']);
  });

  test(
    'description concurrency and queued work remain bounded after cancellation',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((_) {
        requests++;
      });
      final socket = _Socket();
      final repository = DlnaCastRepository(
        discoveryTransport: _Transport([_v4], (_) async => socket),
      );
      addTearDown(() async {
        repository.dispose();
        await server.close(force: true);
      });
      final token = RequestCancellation();
      final result = repository.discover(cancellation: token).toList();
      await _until(() => socket.sent.length == 3);
      for (var i = 0; i < 100; i++) {
        _reply(
          socket,
          InternetAddress.loopbackIPv4,
          Uri.parse('http://127.0.0.1:${server.port}/$i.xml'),
        );
      }
      await _until(() => requests == 4);
      token.cancel();
      expect(await result, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(requests, 4);
      expect(socket.closed, isTrue);
    },
  );

  test(
    'already-cancelled discovery does not enumerate or bind interfaces',
    () async {
      final transport = _Transport([_v4], (_) async => _Socket());
      final repository = DlnaCastRepository(discoveryTransport: transport);
      addTearDown(repository.dispose);
      final token = RequestCancellation()..cancel();
      expect(await repository.discover(cancellation: token).toList(), isEmpty);
      expect(transport.enumerations, 0);
      expect(transport.bound, isEmpty);
    },
  );

  test(
    'scope stays in the TCP destination and is removed from the HTTP authority',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv6, 0);
      final headers = <String?>[];
      server.listen((request) async {
        headers.add(request.headers.value(HttpHeaders.hostHeader));
        if (request.method == 'GET') {
          request.response.write(_description('scope'));
        } else {
          await request.drain<void>();
          request.response.write('<Envelope><PlayResponse/></Envelope>');
        }
        await request.response.close();
      });
      final network = DlnaNetworkAddress(InternetAddress('fe80::1234'), 17);
      final channel = _Socket();
      final connections = <({String peer, String? source})>[];
      final repository = DlnaCastRepository(
        discoveryTransport: _Transport([network], (_) async => channel),
        searchDuration: const Duration(milliseconds: 400),
        socketConnector: (host, port, {sourceAddress}) {
          connections.add((
            peer: (host as InternetAddress).address,
            source: sourceAddress?.address,
          ));
          // Keep the scoped endpoints under test independent of local adapters.
          return Socket.startConnect(InternetAddress.loopbackIPv6, port);
        },
      );
      addTearDown(() async {
        repository.dispose();
        await server.close(force: true);
      });
      final discovered = repository
          .discover(cancellation: RequestCancellation())
          .toList();
      await _until(() => channel.sent.isNotEmpty);
      _reply(
        channel,
        InternetAddress('fe80::abcd%17'),
        Uri.parse('http://[fe80::abcd]:${server.port}/device.xml'),
      );
      final device = (await discovered).single;
      await repository.command(
        device,
        CastCommand.play,
        cancellation: RequestCancellation(),
      );
      expect(headers, [
        '[fe80::abcd]:${server.port}',
        '[fe80::abcd]:${server.port}',
      ]);
      expect(connections, [
        (peer: 'fe80::abcd%17', source: 'fe80::1234%17'),
        (peer: 'fe80::abcd%17', source: 'fe80::1234%17'),
      ]);
    },
  );
}

Future<({DlnaCastRepository repository, List<CastDevice> devices})>
_discoverPair(_Renderer ipv4, _Renderer ipv6) async {
  final v4socket = _Socket(), v6socket = _Socket();
  final transport = _Transport(
    [_v4, _v6],
    (network) async =>
        network.address.type == InternetAddressType.IPv4 ? v4socket : v6socket,
  );
  final repository = DlnaCastRepository(
    discoveryTransport: transport,
    searchDuration: const Duration(milliseconds: 500),
  );
  final devices = <CastDevice>[];
  final first = Completer<void>();
  final done = repository.discover(cancellation: RequestCancellation()).forEach(
    (device) {
      devices.add(device);
      if (!first.isCompleted) first.complete();
    },
  );
  try {
    await _until(() => v4socket.sent.isNotEmpty && v6socket.sent.isNotEmpty);
    _reply(v4socket, InternetAddress.loopbackIPv4, ipv4.location);
    await first.future.timeout(const Duration(seconds: 2));
    _reply(v6socket, InternetAddress.loopbackIPv6, ipv6.location);
    await done;
    expect(ipv6.gets, 1);
    return (repository: repository, devices: devices);
  } catch (_) {
    repository.dispose();
    rethrow;
  }
}

class _Renderer {
  _Renderer(this.server, this.enhanced) {
    server.listen((request) async {
      peers.add(request.connectionInfo!.remoteAddress.address);
      if (request.method == 'GET') {
        gets++;
        request.response.write(_description('pair', enhanced: enhanced));
      } else {
        final action = request.headers
            .value('soapaction')!
            .split('#')
            .last
            .replaceAll('"', '');
        posts.add(action);
        await request.drain<void>();
        if (drop) {
          (await request.response.detachSocket()).destroy();
          return;
        }
        request.response.write(
          fault
              ? '<Envelope><Fault/></Envelope>'
              : '<Envelope><${action}Response/></Envelope>',
        );
      }
      await request.response.close();
    });
  }
  final HttpServer server;
  final bool enhanced;
  final posts = <String>[], peers = <String>[];
  var gets = 0;
  var drop = false, fault = false, closed = false;
  static Future<_Renderer> create(
    InternetAddress address, {
    bool enhanced = false,
  }) async => _Renderer(await HttpServer.bind(address, 0), enhanced);
  Uri get location => Uri(
    scheme: 'http',
    host: server.address.address,
    port: server.port,
    path: '/device.xml',
  );
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await server.close(force: true);
  }
}

class _Transport implements DlnaDiscoveryTransport {
  _Transport(this.networks, this.onBind);
  List<DlnaNetworkAddress> networks;
  final Future<DlnaDiscoverySocket> Function(DlnaNetworkAddress) onBind;
  Future<List<DlnaNetworkAddress>>? listing;
  final bound = <DlnaNetworkAddress>[];
  var enumerations = 0;
  @override
  Future<List<DlnaNetworkAddress>> addresses() async {
    enumerations++;
    return listing ?? networks;
  }

  @override
  Future<DlnaDiscoverySocket> bind(DlnaNetworkAddress network) {
    bound.add(network);
    return onBind(network);
  }
}

class _Socket implements DlnaDiscoverySocket {
  final _packets = StreamController<Datagram>();
  final sent = <({String text, InternetAddress target, int port})>[];
  bool closed = false;
  SocketException? sendError;
  void emit(Datagram packet) {
    if (!closed) _packets.add(packet);
  }

  @override
  Stream<Datagram> get packets => _packets.stream;
  @override
  int send(List<int> bytes, InternetAddress target, int port) {
    if (sendError case final error?) throw error;
    sent.add((text: ascii.decode(bytes), target: target, port: port));
    return bytes.length;
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    unawaited(_packets.close());
  }
}
