import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/repository_providers.dart';
import '../../shared/widgets/state_widgets.dart';
import '../auth/providers/auth_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profileAsync.when(
        data: (profile) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                profile.fullName.isNotEmpty ? profile.fullName[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(profile.fullName,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Center(child: Text(profile.email)),
            const SizedBox(height: 24),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: const Text('Mobile'),
                    subtitle: Text(profile.mobileNumber ?? '-'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: const Text('District'),
                    subtitle: Text(profile.district ?? '-'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit Profile'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showEditProfileSheet(context, ref, profile.fullName,
                        profile.mobileNumber, profile.district),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.lock_reset_outlined),
                    title: const Text('Change Password'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/reset-password'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.bookmark_outline),
                    title: const Text('My Bookmarks'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/bookmarks'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.trending_up),
                    title: const Text('My Progress'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/progress'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error),
                    title: Text('Delete Account',
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    onTap: () => _confirmDeleteAccount(context, ref),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Logout'),
                    onTap: () async {
                      await ref.read(authRepositoryProvider).signOut();
                      if (context.mounted) context.go('/login');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        loading: () => const LoadingList(itemCount: 4),
        error: (e, st) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(myProfileProvider),
        ),
      ),
    );
  }

  void _showEditProfileSheet(BuildContext context, WidgetRef ref, String fullName,
      String? mobile, String? district) {
    final fullNameController = TextEditingController(text: fullName);
    final mobileController = TextEditingController(text: mobile ?? '');
    final districtController = TextEditingController(text: district ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit Profile', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: fullNameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mobileController,
              decoration: const InputDecoration(labelText: 'Mobile Number'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: districtController,
              decoration: const InputDecoration(labelText: 'District'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                await ref.read(profileRepositoryProvider).updateProfile(
                      fullName: fullNameController.text.trim(),
                      mobileNumber: mobileController.text.trim(),
                      district: districtController.text.trim(),
                    );
                ref.invalidate(myProfileProvider);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and associated data '
          'according to our data-retention policy. This cannot be undone. '
          'Are you sure you want to continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.of(context).pop();
              await ref.read(authRepositoryProvider).deleteAccount();
              if (context.mounted) context.go('/login');
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
