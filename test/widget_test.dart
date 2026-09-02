import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:user_interface/main.dart';

void main() {
  testWidgets('MyApp builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MyApp(startPage: SizedBox.shrink(), enableAppLock: false),
    );
    await tester.pump();
  });
}
