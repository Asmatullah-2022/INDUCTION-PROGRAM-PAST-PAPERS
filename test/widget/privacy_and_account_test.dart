import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:induction_program_past_papers/core/services/cache_service.dart';
import 'package:induction_program_past_papers/data/models/profile.dart';
import 'package:induction_program_past_papers/features/auth/providers/auth_providers.dart';
import 'package:induction_program_past_papers/features/auth/screens/signup_screen.dart';
import 'package:induction_program_past_papers/features/profile/profile_screen.dart';
import 'package:induction_program_past_papers/features/settings/about_screen.dart';
import 'package:induction_program_past_papers/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps [child] with a minimal real GoRouter (not a stub) so tapping a
/// Privacy Policy link can be asserted to actually navigate to
/// `/privacy` — the same pattern used for AI Teacher's navigation test.
Widget _wrapWithRouter(Widget child, {List<Override> overrides = const []}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => child),
      GoRoute(path: '/privacy', builder: (context, state) => const Scaffold(body: Text('Privacy Policy Screen'))),
      GoRoute(path: '/downloads', builder: (context, state) => const Scaffold(body: Text('Downloads Screen'))),
      GoRoute(path: '/about', builder: (context, state) => const Scaffold(body: Text('About Screen'))),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  // SettingsScreen reads themeModeProvider, whose Notifier.build() calls
  // CacheService.getString — same SharedPreferences mock setup already
  // used by test/widget_test.dart to boot the real app shell.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();
  });

  group('AboutScreen — Privacy Policy link', () {
    testWidgets('shows a Privacy Policy link that navigates to /privacy', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(const AboutScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Policy'), findsOneWidget);
      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Policy Screen'), findsOneWidget);
    });
  });

  group('SettingsScreen — Privacy Policy entry point', () {
    testWidgets('shows a Privacy Policy tile that navigates to /privacy', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(const SettingsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Policy'), findsOneWidget);
      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Policy Screen'), findsOneWidget);
    });

    testWidgets('shows a Downloads entry point that navigates to /downloads', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Downloads'));
      await tester.pumpAndSettle();

      expect(find.text('Downloads Screen'), findsOneWidget);
    });
  });

  group('SignupScreen — Privacy Policy notice', () {
    testWidgets('shows a Privacy Policy link that navigates to /privacy', (tester) async {
      await tester.pumpWidget(_wrapWithRouter(const SignupScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Policy'), findsOneWidget);

      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Policy Screen'), findsOneWidget);
    });
  });

  group('ProfileScreen — account deletion entry point', () {
    testWidgets('shows a Delete Account entry point that opens a confirmation dialog', (tester) async {
      final fakeProfile = Profile(
        id: 'user-1',
        fullName: 'Test User',
        email: 'test@example.com',
        mobileNumber: '0300-0000000',
        district: 'Peshawar',
        isAdmin: false,
        createdAt: DateTime(2024, 1, 1),
      );

      await tester.pumpWidget(_wrapWithRouter(
        const ProfileScreen(),
        overrides: [
          myProfileProvider.overrideWith((ref) => fakeProfile),
        ],
      ));
      await tester.pumpAndSettle();

      // The Delete Account/Logout card is below the fold in a default test
      // viewport — ListView virtualizes it away until scrolled into view.
      await tester.scrollUntilVisible(find.text('Delete Account'), 200,
          scrollable: find.byType(Scrollable));
      await tester.pumpAndSettle();

      expect(find.text('Delete Account'), findsOneWidget);
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This will permanently delete your account and associated data '
          'according to our data-retention policy. This cannot be undone. '
          'Are you sure you want to continue?',
        ),
        findsOneWidget,
      );
    });
  });
}
