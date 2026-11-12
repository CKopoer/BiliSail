import 'dart:async';

import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_reservation_repository.dart';

import 'dynamic_fakes.dart';

const reservation = DynamicReservation(
  id: '9007199254740993123',
  status: 1,
  type: 2,
  total: 10,
  description: '10人预约',
);

class DynamicReservationFake extends DynamicRepositoryFake
    implements DynamicReservationRepository {
  final reservations = <(String, int, int)>[];
  Completer<DynamicReservation>? pending;
  @override
  Future<DynamicReservation> reserve(
    String dynamicId,
    DynamicReservation value,
    RequestCancellation cancellation,
  ) async {
    reservations.add((dynamicId, value.status, value.total));
    lastCancellation = cancellation;
    if (error case final e?) throw e;
    return pending?.future ??
        value.updated(
          value.checked ? 1 : 2,
          value.total + (value.checked ? -1 : 1),
          value.checked ? '已取消' : '预约成功',
        );
  }
}

DynamicContentCard reservationCard({DynamicReservation value = reservation}) =>
    DynamicContentCard(
      kind: DynamicCardKind.reservation,
      title: '明晚直播',
      description: '明天20点',
      actionLabel: value.label,
      actionUrl: Uri.https('t.bilibili.com', '/100'),
      url: Uri.https('t.bilibili.com', '/100'),
      reservation: value,
    );
