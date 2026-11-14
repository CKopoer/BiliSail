import 'dart:io';

typedef DlnaSocketConnector = Future<ConnectionTask<Socket>> Function(
  Object host,
  int port, {
  InternetAddress? sourceAddress,
});

/// A source address and its interface, retained through discovery and control.
final class DlnaNetworkAddress {
  const DlnaNetworkAddress(this.address, this.interfaceIndex, {this.name = ''});

  final InternetAddress address;
  final int interfaceIndex;
  final String name;

  String get key =>
      '$interfaceIndex/${address.type.name}/${address.rawAddress}';

  InternetAddress scoped(InternetAddress peer) {
    final plain = InternetAddress.fromRawAddress(peer.rawAddress);
    if (plain.type == InternetAddressType.IPv6 &&
        (plain.isLinkLocal || plain.isMulticast) &&
        interfaceIndex > 0) {
      return InternetAddress('${plain.address}%$interfaceIndex');
    }
    return plain;
  }

  InternetAddress get source => scoped(address);

  Uri? location(String text, InternetAddress peer) {
    final uri = Uri.tryParse(text);
    final host = uri == null ? null : DlnaHost.parse(uri.host, uriHost: true);
    final sender = DlnaHost.parse(peer.address);
    if (uri == null ||
        !isDlnaHttpUri(uri) ||
        host == null ||
        sender == null ||
        host.address.type != address.type ||
        host.address.isMulticast ||
        host.address.rawAddress.every((byte) => byte == 0) ||
        !host.sameAddress(sender) ||
        !_acceptsZone(host.zone) ||
        !_acceptsZone(sender.zone)) {
      return null;
    }
    if (host.address.isLinkLocal &&
        host.address.type == InternetAddressType.IPv6) {
      if (interfaceIndex <= 0) return null;
      return uri.replace(host: '${host.address.address}%$interfaceIndex');
    }
    return host.zone == null ? uri.replace(host: host.address.address) : null;
  }

  bool _acceptsZone(String? zone) =>
      zone == null ||
      zone == '$interfaceIndex' ||
      (name.isNotEmpty && zone == name);
}

/// IPv6 URI hosts encode a zone separator as %25; socket addresses use %.
final class DlnaHost {
  const DlnaHost(this.address, this.zone);

  final InternetAddress address;
  final String? zone;

  static DlnaHost? parse(String text, {bool uriHost = false}) {
    final separator = text.indexOf('%');
    final plain = separator < 0 ? text : text.substring(0, separator);
    final address = InternetAddress.tryParse(plain);
    if (address == null) return null;
    String? zone;
    if (separator >= 0) {
      zone = text.substring(
        separator + (uriHost && text.startsWith('%25', separator) ? 3 : 1),
      );
      if (zone.isEmpty || !RegExp(r'^[a-zA-Z0-9_.~-]+$').hasMatch(zone)) {
        return null;
      }
    }
    return DlnaHost(InternetAddress.fromRawAddress(address.rawAddress), zone);
  }

  bool sameAddress(DlnaHost other) =>
      address.type == other.address.type &&
      address.rawAddress.indexed.every(
        (entry) => entry.$2 == other.address.rawAddress[entry.$1],
      );

  InternetAddress get socketAddress =>
      zone == null ? address : InternetAddress('${address.address}%$zone');
}

bool isDlnaHttpUri(Uri uri) =>
    const {'http', 'https'}.contains(uri.scheme) &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    uri.fragment.isEmpty;

bool sameDlnaHost(Uri first, Uri second) {
  final a = DlnaHost.parse(first.host, uriHost: true);
  final b = DlnaHost.parse(second.host, uriHost: true);
  if (a == null || b == null) return first.host == second.host;
  return a.sameAddress(b) &&
      (a.zone == null || b.zone == null || a.zone == b.zone);
}

Uri? resolveDlnaUri(Uri location, String path) {
  final uri = location.resolve(path);
  if (!isDlnaHttpUri(uri) || !sameDlnaHost(location, uri)) return null;
  final original = DlnaHost.parse(location.host, uriHost: true);
  final resolved = DlnaHost.parse(uri.host, uriHost: true);
  if (resolved?.zone != null && !resolved!.address.isLinkLocal) return null;
  if (original?.zone != null && resolved != null && resolved.zone == null) {
    return uri.replace(host: '${resolved.address.address}%${original!.zone}');
  }
  return uri;
}

abstract interface class DlnaDiscoveryTransport {
  Future<List<DlnaNetworkAddress>> addresses();
  Future<DlnaDiscoverySocket> bind(DlnaNetworkAddress network);
}

abstract interface class DlnaDiscoverySocket {
  Stream<Datagram> get packets;
  int send(List<int> bytes, InternetAddress target, int port);
  void close();
}

final class IoDlnaDiscoveryTransport implements DlnaDiscoveryTransport {
  const IoDlnaDiscoveryTransport({this.socketBinder = RawDatagramSocket.bind});

  final Future<RawDatagramSocket> Function(InternetAddress, int) socketBinder;

  @override
  Future<List<DlnaNetworkAddress>> addresses() async {
    final interfaces = await NetworkInterface.list(includeLinkLocal: true);
    final result = <DlnaNetworkAddress>[];
    final seen = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.isLoopback ||
            address.isMulticast ||
            address.rawAddress.every((byte) => byte == 0)) {
          continue;
        }
        final network = DlnaNetworkAddress(
          address,
          interface.index,
          name: interface.name,
        );
        if (seen.add(network.key)) result.add(network);
      }
    }
    // Prefer IPv4 when both families answer, while still searching every source.
    result.sort(
      (a, b) => a.address.type == b.address.type
          ? a.interfaceIndex.compareTo(b.interfaceIndex)
          : a.address.type == InternetAddressType.IPv4
          ? -1
          : 1,
    );
    return result;
  }

  @override
  Future<DlnaDiscoverySocket> bind(DlnaNetworkAddress network) async {
    final socket = await socketBinder(network.source, 0);
    try {
      socket.writeEventsEnabled = false;
      socket.multicastHops = 2;
      if (network.interfaceIndex > 0) {
        socket.setRawOption(
          network.address.type == InternetAddressType.IPv4
              ? RawSocketOption(
                  RawSocketOption.levelIPv4,
                  RawSocketOption.IPv4MulticastInterface,
                  network.address.rawAddress,
                )
              : RawSocketOption.fromInt(
                  RawSocketOption.levelIPv6,
                  RawSocketOption.IPv6MulticastInterface,
                  network.interfaceIndex,
                ),
        );
      }
      return _IoDlnaDiscoverySocket(socket);
    } catch (_) {
      socket.close();
      rethrow;
    }
  }
}

final class _IoDlnaDiscoverySocket implements DlnaDiscoverySocket {
  _IoDlnaDiscoverySocket(this.socket);
  final RawDatagramSocket socket;

  @override
  Stream<Datagram> get packets => socket.expand((event) sync* {
    if (event != RawSocketEvent.read) return;
    Datagram? packet;
    while ((packet = socket.receive()) != null) {
      yield packet!;
    }
  });

  @override
  int send(List<int> bytes, InternetAddress target, int port) =>
      socket.send(bytes, target, port);

  @override
  void close() => socket.close();
}
