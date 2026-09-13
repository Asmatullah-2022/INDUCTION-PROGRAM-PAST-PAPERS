class AuditLog {
  final String id;
  final String? actorId;
  final String action;
  final String tableName;
  final String? recordId;
  final Map<String, dynamic>? beforeData;
  final Map<String, dynamic>? afterData;
  final DateTime createdAt;

  const AuditLog({
    required this.id,
    this.actorId,
    required this.action,
    required this.tableName,
    this.recordId,
    this.beforeData,
    this.afterData,
    required this.createdAt,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
        id: json['id'] as String,
        actorId: json['actor_id'] as String?,
        action: json['action'] as String,
        tableName: json['table_name'] as String,
        recordId: json['record_id'] as String?,
        beforeData: json['before_data'] as Map<String, dynamic>?,
        afterData: json['after_data'] as Map<String, dynamic>?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
