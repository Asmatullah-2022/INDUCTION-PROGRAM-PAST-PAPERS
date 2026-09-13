class PaperSection {
  final String id;
  final String paperId;
  final String sectionName;
  final String sectionCode;
  final int? marks;
  final String? instructions;
  final int displayOrder;

  const PaperSection({
    required this.id,
    required this.paperId,
    required this.sectionName,
    required this.sectionCode,
    this.marks,
    this.instructions,
    required this.displayOrder,
  });

  factory PaperSection.fromJson(Map<String, dynamic> json) => PaperSection(
        id: json['id'] as String,
        paperId: json['paper_id'] as String,
        sectionName: json['section_name'] as String,
        sectionCode: json['section_code'] as String,
        marks: (json['marks'] as num?)?.toInt(),
        instructions: json['instructions'] as String?,
        displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'paper_id': paperId,
        'section_name': sectionName,
        'section_code': sectionCode,
        'marks': marks,
        'instructions': instructions,
        'display_order': displayOrder,
      };
}
