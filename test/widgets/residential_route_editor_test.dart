import 'dart:async';

import 'package:fl_clash/residential_route/config.dart';
import 'package:fl_clash/residential_route/editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const labels = {
  'description': 'Description',
  'enabled': 'Enable',
  'url': 'SOCKS5 URL',
  'parse': 'Parse URL',
  'server': 'Server',
  'port': 'Port',
  'username': 'Username',
  'password': 'Password',
  'showPassword': 'Show password',
  'transit': 'Transit',
  'transitHelp': 'Select a node',
  'connect': 'Connect',
  'save': 'Save',
  'working': 'Working',
  'saved': 'Saved',
  'verified': 'Verified',
  'failed': 'Failed',
  'urlError': 'Invalid URL',
  'endpointError': 'Invalid endpoint',
};
const initial = ResidentialRouteConfig(
  server: '192.0.2.30',
  username: 'demo',
  password: 'secret',
  transit: 'Airport HK',
);

Future<void> mount(
  WidgetTester tester,
  Future<bool> Function(ResidentialRouteConfig, bool) onSave,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ResidentialRouteEditor(
          initial: initial,
          nodes: const ['Airport HK'],
          labels: labels,
          onSave: onSave,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'connect enables the chain and requires verification for success',
    (tester) async {
      ResidentialRouteConfig? saved;
      await mount(tester, (config, connect) async {
        expect(connect, true);
        saved = config;
        return true;
      });
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(saved?.enabled, true);
      expect(saved?.transit, 'Airport HK');
      expect(find.text('Verified'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(4), 'changed');
      await tester.pump();
      expect(find.text('Verified'), findsNothing);
    },
  );

  testWidgets('an unverified connection is never displayed as connected', (
    tester,
  ) async {
    await mount(tester, (_, _) async => false);
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
  });

  testWidgets('failure releases controls and passwords stay obscured', (
    tester,
  ) async {
    await mount(tester, (_, _) async => throw StateError('fixture failure'));
    final passwordField = tester.widget<TextFormField>(
      find.byType(TextFormField).at(4),
    );
    expect(passwordField, isNotNull);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(4)).obscureText,
      true,
    );
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'finishing an operation after closing the page does not update disposed state',
    (tester) async {
      final result = Completer<bool>();
      await mount(tester, (_, _) => result.future);
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      result.complete(true);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
