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

/// Optional bounded reads stop receiving once the decompressed byte cap is hit.
abstract interface class ApiBoundedTransport {
  Future<ApiHttpResponse> getBounded(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    required int maxBytes,
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

abstract interface class ApiMultipartTransport {
  Future<ApiHttpResponse> postMultipart(
    Uri uri, {
    required Map<String, String> fields,
    required Uint8List bytes,
    required String mimeType,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  });
}

final class DioApiTransport
    implements
        ApiTransport,
        ApiFormTransport,
        ApiJsonTransport,
        ApiMultipartTransport,
        ApiBoundedTransport {
  DioApiTransport({Dio? dio}) : _dio = dio ?? Dio();
  final Dio _dio;

  @override
  Future<ApiHttpResponse> getBounded(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    required int maxBytes,
    ApiCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled == true) {
      throw const ApiFailure(ApiFailureCategory.cancelled, 'transport');
    }
    final token = CancelToken();
    cancellation?.whenCancelled.then((_) => token.cancel());
    Future<ApiHttpResponse> receive() async {
      final response = await _dio.get<ResponseBody>(
        uri.toString(),
        cancelToken: token,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (_) => true,
          receiveTimeout: timeout,
          connectTimeout: timeout,
        ),
      );
      final body = BytesBuilder(copy: false);
      final stream = response.data?.stream;
      if (stream != null) {
        await for (final chunk in stream) {
          if (body.length + chunk.length > maxBytes) {
            token.cancel();
            throw const ApiFailure(ApiFailureCategory.protocol, 'transport');
          }
          body.add(chunk);
        }
      }
      return ApiHttpResponse(
        response.statusCode ?? 0,
        body.takeBytes(),
        response.headers.map,
      );
    }

    try {
      return await receive().timeout(
        timeout,
        onTimeout: () {
          token.cancel();
          throw const ApiFailure(ApiFailureCategory.timeout, 'transport');
        },
      );
    } on DioException catch (error) {
      throw ApiFailure(switch (error.type) {
        DioExceptionType.cancel => ApiFailureCategory.cancelled,
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => ApiFailureCategory.timeout,
        _ => ApiFailureCategory.network,
      }, 'transport');
    } on FormatException {
      throw const ApiFailure(ApiFailureCategory.protocol, 'transport');
    } on ApiFailure {
      rethrow;
    } on Exception {
      // A streamed IO/decompression failure may arrive after Dio returned the
      // response headers. Keep it inside the transport failure boundary.
      throw const ApiFailure(ApiFailureCategory.network, 'transport');
    }
  }

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
    Object? body,
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
  Future<ApiHttpResponse> postMultipart(
    Uri uri, {
    required Map<String, String> fields,
    required Uint8List bytes,
    required String mimeType,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => _send(
    uri,
    headers: headers,
    timeout: timeout,
    cancellation: cancellation,
    contentType: Headers.multipartFormDataContentType,
    body: FormData.fromMap({
      ...fields,
      'file_up': MultipartFile.fromBytes(
        bytes,
        filename:
            'comment.${mimeType == 'image/png'
                ? 'png'
                : mimeType == 'image/gif'
                ? 'gif'
                : 'jpg'}',
        contentType: DioMediaType.parse(mimeType),
      ),
    }),
  );

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
