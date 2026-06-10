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

  const ManagerAnnouncement({
    required this.id,
    required this.targetDomain,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.createdAtDisplay,
    required this.priority,
  });
}
