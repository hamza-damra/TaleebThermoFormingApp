import 'palletizer_session.dart';

class PalletizerAuthResult {
  final PalletizerSession session;
  final String sessionToken;

  const PalletizerAuthResult({
    required this.session,
    required this.sessionToken,
  });
}
