import 'package:fl_clash/residential_route/config.dart';
import 'package:fl_clash/residential_route/connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = ResidentialRouteConfig(
    enabled: true,
    server: '192.0.2.30',
    transits: ['HK', 'JP'],
  );
  late List<String> calls;
  late bool current;
  late bool applied;
  late bool selected;
  late bool airportPassed;
  late bool residentialPassed;
  late String? changeAfter;
  setUp(() {
    calls = [];
    current = true;
    applied = selected = airportPassed = residentialPassed = true;
    changeAfter = null;
  });
  void record(String step) {
    calls.add(step);
    if (changeAfter == step) current = false;
  }

  Future<ResidentialRouteOutcome> run({bool connect = true}) =>
      applyResidentialRoute(
        config: config,
        connect: connect,
        isCurrent: () => current,
        save: () async => record('save'),
        apply: () async {
          record('apply');
          return applied;
        },
        select: (name) async {
          record('select:$name');
          return selected;
        },
        closeConnections: () async => record('close'),
        test: (name) async {
          record('test:$name');
          return name == 'HK' ? airportPassed : residentialPassed;
        },
      );
  test(
    'selects and persists the residential node before closing and testing',
    () async {
      expect(await run(), ResidentialRouteOutcome.verified);
      expect(calls, [
        'save',
        'apply',
        'select:${config.nodeName('HK')}',
        'close',
        'test:HK',
        'test:${config.nodeName('HK')}',
      ]);
    },
  );
  test('apply failure stops before selection or tests', () async {
    applied = false;
    expect(await run(), ResidentialRouteOutcome.applyFailed);
    expect(calls, ['save', 'apply']);
  });
  test('selection failure cannot be displayed as verified', () async {
    selected = false;
    expect(await run(), ResidentialRouteOutcome.selectionFailed);
    expect(calls.any((step) => step.startsWith('test:')), isFalse);
  });
  test(
    'airport and residential failures have different applied outcomes',
    () async {
      airportPassed = false;
      expect(await run(), ResidentialRouteOutcome.airportUnavailable);
      expect(calls.last, 'test:HK');
      calls.clear();
      airportPassed = true;
      residentialPassed = false;
      expect(await run(), ResidentialRouteOutcome.unverified);
    },
  );
  test(
    'saving without connecting applies and closes connections without probing',
    () async {
      expect(await run(connect: false), ResidentialRouteOutcome.saved);
      expect(calls, ['save', 'apply', 'close']);
    },
  );
  test('profile changes stop work at every asynchronous boundary', () async {
    for (final step in [
      'save',
      'apply',
      'select:${config.nodeName('HK')}',
      'close',
      'test:HK',
      'test:${config.nodeName('HK')}',
    ]) {
      current = true;
      calls.clear();
      changeAfter = step;
      expect(await run(), ResidentialRouteOutcome.profileChanged, reason: step);
      expect(calls.last, step);
    }
    current = false;
    calls.clear();
    expect(await run(), ResidentialRouteOutcome.profileChanged);
    expect(calls, isEmpty);
  });
}
