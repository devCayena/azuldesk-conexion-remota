import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:azuldesk/providers/app_state.dart';
import 'package:azuldesk/screens/dashboard_screen.dart';

void main() {
  testWidgets('Dashboard shows title and status', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );

    expect(find.text('AzulDesk - Conexión Remota'), findsOneWidget);
  });
}
