import '../models/video_access.dart';

ApiVideoAccess parseVideoAccess(Map<String, Object?> data) {
  final rights = _map(data['rights']);
  final badge = _map(data['badge']);
  final exclusive =
      _flag(data['is_upower_exclusive']) == true ||
      _flag(data['is_charging_arc']) == true ||
      badge['text'] == '充电专属';
  final paid =
      _flag(rights['ugc_pay']) == true ||
      _flag(rights['pay']) == true ||
      _flag(rights['arc_pay']) == true ||
      _flag(data['is_pay']) == true ||
      _flag(data['is_chargeable_season']) == true;
  return ApiVideoAccess(
    kind: exclusive
        ? ApiVideoAccessKind.chargingExclusive
        : paid
        ? ApiVideoAccessKind.paid
        : ApiVideoAccessKind.normal,
    canWatch: exclusive ? _flag(data['is_upower_play']) : null,
    canPreview:
        _flag(data['is_upower_preview']) == true ||
        _flag(rights['ugc_pay_preview']) == true,
  );
}

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : const {};

bool? _flag(Object? value) => switch (value) {
  true || 1 || '1' => true,
  false || 0 || '0' => false,
  _ => null,
};
