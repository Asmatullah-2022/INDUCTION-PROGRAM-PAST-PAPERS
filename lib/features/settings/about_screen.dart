import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About App')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(AppConstants.appName,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          const Text(
            'Induction Program Past Papers is an independent educational preparation '
            'resource for newly recruited government teachers in Khyber Pakhtunkhwa, '
            'Pakistan, preparing for the Teacher Induction Program examinations.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Disclaimer: This app is not an official government application and is not '
            'affiliated with, endorsed by, or operated by the Government of Khyber '
            'Pakhtunkhwa or any of its departments unless explicitly stated otherwise. '
            'Original papers reproduced in this app are provided for educational '
            'preparation purposes with appropriate attribution where applicable.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Content accuracy: Every effort is made to verify questions and answers '
            'independently. Where a discrepancy exists between an original paper\'s '
            'marked answer and the academically verified answer, both are shown '
            'clearly with a quality-check indicator.',
          ),
        ],
      ),
    );
  }
}
