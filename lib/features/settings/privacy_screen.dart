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
            'AI Teacher',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'If you use AI Teacher, your messages and its responses are stored under '
            'your account so you can revisit past conversations. This data is never '
            'shared with anyone else and is used only to provide the AI Teacher '
            'feature and enforce a daily usage limit. AI Teacher responses are '
            'clearly labelled as AI-generated and are never treated as official '
            'verified answers.',
          ),
          SizedBox(height: 16),
          Text(
            'Downloads',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Files you download (answer keys, solved questions, original papers) are '
            'saved only on your own device\'s local storage. We do not track what you '
            'download; the Downloads screen simply lists files already saved on your '
            'device.',
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
            'practice attempts, and AI Teacher conversations.',
          ),
          SizedBox(height: 16),
          Text(
            'Account Deletion',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'You may delete your account at any time from Profile > Delete Account. '
            'This permanently removes your profile, bookmarks, practice attempts, '
            'progress data, and AI Teacher conversations, and clears any files this '
            'app saved on your device.',
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
