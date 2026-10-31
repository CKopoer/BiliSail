import '../models.dart';

enum ApiAppFeedbackKind { dislike, feedback }

final class ApiAppFeedbackReason {
  const ApiAppFeedbackReason({
    required this.id,
    required this.name,
    required this.kind,
  });
  final String id, name;
  final ApiAppFeedbackKind kind;
}

final class ApiAppRecommendation {
  const ApiAppRecommendation({
    required this.video,
    required this.aid,
    required this.reasons,
    required this.cardGoto,
    required this.param,
    this.navigationUri,
  });
  final ApiVideoSummary video;
  final String? aid;
  final String cardGoto, param;
  final Uri? navigationUri;
  final List<ApiAppFeedbackReason> reasons;
}

final class ApiAppQrCode {
  const ApiAppQrCode({required this.url, required this.authCode});
  final Uri url;
  final String authCode;
}

final class ApiAppCredentials {
  const ApiAppCredentials({
    required this.mid,
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
  });
  final String mid, accessToken;
  final DateTime expiresAt;
  final String? refreshToken;
}

final class ApiAppQrPoll {
  const ApiAppQrPoll(this.status, {this.credentials, this.cookies = const []});
  final ApiQrStatus status;
  final ApiAppCredentials? credentials;
  final List<ApiLoginCookie> cookies;
}

final class ApiLoginCookie {
  const ApiLoginCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.expires,
    this.path = '/',
    this.secure = true,
  });
  final String name, value, domain;
  final DateTime? expires;
  final String path;
  final bool secure;
}
