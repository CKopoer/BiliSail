import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/casting.dart';
import 'bilibili_cast_projection.dart';
import 'dlna_network.dart';

/// SSDP discovery and AVTransport control use no account headers or cookies.
final class DlnaCastRepository implements CastDeviceRepository {
  DlnaCastRepository({
    this.searchDuration = const Duration(seconds: 12),
    this.discoveryAddress,
    this.discoveryPort = 1900,
    this.discoveryTransport = const IoDlnaDiscoveryTransport(),
    this.socketConnector = Socket.startConnect,
  });
  final Duration searchDuration;
  final InternetAddress? discoveryAddress;
  final int discoveryPort;
  final DlnaDiscoveryTransport discoveryTransport;
  final DlnaSocketConnector socketConnector;
  final _clients = <HttpClient>{};
  final _searches = <RequestCancellation>{};
  final _endpoints = <String, List<_DlnaEndpoint>>{};
  final _preferred = <String, String>{};
  bool _disposed = false;

  @override
  Stream<CastDevice> discover({required RequestCancellation cancellation}) {
    final search = RequestCancellation();
    cancellation.onCancel(search.cancel);
    final updates = StreamController<CastDevice>();
    final sockets = <DlnaDiscoverySocket>[];
    final subscriptions = <StreamSubscription<Datagram>>[];
    final retries = <Timer>[];
    final locations = <String>{};
    final devices = <String, CastDevice>{};
    final queue = Queue<({Uri uri, DlnaNetworkAddress network})>();
    var activeRequests = 0;
    var workingSockets = 0;
    Timer? timer;
    search.onCancel(() {
      timer?.cancel();
      for (final retry in retries) {
        retry.cancel();
      }
      for (final socket in sockets) {
        socket.close();
      }
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
      queue.clear();
      _searches.remove(search);
      unawaited(updates.close());
    });

    void fail(Object error, StackTrace stack) {
      if (search.isCancelled) return;
      updates.addError(error, stack);
      search.cancel();
    }

    void remember(CastDevice device, DlnaNetworkAddress network) {
      final previous = devices[device.id];
      if (previous == null) {
        if (devices.length >= 64) return;
        if (!_endpoints.containsKey(device.id) && _endpoints.length >= 64) {
          _preferred.remove(_endpoints.keys.first);
          _endpoints.remove(_endpoints.keys.first);
        }
        _endpoints[device.id] = [];
      }
      final endpoint = _DlnaEndpoint(device, network);
      final routes = _endpoints[device.id]!;
      if (routes.length < 64 &&
          !routes.any((route) => route.key == endpoint.key)) {
        routes.add(endpoint);
      }
      final upgrade =
          previous == null ||
          (previous.bilibiliService == null &&
              device.bilibiliService != null) ||
          ((previous.bilibiliService != null) ==
                  (device.bilibiliService != null) &&
              DlnaHost.parse(
                    previous.controlUri.host,
                    uriHost: true,
                  )?.address.type ==
                  InternetAddressType.IPv6 &&
              network.address.type == InternetAddressType.IPv4);
      if (upgrade) {
        devices[device.id] = device;
        updates.add(device);
      }
    }

    late void Function() pump;
    Future<void> load(Uri uri, DlnaNetworkAddress network) async {
      try {
        final xml = await _request(uri, search, network: network);
        if (search.isCancelled) return;
        for (final device in parseDescription(xml, uri)) {
          remember(device, network);
        }
      } on AppFailure {
        // An unreachable/malformed endpoint must not stall other interfaces.
      } finally {
        activeRequests--;
        pump();
      }
    }

    pump = () {
      while (!search.isCancelled && activeRequests < 4 && queue.isNotEmpty) {
        final task = queue.removeFirst();
        activeRequests++;
        unawaited(load(task.uri, task.network).catchError(fail));
      }
    };

    void receive(Datagram packet, DlnaNetworkAddress network) {
      if (search.isCancelled || packet.data.length > 16384) return;
      final lines = latin1.decode(packet.data).split(RegExp(r'\r?\n'));
      if (lines.isEmpty ||
          !RegExp(r'^HTTP/1\.[01] 200\b').hasMatch(lines.first)) {
        return;
      }
      final headers = <String, String>{};
      for (final line in lines.skip(1)) {
        final separator = line.indexOf(':');
        if (separator > 0) {
          headers[line.substring(0, separator).trim().toLowerCase()] = line
              .substring(separator + 1)
              .trim();
        }
      }
      final uri = network.location(headers['location'] ?? '', packet.address);
      if (uri == null ||
          locations.length >= 64 ||
          !locations.add('${network.key}/$uri')) {
        return;
      }
      queue.add((uri: uri, network: network));
      pump();
    }

    Future<void> open(DlnaNetworkAddress network) async {
      DlnaDiscoverySocket? socket;
      try {
        final override = discoveryAddress;
        if (override != null && override.type != network.address.type) return;
        socket = await discoveryTransport.bind(network);
        if (search.isCancelled) {
          socket.close();
          return;
        }
        sockets.add(socket);
        var closed = false;
        void close() {
          if (closed) return;
          closed = true;
          socket!.close();
        }

        subscriptions.add(
          socket.packets.listen(
            (packet) => receive(packet, network),
            onError: (Object error, StackTrace stack) {
              if (error is IOException) {
                close();
              } else {
                fail(error, stack);
              }
            },
          ),
        );
        final target =
            override ??
            network.scoped(
              InternetAddress(
                network.address.type == InternetAddressType.IPv4
                    ? '239.255.255.250'
                    : 'ff02::c',
              ),
            );
        void send() {
          if (search.isCancelled || closed) return;
          try {
            // Search replies are unicast to this interface's ephemeral port.
            for (final type in const [
              'urn:schemas-upnp-org:device:MediaRenderer:1',
              'urn:schemas-upnp-org:service:AVTransport:1',
              'urn:app-bilibili-com:service:NirvanaControl:3',
            ]) {
              final host = target.type == InternetAddressType.IPv4
                  ? target.address
                  : '[${InternetAddress.fromRawAddress(target.rawAddress).address}]';
              socket!.send(
                ascii.encode(
                  'M-SEARCH * HTTP/1.1\r\nHOST: $host:$discoveryPort\r\n'
                  'MAN: "ssdp:discover"\r\nMX: 3\r\nST: $type\r\n\r\n',
                ),
                target,
                discoveryPort,
              );
            }
          } on IOException {
            close();
          }
        }

        send();
        if (!closed) {
          workingSockets++;
          retries.add(Timer(const Duration(seconds: 1), send));
        }
      } on IOException {
        socket?.close();
      } on ArgumentError {
        socket?.close();
      } on UnsupportedError {
        socket?.close();
      }
    }

    Future<void> start() async {
      _check(search);
      final override = discoveryAddress;
      final networks = override != null && override.isLoopback
          ? [DlnaNetworkAddress(override, 0)]
          : await discoveryTransport.addresses();
      if (search.isCancelled) return;
      final seen = <String>{};
      await Future.wait(
        networks.where((network) => seen.add(network.key)).map(open),
      );
      if (!search.isCancelled && workingSockets == 0) {
        fail(
          const AppFailure(AppFailureKind.network, '无法搜索投屏设备，请检查局域网权限和网络连接'),
          StackTrace.current,
        );
      }
    }

    updates.onListen = () {
      if (search.isCancelled) return;
      _searches.add(search);
      timer = Timer(searchDuration, search.cancel);
      unawaited(
        start().catchError((Object error, StackTrace stack) {
          fail(
            error is IOException
                ? const AppFailure(AppFailureKind.network, '无法读取局域网接口，请检查网络连接')
                : error,
            stack,
          );
        }),
      );
    };
    updates.onCancel = search.cancel;
    return updates.stream;
  }

  static List<CastDevice> parseDescription(String xml, Uri location) {
    try {
      final document = XmlDocument.parse(xml);
      if (document.children.any((node) => node is XmlDoctype)) return const [];
      final baseText = _child(document.rootElement, 'URLBase');
      final base = baseText.isEmpty
          ? location
          : resolveDlnaUri(location, baseText);
      if (base == null || !isDlnaHttpUri(base)) return const [];
      final result = <CastDevice>[];
      for (final device in document.descendants.whereType<XmlElement>().where(
        (node) => node.name.local == 'device',
      )) {
        if (!_child(
          device,
          'deviceType',
        ).startsWith('urn:schemas-upnp-org:device:MediaRenderer:')) {
          continue;
        }
        final services = device.childElements
            .where((node) => node.name.local == 'serviceList')
            .expand((node) => node.childElements)
            .toList();
        CastService? bilibili;
        for (final service in services) {
          final type = _child(service, 'serviceType');
          final path = _child(service, 'controlURL');
          if (!RegExp(
                r'^urn:(app-bilibili-com|schemas-upnp-org):service:NirvanaControl:[1-9][0-9]*$',
              ).hasMatch(type) ||
              path.isEmpty) {
            continue;
          }
          final control = resolveDlnaUri(base, path);
          if (control != null) {
            bilibili = CastService(controlUri: control, type: type);
            break;
          }
        }
        for (final service in services) {
          final type = _child(service, 'serviceType');
          final path = _child(service, 'controlURL');
          if (!RegExp(r'^urn:schemas-upnp-org:service:AVTransport:[1-9][0-9]*$')
                  .hasMatch(type) ||
              path.isEmpty) {
            continue;
          }
          final control = resolveDlnaUri(base, path);
          if (control == null) continue;
          final name = _child(device, 'friendlyName');
          final udn = _child(device, 'UDN');
          result.add(
            CastDevice(
              id: udn.isEmpty ? control.toString() : udn,
              name: name.isEmpty
                  ? location.host
                  : name.substring(0, name.length.clamp(0, 128)),
              controlUri: control,
              serviceType: type,
              bilibiliService: bilibili,
            ),
          );
          break;
        }
      }
      return result;
    } on FormatException {
      return const [];
    } on XmlException {
      return const [];
    }
  }

  @override
  Future<void> setMedia(
    CastDevice device,
    CastMedia media,
    String title, {
    required RequestCancellation cancellation,
  }) {
    // NirvanaControl discovery does not prove that a TV can load an
    // identity-only projection using this sender's metadata and session.
    final enhanced = media.receiverResolves;
    if (enhanced && device.bilibiliService == null) {
      throw const AppFailure(AppFailureKind.protocol, '投屏设备不支持电视弹幕模式');
    }
    final uri = enhanced
        ? Uri.parse('bilibili://projection?proj_source=bilibili&_nva_ext_=')
        : media.uri;
    if (uri == null || (!enhanced && !isDlnaHttpUri(uri))) {
      throw const AppFailure(AppFailureKind.protocol, '未取得可投屏的媒体地址');
    }
    final projection = enhanced ? encodeBilibiliCastProjection(media) : null;
    final metadata = XmlBuilder()
      ..element(
        'DIDL-Lite',
        attributes: {
          'xmlns': 'urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/',
          'xmlns:dc': 'http://purl.org/dc/elements/1.1/',
          'xmlns:upnp': 'urn:schemas-upnp-org:metadata-1-0/upnp/',
        },
        nest: () {},
      );
    final root = metadata.buildDocument().rootElement;
    final item = XmlElement(
      XmlName('item'),
      [
        XmlAttribute(XmlName('id'), '0'),
        XmlAttribute(XmlName('parentID'), '-1'),
        XmlAttribute(XmlName('restricted'), '1'),
      ],
      [
        XmlElement(XmlName('title', 'dc'), [], [XmlText(title)]),
        if (projection != null)
          XmlElement(XmlName('longDescription', 'upnp'), [], [
            XmlText(projection),
          ]),
        XmlElement(XmlName('class', 'upnp'), [], [
          XmlText('object.item.videoItem'),
        ]),
        XmlElement(
          XmlName('res'),
          [
            XmlAttribute(
              XmlName('protocolInfo'),
              'http-get:*:${switch (uri.path.split('.').last.toLowerCase()) {
                'flv' => 'video/x-flv',
                'm3u8' => 'application/vnd.apple.mpegurl',
                _ => 'video/mp4',
              }}:*',
            ),
          ],
          [XmlText(uri.toString())],
        ),
      ],
    );
    root.children.add(item);
    return _action(
      device,
      'SetAVTransportURI',
      {'CurrentURI': uri.toString(), 'CurrentURIMetaData': root.toXmlString()},
      cancellation,
      requiresBilibili: enhanced,
    );
  }

  @override
  Future<void> command(
    CastDevice device,
    CastCommand command, {
    required RequestCancellation cancellation,
  }) => _action(
    device,
    switch (command) {
      CastCommand.play => 'Play',
      CastCommand.pause => 'Pause',
      CastCommand.stop => 'Stop',
    },
    {if (command == CastCommand.play) 'Speed': '1'},
    cancellation,
  );

  @override
  Future<void> setDanmaku(
    CastDevice device,
    bool enabled, {
    required RequestCancellation cancellation,
  }) {
    final service = device.bilibiliService;
    if (service == null ||
        !sameDlnaHost(service.controlUri, device.controlUri)) {
      throw const AppFailure(AppFailureKind.protocol, '投屏设备不支持弹幕控制');
    }
    return _action(
      device,
      'SetDanmakuSwitch',
      {'DesiredSwitch': enabled ? '1' : '0'},
      cancellation,
      service: service,
    );
  }

  Future<void> _action(
    CastDevice device,
    String action,
    Map<String, String> arguments,
    RequestCancellation cancellation, {
    CastService? service,
    bool requiresBilibili = false,
  }) async {
    final candidates = [...?_endpoints[device.id]];
    if (candidates.isEmpty) candidates.add(_DlnaEndpoint(device, null));
    final preferred = _preferred[device.id];
    candidates.sort((a, b) {
      if (a.key == b.key) return 0;
      if (a.key == preferred) return -1;
      if (b.key == preferred) return 1;
      final a4 =
          DlnaHost.parse(
            a.device.controlUri.host,
            uriHost: true,
          )?.address.type ==
          InternetAddressType.IPv4;
      final b4 =
          DlnaHost.parse(
            b.device.controlUri.host,
            uriHost: true,
          )?.address.type ==
          InternetAddressType.IPv4;
      return a4 == b4
          ? 0
          : a4
          ? -1
          : 1;
    });
    final elapsed = Stopwatch()..start();
    AppFailure? failure;
    for (final endpoint in candidates) {
      _check(cancellation);
      if (requiresBilibili && endpoint.device.bilibiliService == null) continue;
      final targetService = service == null
          ? null
          : endpoint.device.bilibiliService;
      if (service != null && targetService == null) continue;
      final remaining = const Duration(seconds: 5) - elapsed.elapsed;
      if (remaining <= Duration.zero) break;
      try {
        await _performAction(
          endpoint,
          action,
          arguments,
          cancellation,
          service: targetService,
          timeout: remaining,
        );
        _preferred[device.id] = endpoint.key;
        return;
      } on _DlnaConnectionFailure catch (error) {
        // Only a failure before a TCP connection exists can try another address.
        // A SOAP request with an uncertain result must never be replayed.
        failure = error.failure;
      }
    }
    throw failure ??
        const AppFailure(AppFailureKind.network, '无法连接投屏设备，请重新搜索后重试');
  }

  Future<void> _performAction(
    _DlnaEndpoint endpoint,
    String action,
    Map<String, String> arguments,
    RequestCancellation cancellation, {
    CastService? service,
    required Duration timeout,
  }) async {
    final device = endpoint.device;
    final type = service?.type ?? device.serviceType;
    if (!RegExp(r'^urn:schemas-upnp-org:service:AVTransport:[1-9][0-9]*$')
            .hasMatch(type) &&
        !(service != null &&
            RegExp(
              r'^urn:(app-bilibili-com|schemas-upnp-org):service:NirvanaControl:[1-9][0-9]*$',
            ).hasMatch(type))) {
      throw const AppFailure(AppFailureKind.protocol, '投屏设备协议不受支持');
    }
    final builder = XmlBuilder();
    builder.element(
      's:Envelope',
      attributes: {
        'xmlns:s': 'http://schemas.xmlsoap.org/soap/envelope/',
        's:encodingStyle': 'http://schemas.xmlsoap.org/soap/encoding/',
      },
      nest: () => builder.element(
        's:Body',
        nest: () => builder.element(
          'u:$action',
          attributes: {'xmlns:u': type},
          nest: () {
            for (final entry in {
              if (service == null) 'InstanceID': '0',
              ...arguments,
            }.entries) {
              builder.element(entry.key, nest: entry.value);
            }
          },
        ),
      ),
    );
    final xml = await _request(
      service?.controlUri ?? device.controlUri,
      cancellation,
      action: '$type#$action',
      body: builder.buildDocument().toXmlString(),
      network: endpoint.network,
      timeout: timeout,
    );
    try {
      final document = XmlDocument.parse(xml);
      final names = document.descendants
          .whereType<XmlElement>()
          .map((node) => node.name.local)
          .toSet();
      if (names.contains('Fault') || !names.contains('${action}Response')) {
        throw const AppFailure(
          AppFailureKind.playback,
          '设备未接受投屏操作，请在电视上检查播放状态后重试',
        );
      }
    } on XmlException {
      throw const AppFailure(AppFailureKind.protocol, '投屏设备返回了无法识别的数据');
    }
  }

  Future<String> _request(
    Uri uri,
    RequestCancellation cancellation, {
    String? action,
    String? body,
    DlnaNetworkAddress? network,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _check(cancellation);
    if (!isDlnaHttpUri(uri)) {
      throw const AppFailure(AppFailureKind.protocol, '投屏设备地址无效');
    }
    final host = DlnaHost.parse(uri.host, uriHost: true);
    // Scope selects a local interface, not the HTTP Host or TLS peer identity.
    final wireUri = host?.zone == null
        ? uri
        : uri.replace(host: host!.address.address);
    var connected = false;
    final client = HttpClient()
      ..connectionTimeout = timeout < const Duration(seconds: 3)
          ? timeout
          : const Duration(seconds: 3)
      ..findProxy = (_) => 'DIRECT';
    client.connectionFactory = (url, proxyHost, proxyPort) async {
      _check(cancellation);
      final target = host == null
          ? url.host
          : network?.scoped(host.address) ?? host.socketAddress;
      final task = await socketConnector(
        target,
        url.port,
        sourceAddress: network?.source,
      );
      cancellation.onCancel(task.cancel);
      return ConnectionTask.fromSocket(
        task.socket.then((socket) {
          if (cancellation.isCancelled || _disposed) {
            socket.destroy();
            _check(cancellation);
          }
          connected = true;
          return socket;
        }),
        task.cancel,
      );
    };
    cancellation.onCancel(() => client.close(force: true));
    _clients.add(client);
    try {
      return await (() async {
        final request = await client.openUrl(
          action == null ? 'GET' : 'POST',
          wireUri,
        );
        request.followRedirects = false;
        if (action != null) {
          request.headers.set('SOAPAction', '"$action"');
          request.headers.contentType = ContentType(
            'text',
            'xml',
            charset: 'utf-8',
          );
          request.add(utf8.encode(body!));
        }
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 256 * 1024) {
            throw const AppFailure(AppFailureKind.protocol, '投屏设备响应过大');
          }
          bytes.addAll(chunk);
        }
        _check(cancellation);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw const AppFailure(
            AppFailureKind.playback,
            '投屏设备拒绝了操作，请检查设备状态后重试',
          );
        }
        return utf8.decode(bytes);
      })().timeout(timeout);
    } on TimeoutException {
      _check(cancellation);
      const failure = AppFailure(
        AppFailureKind.timeout,
        '投屏设备响应超时，请检查电视播放状态后重试',
      );
      if (action != null && !connected) throw _DlnaConnectionFailure(failure);
      throw failure;
    } on IOException {
      _check(cancellation);
      const failure = AppFailure(
        AppFailureKind.network,
        '无法连接投屏设备，请确认设备与本机在同一局域网',
      );
      if (action != null && !connected) throw _DlnaConnectionFailure(failure);
      throw failure;
    } on FormatException {
      throw const AppFailure(AppFailureKind.protocol, '投屏设备返回了无法识别的数据');
    } finally {
      client.close(force: true);
      _clients.remove(client);
    }
  }

  void _check(RequestCancellation cancellation) {
    if (cancellation.isCancelled || _disposed) {
      throw const AppFailure(AppFailureKind.cancelled, '投屏操作已取消');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final search in _searches.toList()) {
      search.cancel();
    }
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
    _endpoints.clear();
    _preferred.clear();
  }
}

final class _DlnaEndpoint {
  const _DlnaEndpoint(this.device, this.network);
  final CastDevice device;
  final DlnaNetworkAddress? network;
  String get key => '${network?.key}/${device.controlUri}';
}

final class _DlnaConnectionFailure implements Exception {
  const _DlnaConnectionFailure(this.failure);
  final AppFailure failure;
}

String _child(XmlElement element, String name) =>
    element.childElements
        .where((node) => node.name.local == name)
        .firstOrNull
        ?.innerText
        .trim() ??
    '';
