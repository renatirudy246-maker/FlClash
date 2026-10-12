import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/residential_route.dart';
import 'package:fl_clash/widgets/inherited.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1100, 700)]) {
    testWidgets(
      'page content clears its own toolbar despite an inherited zero inset at $size',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          TestApp(
            locale: const Locale('en'),
            overrides: [currentProfileProvider.overrideWithValue(null)],
            child: const FloatingBarScope(
              inset: 0,
              child: ResidentialRouteView(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final title = find.text('Residential route · IP-Link');
        final body = find.textContaining(
          'Import and select an airport profile first.',
        );
        expect(title, findsOneWidget);
        expect(body, findsOneWidget);
        expect(
          tester.getTopLeft(body).dy,
          greaterThan(tester.getBottomRight(title).dy),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
