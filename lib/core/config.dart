class AppConfig {
  // Remote server (production)
  // static const String baseUrl = 'https://taleeb.me/api/v1';

  // Local development server
  static const String baseUrl = 'http://taleeb.ddns.net:8080';

  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
