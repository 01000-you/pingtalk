// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/main.dart';

void main() {
  testWidgets('Scoreboard renders and can increment', (WidgetTester tester) async {
    await tester.pumpWidget(const PingTalkApp());

    expect(find.text('PINGTALK'), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('AWAY'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('1'), findsNothing);

    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });
}
