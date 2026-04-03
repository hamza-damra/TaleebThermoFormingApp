import 'package:dio/dio.dart';

import '../../core/config.dart';
import '../../core/exceptions/api_exception.dart';
import 'auth_local_storage.dart';

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
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // For palletizing-line endpoints, use X-Device-Key header (no JWT)
    if (options.path.contains('/palletizing-line/')) {
      final deviceKey = await _authStorage.getDeviceKey();
      if (deviceKey != null && deviceKey.isNotEmpty) {
        options.headers['X-Device-Key'] = deviceKey;
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
    handler.next(options);
  }

  void _onError(DioException error, ErrorInterceptorHandler handler) {
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
        if (statusCode == 401) {
          // Try to parse the response body for a specific error code first
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
