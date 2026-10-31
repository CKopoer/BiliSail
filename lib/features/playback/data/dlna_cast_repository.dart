import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/casting.dart';

/// SSDP discovery and AVTransport control use no account headers or cookies.
final class DlnaCastRepository implements CastDeviceRepository {
  DlnaCastRepository({
    this.searchDuration = const Duration(seconds: 12),
    InternetAddress? discoveryAddress,
    this.discoveryPort = 1900,
  }) : discoveryAddress =
           discoveryAddress ?? InternetAddress('239.255.255.250');
  final Duration searchDuration;
  final InternetAddress discoveryAddress;
  final int discoveryPort;
  final _clients = <HttpClient>{};
  final _searches = <RequestCancellation>{};
  bool _disposed = false;

  @override
  Stream<CastDevice> discover({
    required RequestCancellation cancellation,
  }) async* {
    final search = RequestCancellation();
    cancellation.onCancel(search.cancel);
    _searches.add(search);
    RawDatagramSocket? socket;
    Timer? timer;
    try {
      _check(search);
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      search.onCancel(socket.close);
      _check(search);
      timer = Timer(searchDuration, search.cancel);
      // Replies are unicast to this ephemeral port; no multicast subscription.
      for (final target in const [
        'urn:schemas-upnp-org:device:MediaRenderer:1',
        'urn:schemas-upnp-org:service:AVTransport:1',
      ]) {
        socket.send(
          ascii.encode(
            'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n'
            'MAN: "ssdp:discover"\r\nMX: 3\r\nST: $target\r\n\r\n',
          ),
          discoveryAddress,
          discoveryPort,
        );
      }
      final locations = <String>{};
      final devices = <String>{};
      await for (final event in socket) {
        if (event != RawSocketEvent.read) continue;
        final packet = socket.receive();
        if (packet == null || packet.data.length > 16384) continue;
        final lines = latin1.decode(packet.data).split(RegExp(r'\r?\n'));
        if (lines.isEmpty ||
            !RegExp(r'^HTTP/1\.[01] 200\b').hasMatch(lines.first)) {
          continue;
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
        final location = Uri.tryParse(headers['location'] ?? '');
        if (location == null ||
            !_httpUri(location) ||
            location.host != packet.address.address ||
            locations.length >= 64 ||
            !locations.add(location.toString())) {
          continue;
        }
        try {
          final xml = await _request(location, search);
          _check(search);
          for (final device in parseDescription(xml, location)) {
            if (devices.length < 64 && devices.add(device.id)) yield device;
          }
        } on AppFailure {
          // A malformed/unreachable renderer must not hide the other devices.
          if (search.isCancelled) break;
        }
      }
    } on SocketException {
      if (!search.isCancelled) {
        throw const AppFailure(
          AppFailureKind.network,
          '无法搜索投屏设备，请检查局域网权限和网络连接',
        );
      }
    } finally {
      timer?.cancel();
      socket?.close();
      search.cancel();
      _searches.remove(search);
    }
  }

  static List<CastDevice> parseDescription(String xml, Uri location) {
    try {
      final document = XmlDocument.parse(xml);
      if (document.children.any((node) => node is XmlDoctype)) return const [];
      final baseText = _child(document.rootElement, 'URLBase');
      final base = baseText.isEmpty ? location : location.resolve(baseText);
      if (!_httpUri(base) || base.host != location.host) return const [];
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
            .expand((node) => node.childElements);
        for (final service in services) {
          final type = _child(service, 'serviceType');
          final path = _child(service, 'controlURL');
          if (!RegExp(r'^urn:schemas-upnp-org:service:AVTransport:[1-9][0-9]*$')
                  .hasMatch(type) ||
              path.isEmpty) {
            continue;
          }
          final control = base.resolve(path);
          if (!_httpUri(control) || control.host != location.host) continue;
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
    Uri uri,
    String title, {
    required RequestCancellation cancellation,
  }) {
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
    return _action(device, 'SetAVTransportURI', {
      'CurrentURI': uri.toString(),
      'CurrentURIMetaData': root.toXmlString(),
    }, cancellation);
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

  Future<void> _action(
    CastDevice device,
    String action,
    Map<String, String> arguments,
    RequestCancellation cancellation,
  ) async {
    if (!RegExp(r'^urn:schemas-upnp-org:service:AVTransport:[1-9][0-9]*$')
        .hasMatch(device.serviceType)) {
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
          attributes: {'xmlns:u': device.serviceType},
          nest: () {
            for (final entry in {'InstanceID': '0', ...arguments}.entries) {
              builder.element(entry.key, nest: entry.value);
            }
          },
        ),
      ),
    );
    final xml = await _request(
      device.controlUri,
      cancellation,
      action: '${device.serviceType}#$action',
      body: builder.buildDocument().toXmlString(),
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
  }) async {
    _check(cancellation);
    if (!_httpUri(uri)) {
      throw const AppFailure(AppFailureKind.protocol, '投屏设备地址无效');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    cancellation.onCancel(() => client.close(force: true));
    _clients.add(client);
    try {
      return await (() async {
        final request = await client.openUrl(
          action == null ? 'GET' : 'POST',
          uri,
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
      })().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      throw const AppFailure(AppFailureKind.timeout, '投屏设备响应超时，请检查电视播放状态后重试');
    } on IOException {
      _check(cancellation);
      throw const AppFailure(AppFailureKind.network, '无法连接投屏设备，请确认设备与本机在同一局域网');
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
  }
}

bool _httpUri(Uri uri) =>
    const {'http', 'https'}.contains(uri.scheme) &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    uri.fragment.isEmpty;

String _child(XmlElement element, String name) =>
    element.childElements
        .where((node) => node.name.local == name)
        .firstOrNull
        ?.innerText
        .trim() ??
    '';
