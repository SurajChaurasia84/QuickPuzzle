import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle/main.dart';

void main() {
  testWidgets('Puzzle game mounts successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TopPuzzleApp());

    // Verify that the game screen loads by checking for HUD text
    expect(find.textContaining('TIME:'), findsOneWidget);
    expect(find.textContaining('MOVES:'), findsOneWidget);
  });
}
