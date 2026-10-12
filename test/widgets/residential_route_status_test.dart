import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/residential_route/config.dart';
import 'package:fl_clash/residential_route/status.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

const node = 'Airport JP 住宅-30-12345678';
const group = Group(
  name: ResidentialRouteConfig.routeName,
  type: GroupType.Selector,
  now: node,
  all: [Proxy(name: node, type: 'Socks5')],
);

void main() {
  Future<void> mount(
    WidgetTester tester, {
    bool running = true,
    bool suspended = false,
    Mode mode = Mode.rule,
    Group? liveGroup = group,
  }) async {
    await tester.pumpWidget(
      TestApp(
        locale: const Locale('en'),
        overrides: [
          isStartProvider.overrideWithValue(running),
          suspendProvider.overrideWithValue(suspended),
          groupsProvider.overrideWithValue([?liveGroup]),
          patchClashConfigProvider.overrideWithBuild(
            (_, _) => PatchClashConfig(mode: mode),
          ),
        ],
        child: const ResidentialRouteStatus(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('running rule mode reports the live selected residential exit', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Current proxy exit: $node'), findsOneWidget);
    expect(
      find.textContaining(
        'Airport group selections are retained independently',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'stopped or suspended clients do not claim an active residential exit',
    (tester) async {
      for (final suspended in [false, true]) {
        await tester.pumpWidget(const SizedBox());
        await mount(tester, running: suspended, suspended: suspended);
        expect(find.textContaining('Clash is stopped'), findsOneWidget);
        expect(find.text('Current proxy exit: $node'), findsNothing);
      }
    },
  );

  testWidgets('global and direct modes do not claim residential rule routing', (
    tester,
  ) async {
    for (final mode in [Mode.global, Mode.direct]) {
      await tester.pumpWidget(const SizedBox());
      await mount(tester, mode: mode);
      expect(find.textContaining('Rule mode is off'), findsOneWidget);
      expect(find.text('Current proxy exit: $node'), findsNothing);
    }
  });

  testWidgets(
    'a legacy airport selection or unknown live selection is not a residential exit',
    (tester) async {
      for (final selected in ['Airport JP', 'Missing']) {
        await tester.pumpWidget(const SizedBox());
        await mount(
          tester,
          liveGroup: group.copyWith(
            now: selected,
            all: [
              ...group.all,
              const Proxy(name: 'Airport JP', type: 'Vless'),
            ],
          ),
        );
        expect(
          find.textContaining('No residential exit is confirmed'),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets('ordinary airport profiles have no residential status panel', (
    tester,
  ) async {
    await mount(tester, liveGroup: null);
    expect(
      find.byKey(const ValueKey('residential-active-route')),
      findsNothing,
    );
  });
}
