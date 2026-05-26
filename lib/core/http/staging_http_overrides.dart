import 'dart:io';

/// Process-wide [HttpOverrides] that accepts a bad TLS certificate ONLY for
/// the staging hosts passed at construction time. Every other host (including
/// `taleeb.me`) keeps normal certificate validation.
///
/// Install this in `main()` and only when [AppConfig.allowStagingSelfSignedCert]
/// is true — that getter is itself gated on the build being non-production.
class StagingSelfSignedHttpOverrides extends HttpOverrides {
  StagingSelfSignedHttpOverrides(this.allowedHosts);

  final Set<String> allowedHosts;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      return allowedHosts.contains(host);
    };
    return client;
  }
}
