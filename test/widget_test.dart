import 'package:flutter_test/flutter_test.dart';
import 'package:hisabkhata_mess_manager/main.dart';

void main() {
  testWidgets('dashboard loads with primary action', (WidgetTester tester) async {
    await tester.pumpWidget(const HisabKhataApp());
    expect(find.text('হিসাব যোগ করুন'), findsOneWidget);
  });
}
