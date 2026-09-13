import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:induction_program_past_papers/core/errors/app_exception.dart';
import 'package:induction_program_past_papers/core/providers/repository_providers.dart';
import 'package:induction_program_past_papers/core/services/connectivity_service.dart';
import 'package:induction_program_past_papers/core/validation/ai_teacher_validation.dart';
import 'package:induction_program_past_papers/data/models/ai_message.dart';
import 'package:induction_program_past_papers/data/repositories/ai_teacher_repository.dart';
import 'package:induction_program_past_papers/features/ai_teacher/ai_teacher_context.dart';
import 'package:induction_program_past_papers/features/ai_teacher/ai_teacher_screen.dart';

/// Always reports online, so tests don't depend on connectivity_plus's
/// platform channel (unavailable in a widget test).
class _AlwaysOnlineConnectivityService extends ConnectivityService {
  @override
  Future<bool> isOnline() async => true;
}

/// A scriptable fake standing in for the real repository, which otherwise
/// talks to a live Edge Function — see docs/AI_TEACHER_GUIDE.md for why
/// that can't be exercised in a unit/widget test.
class _FakeAiTeacherRepository extends AiTeacherRepository {
  final AiTeacherResponse Function()? onSuccess;
  final AppException? failWith;
  final List<String> receivedMessages = [];
  final List<AiTeacherAction> receivedActions = [];
  final List<String> deletedConversationIds = [];
  int callCount = 0;

  _FakeAiTeacherRepository({this.onSuccess, this.failWith});

  @override
  Future<AiTeacherResponse> sendMessage({
    required AiTeacherAction action,
    required String message,
    String language = 'en',
    String? conversationId,
    String? paperId,
    String? questionId,
  }) async {
    callCount++;
    receivedMessages.add(message);
    receivedActions.add(action);
    if (failWith != null && callCount == 1) throw failWith!;
    if (onSuccess != null) return onSuccess!();
    return AiTeacherResponse(
      conversationId: 'conv-1',
      assistantMessage: AiMessage(
        id: 'msg-1',
        conversationId: 'conv-1',
        role: AiMessageRole.assistant,
        content: 'This is a general AI-generated answer.',
        contentKind: AiContentKind.aiGeneratedAnswer,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    deletedConversationIds.add(conversationId);
  }
}

/// A repository whose response never resolves until the test completes
/// [pending] — lets a test observe the loading state deterministically,
/// without racing a real (fast) Future's resolution against a single
/// `pump()`.
class _PendingAiTeacherRepository extends AiTeacherRepository {
  final Completer<AiTeacherResponse> pending = Completer<AiTeacherResponse>();

  @override
  Future<AiTeacherResponse> sendMessage({
    required AiTeacherAction action,
    required String message,
    String language = 'en',
    String? conversationId,
    String? paperId,
    String? questionId,
  }) => pending.future;
}

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

void main() {
  group('AiTeacherScreen — empty state', () {
    testWidgets('shows the AI Teacher title, tagline, and general quick actions', (tester) async {
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(_FakeAiTeacherRepository()),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      expect(find.text('AI Teacher'), findsWidgets);
      expect(find.text('Learn • Understand • Practice'), findsOneWidget);
      expect(find.text('Explain Simply'), findsOneWidget); // present in general mode
      expect(find.text('Explain This MCQ'), findsNothing); // question-only action absent
    });
  });

  group('AiTeacherScreen — question-context mode', () {
    testWidgets('shows the question preview banner and question-context quick actions', (tester) async {
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(
          context0: AiTeacherContext(
            paperId: 'paper-1',
            questionId: 'question-1',
            questionPreview: 'What is formative assessment?',
            isMcq: true,
          ),
        ),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(_FakeAiTeacherRepository()),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      expect(find.text('What is formative assessment?'), findsOneWidget);
      expect(find.text('Explain This MCQ'), findsOneWidget);
      expect(find.text('Study Plan'), findsNothing); // general-only action absent here
    });
  });

  group('AiTeacherScreen — message rendering and labelling', () {
    testWidgets('sending a message renders the user bubble then the AI-generated-answer label', (tester) async {
      final fake = _FakeAiTeacherRepository();
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(fake),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      await tester.enterText(find.byType(TextField), 'What is classroom management?');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('What is classroom management?'), findsOneWidget);
      expect(find.text('This is a general AI-generated answer.'), findsOneWidget);
      expect(find.text('AI-GENERATED ANSWER'), findsOneWidget);
      expect(fake.receivedActions.single, AiTeacherAction.ask);
    });

    testWidgets('a verified-context response is labelled as based on verified content, never as verified itself',
        (tester) async {
      final fake = _FakeAiTeacherRepository(
        onSuccess: () => AiTeacherResponse(
          conversationId: 'conv-2',
          assistantMessage: AiMessage(
            id: 'msg-2',
            conversationId: 'conv-2',
            role: AiMessageRole.assistant,
            content: 'B is correct because...',
            contentKind: AiContentKind.aiGeneratedExplanationBasedOnVerified,
            createdAt: DateTime.now(),
          ),
        ),
      );
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(
          context0: AiTeacherContext(paperId: 'p1', questionId: 'q1', questionPreview: 'Q1', isMcq: true),
        ),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(fake),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      await tester.tap(find.text('Explain This MCQ'));
      await tester.pumpAndSettle();

      expect(find.text('AI-GENERATED EXPLANATION BASED ON VERIFIED CONTENT'), findsOneWidget);
      expect(find.text('VERIFIED ANSWER'), findsNothing);
    });
  });

  group('AiTeacherScreen — loading state', () {
    testWidgets('shows a loading indicator while a request is in flight, then the response once it resolves',
        (tester) async {
      final pendingRepo = _PendingAiTeacherRepository();
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(pendingRepo),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      await tester.enterText(find.byType(TextField), 'Explain constructivism.');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump(); // the send-related setState is synchronous, before any await

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pendingRepo.pending.complete(AiTeacherResponse(
        conversationId: 'conv-3',
        assistantMessage: AiMessage(
          id: 'msg-3',
          conversationId: 'conv-3',
          role: AiMessageRole.assistant,
          content: 'Constructivism is a learning theory...',
          contentKind: AiContentKind.aiGeneratedAnswer,
          createdAt: DateTime.now(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Constructivism is a learning theory...'), findsOneWidget);
    });
  });

  group('AiTeacherScreen — error state and retry', () {
    testWidgets('a failed request shows an error bubble with Retry, and Retry re-sends successfully',
        (tester) async {
      final fake = _FakeAiTeacherRepository(
        failWith: const AppException('AI Teacher is temporarily unavailable. Please try again.'),
      );
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(fake),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      await tester.enterText(find.byType(TextField), 'Explain Bloom\'s taxonomy.');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('AI Teacher is temporarily unavailable. Please try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(fake.callCount, 2);
      expect(find.text('This is a general AI-generated answer.'), findsOneWidget);
    });

    testWidgets('sending with no text shows a validation error instead of calling the repository',
        (tester) async {
      final fake = _FakeAiTeacherRepository();
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(fake),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a message.'), findsOneWidget);
      expect(fake.callCount, 0);
    });
  });

  group('AiTeacherScreen — language toggle', () {
    testWidgets('tapping the language icon toggles between English and Urdu mode', (tester) async {
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(_FakeAiTeacherRepository()),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      expect(find.byIcon(Icons.language), findsOneWidget);
      await tester.tap(find.byIcon(Icons.language));
      await tester.pump();
      expect(find.byIcon(Icons.translate), findsOneWidget);
    });
  });

  group('AiTeacherScreen — navigation', () {
    testWidgets('navigating to /ai-teacher from another route renders the AI Teacher screen', (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => context.push('/ai-teacher'),
                  child: const Text('Open AI Teacher'),
                ),
              ),
            ),
          ),
          GoRoute(path: '/ai-teacher', builder: (context, state) => const AiTeacherScreen()),
        ],
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(_FakeAiTeacherRepository()),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));

      await tester.tap(find.text('Open AI Teacher'));
      await tester.pumpAndSettle();

      expect(find.text('Learn • Understand • Practice'), findsOneWidget);
    });
  });

  group('AiTeacherScreen — stop generation', () {
    testWidgets('tapping Stop abandons the pending request and a late response is never displayed',
        (tester) async {
      final pendingRepo = _PendingAiTeacherRepository();
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(pendingRepo),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      await tester.enterText(find.byType(TextField), 'Explain constructivism.');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(find.byIcon(Icons.stop), findsOneWidget);
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump();

      expect(find.text('Generation stopped.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.send), findsOneWidget);

      // The Edge Function call isn't actually aborted (no cancellation
      // hook in supabase_flutter's functions client) — completing it
      // afterwards must never resurrect the loading state or append a
      // stale response. See docs/AI_TEACHER_GUIDE.md "Stop Generation".
      pendingRepo.pending.complete(AiTeacherResponse(
        conversationId: 'conv-x',
        assistantMessage: AiMessage(
          id: 'msg-x',
          conversationId: 'conv-x',
          role: AiMessageRole.assistant,
          content: 'Late response.',
          contentKind: AiContentKind.aiGeneratedAnswer,
          createdAt: DateTime.now(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Late response.'), findsNothing);
    });
  });

  group('AiTeacherScreen — new conversation vs clear chat', () {
    testWidgets('New Conversation resets the view immediately, without confirmation or deletion',
        (tester) async {
      final fake = _FakeAiTeacherRepository();
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(fake),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      await tester.enterText(find.byType(TextField), 'What is formative assessment?');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(find.text('This is a general AI-generated answer.'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Conversation'));
      await tester.pumpAndSettle();

      expect(find.text('This is a general AI-generated answer.'), findsNothing);
      expect(fake.deletedConversationIds, isEmpty);
    });

    testWidgets('Clear Chat asks for confirmation, and only deletes the conversation once confirmed',
        (tester) async {
      final fake = _FakeAiTeacherRepository();
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(fake),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      await tester.enterText(find.byType(TextField), 'What is formative assessment?');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear Chat'));
      await tester.pumpAndSettle();
      expect(find.text('Clear this conversation?'), findsOneWidget);

      // Cancel leaves the conversation untouched.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('This is a general AI-generated answer.'), findsOneWidget);
      expect(fake.deletedConversationIds, isEmpty);

      // Confirming deletes it and clears the view.
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear Chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.text('This is a general AI-generated answer.'), findsNothing);
      expect(fake.deletedConversationIds, ['conv-1']);
    });
  });

  group('AiTeacherScreen — regenerate', () {
    testWidgets('Regenerate re-sends the same message/action and replaces the previous answer, not duplicates it',
        (tester) async {
      var responseIndex = 0;
      final responses = ['First answer.', 'Second answer.'];
      final fake = _FakeAiTeacherRepository(
        onSuccess: () => AiTeacherResponse(
          conversationId: 'conv-1',
          assistantMessage: AiMessage(
            id: 'msg-${responseIndex + 1}',
            conversationId: 'conv-1',
            role: AiMessageRole.assistant,
            content: responses[responseIndex++],
            contentKind: AiContentKind.aiGeneratedAnswer,
            createdAt: DateTime.now(),
          ),
        ),
      );
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(fake),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      await tester.enterText(find.byType(TextField), "Explain Bloom's taxonomy.");
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(find.text('First answer.'), findsOneWidget);

      await tester.tap(find.text('Regenerate'));
      await tester.pumpAndSettle();

      expect(find.text('First answer.'), findsNothing);
      expect(find.text('Second answer.'), findsOneWidget);
      expect(find.text("Explain Bloom's taxonomy."), findsOneWidget); // not duplicated
      expect(fake.callCount, 2);
      expect(fake.receivedActions, [AiTeacherAction.ask, AiTeacherAction.ask]);
    });
  });

  group('AiTeacherScreen — verified content must have priority', () {
    testWidgets('a mismatched AI-stated answer triggers a discrepancy notice', (tester) async {
      final fake = _FakeAiTeacherRepository(
        onSuccess: () => AiTeacherResponse(
          conversationId: 'conv-2',
          assistantMessage: AiMessage(
            id: 'msg-2',
            conversationId: 'conv-2',
            role: AiMessageRole.assistant,
            content: 'Correct Answer is C.\nBecause C fits best.',
            contentKind: AiContentKind.aiGeneratedExplanationBasedOnVerified,
            createdAt: DateTime.now(),
          ),
        ),
      );
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(
          context0: AiTeacherContext(
            paperId: 'p1',
            questionId: 'q1',
            questionPreview: 'Q1',
            isMcq: true,
            verifiedAnswer: 'B',
          ),
        ),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(fake),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      await tester.tap(find.text('Explain This MCQ'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Potential discrepancy detected. The stored answer is marked VERIFIED. '
          'Please refer to the source paper or administrator verification.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a matching AI-stated answer never triggers a discrepancy notice', (tester) async {
      final fake = _FakeAiTeacherRepository(
        onSuccess: () => AiTeacherResponse(
          conversationId: 'conv-3',
          assistantMessage: AiMessage(
            id: 'msg-3',
            conversationId: 'conv-3',
            role: AiMessageRole.assistant,
            content: 'Correct Answer is B.\nBecause B fits best.',
            contentKind: AiContentKind.aiGeneratedExplanationBasedOnVerified,
            createdAt: DateTime.now(),
          ),
        ),
      );
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(
          context0: AiTeacherContext(
            paperId: 'p1',
            questionId: 'q1',
            questionPreview: 'Q1',
            isMcq: true,
            verifiedAnswer: 'B',
          ),
        ),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(fake),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      await tester.tap(find.text('Explain This MCQ'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Potential discrepancy'), findsNothing);
    });
  });

  group('AiTeacherScreen — generated practice labelling', () {
    testWidgets('a make_quiz response is labelled AI-GENERATED PRACTICE with a NEEDS REVIEW badge',
        (tester) async {
      final fake = _FakeAiTeacherRepository(
        onSuccess: () => AiTeacherResponse(
          conversationId: 'conv-4',
          assistantMessage: AiMessage(
            id: 'msg-4',
            conversationId: 'conv-4',
            role: AiMessageRole.assistant,
            content: '1. What is formative assessment?\n2. What is summative assessment?',
            contentKind: AiContentKind.aiGeneratedPractice,
            createdAt: DateTime.now(),
          ),
        ),
      );
      await tester.pumpWidget(_wrap(
        const AiTeacherScreen(),
        overrides: [
          aiTeacherRepositoryProvider.overrideWithValue(fake),
          connectivityServiceProvider.overrideWithValue(_AlwaysOnlineConnectivityService()),
        ],
      ));

      // "Make Quiz" is off-screen in the horizontally-scrolling quick
      // actions row at test viewport width — same virtualization issue
      // noted for "Study Plan" elsewhere in this file.
      await tester.ensureVisible(find.text('Make Quiz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make Quiz'));
      await tester.pumpAndSettle();

      expect(find.text('AI-GENERATED PRACTICE'), findsOneWidget);
      expect(find.text('NEEDS REVIEW'), findsOneWidget);
    });
  });
}
