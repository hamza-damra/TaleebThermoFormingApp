class AppConfig {
  static const String baseUrl = 'http://192.168.1.5:8080/api/v1';

  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
