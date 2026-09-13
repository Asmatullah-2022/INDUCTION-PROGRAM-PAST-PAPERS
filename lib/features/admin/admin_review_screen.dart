import 'package:flutter/material.dart';

import '../../shared/widgets/state_widgets.dart';
import 'admin_guard.dart';

/// Placeholder for the human-review workflow (spec section 63): admins
/// will triage QUESTIONABLE / PAPER_ERROR / OCR_UNCERTAIN / ANSWER_UNCERTAIN
/// questions here before they can move to VERIFIED/PUBLISHED. Full CRUD
/// admin screens (paper upload, question editor, etc.) are a deliberately
/// separate follow-up build — see CLAUDE.md.
class AdminReviewScreen extends StatelessWidget {
  const AdminReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Review Questionable Questions')),
        body: const EmptyState(
          icon: Icons.construction_outlined,
          title: 'Admin content-review screens are not yet built',
          subtitle:
              'This first release ships the QA dashboard and role enforcement. '
              'Full question review/edit UI is planned for the admin follow-up build.',
        ),
      ),
    );
  }
}
