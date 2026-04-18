import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memory_assistant/main.dart';

void main() {
  testWidgets('App renders bottom navigation', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'has_seen_tour_v2': true});
    await tester.pumpWidget(const MemoryAssistantApp());
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump(const Duration(milliseconds: 500));

    // Verify bottom navigation tabs exist
    expect(find.text('Capture'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
    expect(find.text('Agenda'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}
