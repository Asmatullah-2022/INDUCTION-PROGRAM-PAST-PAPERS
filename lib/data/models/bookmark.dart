enum BookmarkTargetType { paper, mcq, short, long }

extension BookmarkTargetTypeX on BookmarkTargetType {
  static BookmarkTargetType fromString(String value) {
    switch (value) {
      case 'paper':
        return BookmarkTargetType.paper;
      case 'short':
        return BookmarkTargetType.short;
      case 'long':
        return BookmarkTargetType.long;
      default:
        return BookmarkTargetType.mcq;
    }
  }

  String get dbValue => switch (this) {
        BookmarkTargetType.paper => 'paper',
        BookmarkTargetType.mcq => 'mcq',
        BookmarkTargetType.short => 'short',
        BookmarkTargetType.long => 'long',
      };
}

class Bookmark {
  final String id;
  final String userId;
  final BookmarkTargetType targetType;
  final String targetId; // paper_id or question_id depending on type
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.userId,
    required this.targetType,
    required this.targetId,
    required this.createdAt,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        targetType: BookmarkTargetTypeX.fromString(json['target_type'] as String),
        targetId: json['target_id'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'target_type': targetType.dbValue,
        'target_id': targetId,
        'created_at': createdAt.toIso8601String(),
      };
}
