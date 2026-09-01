import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:spotplayer/main.dart';

void main() {
  testWidgets('app smoke test', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SpotPlayerApp()));
    await tester.pump();
  });
}
