import '../../domain/entities/manager_announcement.dart';

/// DTO for the sanitized pending-announcements endpoint:
/// `GET /palletizing-line/urgent-announcements/pending?lineId={lineId}`.
///
/// **Privacy:** [fromJson] deliberately reads only the sanitized fields. It
/// never reads `messageBody` or `senderDisplayName` — even if a future backend
/// bug were to include them, they are dropped here and can never reach the UI.
class ManagerAnnouncementModel extends ManagerAnnouncement {
  const ManagerAnnouncementModel({
    required super.id,
    required super.targetDomain,
    required super.title,
    required super.message,
    required super.createdAt,
    required super.createdAtDisplay,
    required super.priority,
  });

  factory ManagerAnnouncementModel.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['createdAt'];
    return ManagerAnnouncementModel(
      id: json['id'] as int,
      targetDomain: json['targetDomain'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      createdAt: createdAtRaw is String && createdAtRaw.isNotEmpty
          ? DateTime.tryParse(createdAtRaw)
          : null,
      createdAtDisplay: json['createdAtDisplay'] as String? ?? '',
      priority: json['priority'] as String? ?? '',
    );
  }
}
