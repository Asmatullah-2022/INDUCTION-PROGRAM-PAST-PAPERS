import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:induction_program_past_papers/core/services/cache_service.dart';
import 'package:induction_program_past_papers/main.dart';

void main() {
  testWidgets('App boots to splash screen without crashing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();

    await tester.pumpWidget(const ProviderScope(child: InductionApp()));
    await tester.pump();

    expect(find.text('Induction Program Past Papers'), findsWidgets);

    // Let the splash screen's redirect timer fire and settle on /login
    // before the test ends, so no pending Timer trips the test binding.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
