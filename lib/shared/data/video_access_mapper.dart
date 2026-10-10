import 'package:bili_api/bili_api.dart';

import '../../domain/video_access.dart';

VideoAccess mapVideoAccess(ApiVideoAccess access) => VideoAccess(
  kind: switch (access.kind) {
    ApiVideoAccessKind.normal => VideoAccessKind.normal,
    ApiVideoAccessKind.chargingExclusive => VideoAccessKind.chargingExclusive,
    ApiVideoAccessKind.paid => VideoAccessKind.paid,
  },
  canWatch: access.canWatch,
  canPreview: access.canPreview,
);
