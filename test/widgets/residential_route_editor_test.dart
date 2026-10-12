import 'dart:async';

import 'package:fl_clash/residential_route/config.dart';
import 'package:fl_clash/residential_route/connection.dart';
import 'package:fl_clash/residential_route/editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const labels = {
  'description': 'Description',
  'enabled': 'Enable',
  'url': 'SOCKS5 URL',
  'urlHelp': 'Paste complete URL',
  'testNodes': 'Test latency',
  'delayFailed': 'Latency test failed',
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
  'unverified': 'Unverified',
  'airportUnavailable': 'Airport unavailable',
  'applyFailed': 'Apply failed',
  'selectionFailed': 'Selection failed',
  'profileChanged': 'Profile changed',
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
  Future<ResidentialRouteOutcome> Function(ResidentialRouteConfig, bool)
  onSave, {
  Future<void> Function()? onTestNodes,
  ResidentialRouteConfig initialValue = initial,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ResidentialRouteEditor(
          initial: initialValue,
          nodes: const ['Airport HK', 'Airport JP', 'Airport US'],
          labels: labels,
          onSave: onSave,
          onTestNodes: onTestNodes,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('one hidden URL field automatically parses on connect', (
    tester,
  ) async {
    ResidentialRouteConfig? saved;
    await mount(tester, (config, _) async {
      saved = config;
      return ResidentialRouteOutcome.verified;
    });
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('Parse URL'), findsNothing);
    expect(find.text('Show password'), findsNothing);
    await tester.enterText(
      find.byType(TextFormField),
      'socks5://next%2Buser:p%3Aa%40ss@[2001:db8::40]:443',
    );
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(saved?.server, '2001:db8::40');
    expect(saved?.port, 443);
    expect(saved?.username, 'next+user');
    expect(saved?.password, 'p:a@ss');
    expect(saved?.selectedTransits, ['Airport HK']);
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, true);
  });

  testWidgets('invalid edited URL cannot reuse old credentials on connect', (
    tester,
  ) async {
    var calls = 0;
    await mount(tester, (_, _) async {
      calls++;
      return ResidentialRouteOutcome.verified;
    });
    await tester.enterText(find.byType(TextFormField), 'socks5://broken');
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Invalid URL'), findsOneWidget);
  });

  testWidgets('invalid URL still allows disabling an existing chain', (
    tester,
  ) async {
    ResidentialRouteConfig? saved;
    await mount(tester, (config, _) async {
      saved = config;
      return ResidentialRouteOutcome.saved;
    });
    await tester.enterText(find.byType(TextFormField), 'bad');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.enabled, false);
    expect(saved?.server, initial.server);
  });

  testWidgets(
    'latency failure releases its control and preserves multi-selection',
    (tester) async {
      final result = Completer<void>();
      ResidentialRouteConfig? saved;
      await mount(tester, (config, _) async {
        saved = config;
        return ResidentialRouteOutcome.verified;
      }, onTestNodes: () => result.future);
      await tester.ensureVisible(find.text('Airport JP'));
      await tester.tap(find.text('Airport JP'));
      await tester.ensureVisible(find.text('Test latency'));
      await tester.tap(find.text('Test latency'));
      await tester.pump();
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      result.completeError(StateError('test error'));
      await tester.pumpAndSettle();
      expect(find.text('Latency test failed'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(saved?.selectedTransits, ['Airport HK', 'Airport JP']);
    },
  );

  testWidgets(
    'multiple checks are saved and unchecked airport nodes are excluded',
    (tester) async {
      ResidentialRouteConfig? saved;
      await mount(tester, (config, _) async {
        saved = config;
        return ResidentialRouteOutcome.verified;
      });
      await tester.ensureVisible(find.text('Airport JP'));
      await tester.tap(find.text('Airport JP'));
      await tester.pump();
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(saved?.selectedTransits, ['Airport HK', 'Airport JP']);
      expect(saved?.selectedTransits, isNot(contains('Airport US')));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Airport HK 住宅-'), findsOneWidget);
    },
  );

  testWidgets('clearing all checks prevents a connection', (tester) async {
    var calls = 0;
    await mount(tester, (_, _) async {
      calls++;
      return ResidentialRouteOutcome.verified;
    });
    await tester.ensureVisible(find.text('Airport HK'));
    await tester.tap(find.text('Airport HK'));
    await tester.pump();
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Invalid endpoint'), findsOneWidget);
  });

  testWidgets(
    'connection shows immediate progress and distinct stage results',
    (tester) async {
      for (final outcome in [
        ResidentialRouteOutcome.unverified,
        ResidentialRouteOutcome.airportUnavailable,
        ResidentialRouteOutcome.applyFailed,
        ResidentialRouteOutcome.selectionFailed,
      ]) {
        await tester.pumpWidget(const SizedBox());
        final result = Completer<ResidentialRouteOutcome>();
        await mount(tester, (_, _) => result.future);
        await tester.ensureVisible(find.text('Connect'));
        await tester.tap(find.text('Connect'));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        result.complete(outcome);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('residential-status')))
              .data,
          labels[outcome.name],
        );
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Verified'), findsNothing);
      }
    },
  );

  testWidgets(
    'connect enables the chain and requires verification for success',
    (tester) async {
      ResidentialRouteConfig? saved;
      await mount(tester, (config, connect) async {
        expect(connect, true);
        saved = config;
        return ResidentialRouteOutcome.verified;
      });
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(saved?.enabled, true);
      expect(saved?.transit, 'Airport HK');
      expect(find.text('Verified'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'changed');
      await tester.pump();
      expect(find.text('Verified'), findsNothing);
    },
  );

  testWidgets('an unverified connection is never displayed as connected', (
    tester,
  ) async {
    await mount(tester, (_, _) async => ResidentialRouteOutcome.unverified);
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Unverified'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
  });

  testWidgets('failure releases controls and passwords stay obscured', (
    tester,
  ) async {
    await mount(tester, (_, _) async => throw StateError('fixture failure'));
    final passwordField = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    expect(passwordField, isNotNull);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).obscureText,
      true,
    );
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsWidgets);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'finishing an operation after closing the page does not update disposed state',
    (tester) async {
      final result = Completer<ResidentialRouteOutcome>();
      await mount(tester, (_, _) => result.future);
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      result.complete(ResidentialRouteOutcome.verified);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
