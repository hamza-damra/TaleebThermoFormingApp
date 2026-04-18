/// Lightweight DTO for the FALET existence check endpoint.
/// GET /api/v1/palletizing-line/lines/{lineId}/falet/exists
class FaletExistsResponse {
  final bool hasOpenFalet;
  final int openFaletCount;
  final bool requiresAction;
  final int lineId;
  final int? sessionId;

  const FaletExistsResponse({
    required this.hasOpenFalet,
    required this.openFaletCount,
    required this.requiresAction,
    required this.lineId,
    this.sessionId,
  });
}
