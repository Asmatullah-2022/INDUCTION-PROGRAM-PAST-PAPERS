import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          Text(
            'Information We Collect',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'When you create an account, we collect your full name, email address, '
            'mobile number, and district through Supabase Authentication. We also '
            'store your bookmarks, practice attempts, and progress data so you can '
            'track your own preparation across sessions.',
          ),
          SizedBox(height: 16),
          Text(
            'How We Use Your Information',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Your information is used solely to provide account access, sync your '
            'bookmarks and progress across devices, and improve the accuracy of '
            'exam content over time. We do not sell your personal information.',
          ),
          SizedBox(height: 16),
          Text(
            'Data Storage',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Data is stored securely using Supabase (PostgreSQL) with Row Level '
            'Security enabled, so you can only access your own bookmarks, progress, '
            'and practice attempts.',
          ),
          SizedBox(height: 16),
          Text(
            'Account Deletion',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'You may delete your account at any time from Profile > Delete Account. '
            'This permanently removes your profile, bookmarks, practice attempts, and '
            'progress data according to our data-retention policy.',
          ),
          SizedBox(height: 16),
          Text(
            'Contact',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text('For privacy questions, contact: YOUR_SUPPORT_EMAIL'),
        ],
      ),
    );
  }
}
