import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers/auth_providers.dart';

/// Client-side gate for admin screens — a UX convenience only. The real
/// enforcement is server-side: every write to official content tables is
/// blocked by Supabase RLS unless profiles.is_admin is true for the
/// requesting user (see supabase/migrations/002_rls.sql).
class AdminGuard extends ConsumerWidget {
  final Widget child;
  const AdminGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdminAsync = ref.watch(isAdminProvider);
    return isAdminAsync.when(
      data: (isAdmin) => isAdmin
          ? child
          : const Scaffold(
              body: Center(child: Text('You do not have access to this area.')),
            ),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('$e'))),
    );
  }
}
