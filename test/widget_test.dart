import 'package:flutter_test/flutter_test.dart';
import 'package:finora/main.dart';

void main() {
  testWidgets('shows setup guidance when Firebase values are not configured',
      (WidgetTester tester) async {
    await tester.pumpWidget(const FinoraApp());
    await tester.pump();
    expect(find.text('Firebase সেটআপ প্রয়োজন'), findsOneWidget);
    expect(find.text('https://console.firebase.google.com/'), findsOneWidget);
  });
}
