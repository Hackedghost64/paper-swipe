import 'package:flutter_test/flutter_test.dart';
import 'package:paper_swipe/main.dart';

void main() {
  testWidgets('PaperSwipeApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PaperSwipeApp());
    await tester.pump();

    // Verify app title and Add Book button are rendered
    expect(find.text('PaperSwipe'), findsOneWidget);
    expect(find.text('Add Book (PDF)'), findsOneWidget);
  });
}
