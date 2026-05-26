import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import '../../core/exceptions/api_exception.dart';
import 'auth_local_storage.dart';

/// Path of the bootstrap endpoint, relative to [AppConfig.baseUrl]. Used to
/// gate always-on (release-visible) diagnostic logging — every other endpoint
/// stays on the existing kDebugMode-only logs to avoid logcat spam in
/// production.
const String _bootstrapPath = '/palletizing-line/bootstrap';

class ApiClient {
  late final Dio dio;
  final AuthLocalStorage _authStorage;

  ApiClient({AuthLocalStorage? authStorage})
    : _authStorage = authStorage ?? AuthLocalStorage() {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        sendTimeout: AppConfig.sendTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onResponse: _onResponse,
        onError: _onError,
      ),
    );
  }

  /// Path heuristic — `/palletizing-line/*` endpoints are authenticated by the
  /// `X-Device-Key` header. A 401 / 403 on any of them is a device-key issue,
  /// not a credentials / PIN issue.
  static bool _isDeviceKeyEndpoint(String path) =>
      path.contains('/palletizing-line/');

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    bool deviceKeyAttached = false;
    int deviceKeyLength = 0;
    // For palletizing-line endpoints, use X-Device-Key header (no JWT)
    if (options.path.contains('/palletizing-line/')) {
      final deviceKey = await _authStorage.getDeviceKey();
      if (deviceKey != null && deviceKey.isNotEmpty) {
        options.headers['X-Device-Key'] = deviceKey;
        deviceKeyAttached = true;
        deviceKeyLength = deviceKey.length;
      }
      // Remove any JWT Authorization header for device-key endpoints
      options.headers.remove('Authorization');
    } else {
      // For legacy endpoints, use JWT Bearer token
      final token = await _authStorage.getToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    // Always-on diagnostic for the bootstrap call — survives release-mode
    // tree-shaking of kDebugMode branches so `adb logcat` shows it on a
    // production tablet. Logs the FULL effective URL (baseUrl + path) so a
    // mismatch between AppConfig.baseUrl and the repository path (the
    // double-/api/v1 bug) is visible at a glance, plus the key LENGTH (never
    // the value) to confirm the header is being attached.
    if (options.path == _bootstrapPath) {
      debugPrint(
        '[Bootstrap REQUEST] url=${options.uri} '
        'method=${options.method} '
        'hasDeviceKey=$deviceKeyAttached '
        'keyLength=$deviceKeyLength '
        'headerName=X-Device-Key',
      );
    } else if (kDebugMode) {
      // Other endpoints stay on the kDebugMode-only log to avoid logcat spam
      // in production builds.
      debugPrint(
        '[ApiClient] -> ${options.method} ${options.path} '
        'xDeviceKey=$deviceKeyAttached',
      );
    }
    handler.next(options);
  }

  void _onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final reqPath = response.requestOptions.path;
    if (reqPath == _bootstrapPath) {
      final body = response.data;
      String? code;
      bool? success;
      List<String> topKeys = const [];
      int bodyLength = 0;
      if (body is Map<String, dynamic>) {
        success = body['success'] as bool?;
        topKeys = body.keys.toList();
        final err = body['error'];
        if (err is Map<String, dynamic>) code = err['code'] as String?;
        bodyLength = body.toString().length;
      } else if (body is String) {
        bodyLength = body.length;
      }
      debugPrint(
        '[Bootstrap RESPONSE] status=${response.statusCode} '
        'success=$success '
        'bodyLength=$bodyLength '
        'topKeys=$topKeys '
        '${code != null ? 'errorCode=$code' : ''}',
      );
    } else if (kDebugMode) {
      final body = response.data;
      String? code;
      bool? success;
      if (body is Map<String, dynamic>) {
        success = body['success'] as bool?;
        final err = body['error'];
        if (err is Map<String, dynamic>) code = err['code'] as String?;
      }
      debugPrint(
        '[ApiClient] <- ${response.requestOptions.method} '
        '${response.requestOptions.path} '
        'status=${response.statusCode} success=$success '
        '${code != null ? 'code=$code' : ''}',
      );
    }
    handler.next(response);
  }

  void _onError(DioException error, ErrorInterceptorHandler handler) {
    final reqPath = error.requestOptions.path;
    final status = error.response?.statusCode;
    if (reqPath == _bootstrapPath) {
      // Always-on: this is the single line a tablet operator needs to see when
      // bootstrap fails outright. Includes the full URL, the Dio exception
      // type (timeout / connectionError / badResponse), and the raw error
      // message — covers SocketException, HandshakeException, TimeoutException,
      // FormatException, "cleartext HTTP not permitted", bad certificate, DNS
      // failure. Never includes the device key or operator data.
      debugPrint(
        '[Bootstrap ERROR] url=${error.requestOptions.uri} '
        'status=$status '
        'type=${error.type} '
        'message=${error.message} '
        'innerError=${error.error?.runtimeType}',
      );
    } else if (kDebugMode) {
      debugPrint(
        '[ApiClient] !! ${error.requestOptions.method} '
        '${error.requestOptions.path} '
        'status=$status type=${error.type}',
      );
    }
    handler.next(error);
  }

  Future<T> request<T>({
    required String path,
    required String method,
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    required T Function(Map<String, dynamic>) parser,
  }) async {
    try {
      final response = await dio.request(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method),
      );

      final responseData = response.data as Map<String, dynamic>;
      if (responseData['success'] == true) {
        return parser(responseData);
      } else {
        throw ApiException.fromJson(
          responseData,
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  Future<List<T>> requestList<T>({
    required String path,
    required String method,
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    required T Function(Map<String, dynamic>) itemParser,
  }) async {
    try {
      final response = await dio.request(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method),
      );

      final responseData = response.data as Map<String, dynamic>;
      if (responseData['success'] == true) {
        final dataList = responseData['data'] as List<dynamic>;
        return dataList
            .map((item) => itemParser(item as Map<String, dynamic>))
            .toList();
      } else {
        throw ApiException.fromJson(
          responseData,
          statusCode: response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioException(e);
    }
  }

  ApiException _handleDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException.timeout();
      case DioExceptionType.connectionError:
        return ApiException.network();
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final path = e.requestOptions.path;
        // Device-key endpoints: a 401 / 403 here can ONLY mean the X-Device-Key
        // was rejected — the palletizing-line backend never gates these on a
        // user credential. Surface a dedicated, actionable code so the UI
        // routes to the device-settings recovery flow instead of showing a
        // misleading "بيانات الدخول غير صحيحة" credentials message.
        if ((statusCode == 401 || statusCode == 403) &&
            _isDeviceKeyEndpoint(path)) {
          return ApiException.deviceKeyInvalid(statusCode: statusCode);
        }
        if (statusCode == 401) {
          // Non-device-key 401 — try to parse the response body for a specific
          // error code first (e.g. legacy `/auth/*` endpoints).
          if (e.response?.data is Map<String, dynamic>) {
            final body = e.response!.data as Map<String, dynamic>;
            final error = body['error'] as Map<String, dynamic>?;
            if (error != null && error['code'] != null) {
              return ApiException.fromJson(body, statusCode: statusCode);
            }
          }
          return ApiException.unauthorized();
        }
        if (e.response?.data is Map<String, dynamic>) {
          return ApiException.fromJson(
            e.response!.data as Map<String, dynamic>,
            statusCode: statusCode,
          );
        }
        return ApiException(
          code: 'SERVER_ERROR',
          message: 'خطأ في الخادم',
          statusCode: statusCode,
        );
      default:
        return ApiException.network();
    }
  }
}
