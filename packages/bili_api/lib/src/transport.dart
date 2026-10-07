import 'dart:typed_data';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'models.dart';

final class ApiHttpResponse {
  const ApiHttpResponse(this.statusCode, this.body, this.headers);
  final int statusCode;
  final Uint8List body;
  final Map<String, List<String>> headers;
  List<String> header(String name) => headers[name.toLowerCase()] ?? const [];
}

abstract interface class ApiTransport {
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  });
}

/// Mutation transport deliberately has no retry contract.
abstract interface class ApiFormTransport {
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  });
}

abstract interface class ApiJsonTransport {
  Future<ApiHttpResponse> postJson(
    Uri uri, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  });
}

final class DioApiTransport
    implements ApiTransport, ApiFormTransport, ApiJsonTransport {
  DioApiTransport({Dio? dio}) : _dio = dio ?? Dio();
  final Dio _dio;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => _send(
    uri,
    headers: headers,
    timeout: timeout,
    cancellation: cancellation,
  );

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => _send(
    uri,
    headers: headers,
    timeout: timeout,
    cancellation: cancellation,
    body: Uri(queryParameters: fields).query,
  );

  Future<ApiHttpResponse> _send(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
    String? body,
    String contentType = Headers.formUrlEncodedContentType,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      throw const ApiFailure(ApiFailureCategory.cancelled, 'transport');
    }
    final token = CancelToken();
    cancellation?.whenCancelled.then((_) => token.cancel());
    try {
      final response = await _dio
          .request<List<int>>(
            uri.toString(),
            data: body,
            cancelToken: token,
            options: Options(
              method: body == null ? 'GET' : 'POST',
              contentType: body == null ? null : contentType,
              headers: headers,
              responseType: ResponseType.bytes,
              followRedirects: false,
              validateStatus: (_) => true,
              receiveTimeout: timeout,
              connectTimeout: timeout,
            ),
          )
          .timeout(
            timeout,
            onTimeout: () {
              token.cancel();
              throw const ApiFailure(ApiFailureCategory.timeout, 'transport');
            },
          );
      final responseBody = response.data ?? const <int>[];
      if (responseBody.length > 4 * 1024 * 1024) {
        throw const ApiFailure(ApiFailureCategory.protocol, 'transport');
      }
      final resultHeaders = <String, List<String>>{};
      response.headers.map.forEach((name, values) {
        resultHeaders[name.toLowerCase()] = values;
      });
      return ApiHttpResponse(
        response.statusCode ?? 0,
        Uint8List.fromList(responseBody),
        resultHeaders,
      );
    } on DioException catch (error) {
      final category = switch (error.type) {
        DioExceptionType.cancel => ApiFailureCategory.cancelled,
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => ApiFailureCategory.timeout,
        _ => ApiFailureCategory.network,
      };
      throw ApiFailure(category, 'transport');
    }
  }

  void close() => _dio.close(force: true);

  @override
  Future<ApiHttpResponse> postJson(
    Uri uri, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => _send(
    uri,
    headers: headers,
    timeout: timeout,
    cancellation: cancellation,
    body: jsonEncode(body),
    contentType: Headers.jsonContentType,
  );
}
