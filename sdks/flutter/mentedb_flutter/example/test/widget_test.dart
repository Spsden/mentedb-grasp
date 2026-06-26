import 'package:flutter_test/flutter_test.dart';
import 'package:mentedb_memory_demo/main.dart';

void main() {
  testWidgets('renders memory comparison controls', (tester) async {
    await tester.pumpWidget(const MemoryDemoApp());

    expect(find.text('MenteDB Memory Demo'), findsOneWidget);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Memory bank'), findsOneWidget);
    expect(find.text('Run comparison'), findsOneWidget);
  });
}
