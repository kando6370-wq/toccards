import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/app/app.dart';

void main() {
  testWidgets('skeleton app exposes a single root route', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KandoApp()));
    await tester.pump();

    expect(find.byType(KandoApp), findsOneWidget);
  });
}
