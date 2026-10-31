import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/playback/application/casting_controller.dart';
import 'package:bilisail/features/playback/domain/casting.dart';
import 'package:flutter/foundation.dart';

CastDevice castDevice(String id) => CastDevice(
  id: id,
  name: '客厅电视 $id',
  controlUri: Uri.parse('http://192.168.1.2/control'),
  serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
);

class FakeCastMedia implements CastMediaRepository {
  Completer<Uri>? pending;
  RequestCancellation? token;
  int calls = 0;
  @override
  Future<Uri> resolve(
    CastMediaRequest request, {
    required RequestCancellation cancellation,
  }) async {
    calls++;
    token = cancellation;
    return pending?.future ??
        Uri.parse('https://cdn.example/video.mp4?sign=fixture');
  }
}

class FakeCastDevices implements CastDeviceRepository {
  List<CastDevice> found = [castDevice('a'), castDevice('b')];
  final calls = <String>[];
  Completer<void>? pendingCommand;
  CastCommand? failCommand;
  bool disposed = false;
  RequestCancellation? searchToken;
  @override
  Stream<CastDevice> discover({required RequestCancellation cancellation}) {
    searchToken = cancellation;
    return Stream.fromIterable(found);
  }

  @override
  Future<void> setMedia(
    CastDevice device,
    Uri uri,
    String title, {
    required RequestCancellation cancellation,
  }) async {
    calls.add('set:${device.id}');
  }

  @override
  Future<void> command(
    CastDevice device,
    CastCommand command, {
    required RequestCancellation cancellation,
  }) async {
    calls.add('${command.name}:${device.id}');
    if (failCommand == command) {
      throw const AppFailure(AppFailureKind.playback, '设备操作失败');
    }
    await pendingCommand?.future;
  }

  @override
  void dispose() => disposed = true;
}

class CastingHarness {
  final media = FakeCastMedia();
  final devices = FakeCastDevices();
  final source = ValueNotifier(0);
  RequestCancellation? lifetime;
  bool current = true, untracked = false;
  int localPauses = 0;
  late final controller = CastingController(
    request: const CastMediaRequest(aid: '1', cid: '2', quality: 80),
    title: '投屏测试',
    mediaRepository: media,
    deviceRepository: devices,
    pauseLocal: () async {
      localPauses++;
    },
    isCurrent: () => current,
    source: source,
    trackLifetime: (token) {
      lifetime = token;
      return () {
        untracked = true;
      };
    },
  );
  void dispose() {
    controller.dispose();
    source.dispose();
  }
}
