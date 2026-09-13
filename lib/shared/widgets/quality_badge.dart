import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

/// Small tappable badge shown next to a question. Verified questions show
/// a quiet check; anything else shows a warning that expands into the
/// quality note on tap, so the normal reading UI stays uncluttered.
class QualityBadge extends StatelessWidget {
  final QualityStatus status;
  final String? note;

  const QualityBadge({super.key, required this.status, this.note});

  @override
  Widget build(BuildContext context) {
    final isVerified = status == QualityStatus.verified;
    final color = isVerified
        ? QualityColors.verified(context)
        : QualityColors.warning(context);

    final chip = Chip(
      avatar: Icon(
        isVerified ? Icons.check_circle : Icons.warning_amber_rounded,
        size: 16,
        color: color,
      ),
      label: Text(
        isVerified ? 'Verified' : status.label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    if (isVerified || note == null || note!.isEmpty) return chip;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _showNote(context, color),
      child: chip,
    );
  }

  void _showNote(BuildContext context, Color color) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: color),
                const SizedBox(width: 8),
                Text(
                  status.label,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: color),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(note ?? '', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
