import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/admin/admin_dashboard_screen.dart';
import '../../features/admin/admin_audit_log_screen.dart';
import '../../features/admin/admin_content_coverage_screen.dart';
import '../../features/admin/admin_paper_detail_screen.dart';
import '../../features/admin/admin_paper_review_screen.dart';
import '../../features/admin/admin_paper_form_screen.dart';
import '../../features/admin/admin_papers_screen.dart';
import '../../features/admin/admin_question_form_screen.dart';
import '../../features/admin/admin_questions_screen.dart';
import '../../features/admin/admin_review_screen.dart';
import '../../features/admin/admin_sections_screen.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/bookmarks/bookmarks_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/home/splash_screen.dart';
import '../../features/papers/answer_key_screen.dart';
import '../../features/papers/complete_solution_screen.dart';
import '../../features/papers/long_answers_screen.dart';
import '../../features/papers/original_paper_viewer_screen.dart';
import '../../features/papers/paper_screen.dart';
import '../../features/papers/short_answers_screen.dart';
import '../../features/phases/phase_screen.dart';
import '../../features/practice/practice_result.dart';
import '../../features/practice/practice_result_screen.dart';
import '../../features/practice/practice_session_screen.dart';
import '../../features/practice/practice_setup_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/progress/progress_screen.dart';
import '../../features/settings/about_screen.dart';
import '../../features/settings/privacy_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/subjects/subject_screen.dart';
import '../services/supabase_service.dart';

final _publicPaths = {'/login', '/signup', '/forgot-password', '/reset-password'};

final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluate redirect() whenever auth state changes.
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final path = state.matchedLocation;

      // Supabase's password-recovery deep link signs the user into a
      // recovery session and fires this event — always route to the
      // reset-password screen for it, regardless of normal auth gating.
      final isPasswordRecovery = authState.value?.event == AuthChangeEvent.passwordRecovery;
      if (isPasswordRecovery && path != '/reset-password') return '/reset-password';

      if (path == '/splash') return null;
      final loggedIn = SupabaseService.isLoggedIn;
      final isPublic = _publicPaths.contains(path);
      if (!loggedIn && !isPublic) return '/login';
      if (loggedIn && isPublic && !isPasswordRecovery) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/phase/:phaseId',
        builder: (context, state) => PhaseScreen(phaseId: state.pathParameters['phaseId']!),
      ),
      GoRoute(
        path: '/subject/:subjectId',
        builder: (context, state) => SubjectScreen(
          subjectId: state.pathParameters['subjectId']!,
          phaseId: state.uri.queryParameters['phaseId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/paper/:paperId',
        builder: (context, state) => PaperScreen(paperId: state.pathParameters['paperId']!),
      ),
      GoRoute(
        path: '/paper/:paperId/original',
        builder: (context, state) =>
            OriginalPaperViewerScreen(paperId: state.pathParameters['paperId']!),
      ),
      GoRoute(
        path: '/paper/:paperId/answer-key',
        builder: (context, state) =>
            AnswerKeyScreen(paperId: state.pathParameters['paperId']!),
      ),
      GoRoute(
        path: '/paper/:paperId/short-answers',
        builder: (context, state) =>
            ShortAnswersScreen(paperId: state.pathParameters['paperId']!),
      ),
      GoRoute(
        path: '/paper/:paperId/long-answers',
        builder: (context, state) =>
            LongAnswersScreen(paperId: state.pathParameters['paperId']!),
      ),
      GoRoute(
        path: '/paper/:paperId/complete-solution',
        builder: (context, state) =>
            CompleteSolutionScreen(paperId: state.pathParameters['paperId']!),
      ),
      GoRoute(
        path: '/practice/setup',
        builder: (context, state) => PracticeSetupScreen(
          initialPhaseId: state.uri.queryParameters['phaseId'],
          initialSubjectId: state.uri.queryParameters['subjectId'],
        ),
      ),
      GoRoute(
        path: '/practice/session',
        builder: (context, state) {
          final params = state.uri.queryParameters;
          final limit = params['limit'];
          return PracticeSessionScreen(
            phaseId: params['phaseId']!,
            subjectId: params['subjectId']!,
            limit: limit != null ? int.tryParse(limit) : null,
          );
        },
      ),
      GoRoute(
        path: '/practice/result',
        builder: (context, state) =>
            PracticeResultScreen(result: state.extra as PracticeResult),
      ),
      GoRoute(path: '/bookmarks', builder: (context, state) => const BookmarksScreen()),
      GoRoute(path: '/progress', builder: (context, state) => const ProgressScreen()),
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/privacy', builder: (context, state) => const PrivacyScreen()),
      GoRoute(path: '/about', builder: (context, state) => const AboutScreen()),
      GoRoute(path: '/admin', builder: (context, state) => const AdminDashboardScreen()),
      GoRoute(path: '/admin/review', builder: (context, state) => const AdminReviewScreen()),
      GoRoute(
        path: '/admin/review/sections/:sectionId/questions/:questionId',
        builder: (context, state) => AdminQuestionFormScreen(
          sectionId: state.pathParameters['sectionId']!,
          questionId: state.pathParameters['questionId'],
        ),
      ),
      GoRoute(path: '/admin/audit-log', builder: (context, state) => const AdminAuditLogScreen()),
      GoRoute(
        path: '/admin/coverage',
        builder: (context, state) => const AdminContentCoverageScreen(),
      ),
      GoRoute(path: '/admin/papers', builder: (context, state) => const AdminPapersScreen()),
      GoRoute(path: '/admin/papers/new', builder: (context, state) => const AdminPaperFormScreen()),
      GoRoute(
        path: '/admin/papers/:paperId',
        builder: (context, state) =>
            AdminPaperDetailScreen(paperId: state.pathParameters['paperId']!),
      ),
      GoRoute(
        path: '/admin/papers/:paperId/review',
        builder: (context, state) =>
            AdminPaperReviewScreen(paperId: state.pathParameters['paperId']!),
      ),
      GoRoute(
        path: '/admin/papers/:paperId/sections',
        builder: (context, state) =>
            AdminSectionsScreen(paperId: state.pathParameters['paperId']!),
      ),
      GoRoute(
        path: '/admin/papers/:paperId/sections/:sectionId/questions',
        builder: (context, state) => AdminQuestionsScreen(
          paperId: state.pathParameters['paperId']!,
          sectionId: state.pathParameters['sectionId']!,
        ),
      ),
      GoRoute(
        path: '/admin/papers/:paperId/sections/:sectionId/questions/:questionId',
        builder: (context, state) {
          final questionId = state.pathParameters['questionId'];
          return AdminQuestionFormScreen(
            sectionId: state.pathParameters['sectionId']!,
            questionId: questionId == 'new' ? null : questionId,
          );
        },
      ),
    ],
  );
});
