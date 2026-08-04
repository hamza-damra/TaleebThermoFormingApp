/// A **sanitized** urgent manager announcement for the Palletizing App.
///
/// The Palletizing App only ever receives a generic notice telling the operator
/// to open the operator app to read the real message — it **never** receives the
/// real message body or sender. Declaring no `messageBody` / `senderDisplayName`
/// field here is the structural enforcement of that privacy rule: even if a
/// future backend bug sent such fields, there is nowhere to parse them into.
///
/// See [docs/PALLETIZING_URGENT_ANNOUNCEMENTS_HANDOFF.md].
class ManagerAnnouncement {
  /// Server id. The only field used for ack + client-side dedupe across lines.
  final int id;

  /// Always `THERMOFORMING` for notices this app surfaces.
  final String targetDomain;

  /// Fixed generic title (e.g. "ملاحظة عاجلة من المدير"). The overlay renders a
  /// hardcoded constant rather than this value — see the overlay widget.
  final String title;

  /// Fixed generic body. Rendered as a hardcoded constant by the overlay.
  final String message;

  /// ISO-8601 creation timestamp, when parseable. Used only for oldest-first
  /// ordering.
  final DateTime? createdAt;

  /// Backend-formatted Arabic timestamp (e.g. "2026-06-10، 06:10 مساءً"). This
  /// is the only server-provided string the overlay renders.
  final String createdAtDisplay;

  /// Priority discriminator (e.g. `URGENT`).
  final String priority;

  /// Absolute ISO-8601 UTC moment the announcement stops being relevant, or
  /// `null` when it never expires (also `null` on a legacy backend row).
  ///
  /// The backend already excludes expired rows from the pending endpoint; this
  /// exists so the notice can also disappear locally on the exact second
  /// instead of waiting for the next re-fetch.
  final DateTime? expiresAt;

  /// Backend-formatted Arabic expiry timestamp, or `null`. Parsed for contract
  /// parity — the overlay deliberately does not render it (no new UI strings).
  final String? expiresAtDisplay;

  const ManagerAnnouncement({
    required this.id,
    required this.targetDomain,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.createdAtDisplay,
    required this.priority,
    this.expiresAt,
    this.expiresAtDisplay,
  });

  /// `true` once [expiresAt] has passed. Boundary-exclusive, mirroring the
  /// backend filter `expiresAt > now`. Always `false` when [expiresAt] is
  /// `null` (never expires).
  ///
  /// [DateTime.isBefore] compares absolute instants, so a UTC `…Z` [expiresAt]
  /// and a local [now] compare correctly without conversion.
  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !now.isBefore(expiresAt!);
}
