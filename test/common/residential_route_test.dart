import 'dart:convert';

import 'package:fl_clash/residential_route/config.dart';
import 'package:fl_clash/residential_route/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const route = ResidentialRouteConfig(
    enabled: true,
    server: '192.0.2.30',
    port: 1080,
    username: 'demo',
    password: 'p:a+ss#word',
    transit: 'Airport HK',
  );
  Map<String, dynamic> airport() => {
    'mode': 'global',
    'proxies': [
      {'name': 'Airport HK', 'type': 'ss', 'server': '192.0.2.20'},
    ],
    'proxy-groups': [
      {
        'name': 'Airport',
        'type': 'select',
        'proxies': ['Airport HK'],
      },
    ],
    'rules': [
      'DOMAIN,lan.example,DIRECT',
      'DOMAIN,blocked.example,REJECT',
      'DOMAIN,drop.example,REJECT-DROP',
      'IP-CIDR,203.0.113.0/24,Airport,no-resolve',
      'AND,((NETWORK,tcp),(DOMAIN,example.com)),Airport',
      'SUB-RULE,(NETWORK,tcp),tcp-rules',
      'MATCH,Airport',
    ],
    'sub-rules': {
      'tcp-rules': ['DOMAIN,example.com,Airport', 'MATCH,DIRECT'],
    },
  };

  test('uses airport as the dialer and preserves source and direct rules', () {
    final source = airport();
    final original = jsonEncode(source);
    final config = route.apply(source);
    expect(jsonEncode(source), original);
    final residential = (config['proxies'] as List).last as Map;
    expect(residential['server'], route.server);
    expect(residential['dialer-proxy'], route.transit);
    expect(residential['password'], route.password);
    expect(residential['udp'], false);
    expect(config['mode'], 'rule');
    expect(
      (config['proxy-groups'] as List).first,
      (source['proxy-groups'] as List).first,
    );
    expect((config['proxy-groups'] as List).last, {
      'name': ResidentialRouteConfig.routeName,
      'type': 'select',
      'proxies': [route.nodeName('Airport HK')],
    });
    expect(residential['name'], route.nodeName('Airport HK'));
    expect(config['rules'], [
      'DOMAIN,lan.example,DIRECT',
      'DOMAIN,blocked.example,REJECT',
      'DOMAIN,drop.example,REJECT-DROP',
      'IP-CIDR,203.0.113.0/24,IP-Link Residential,no-resolve',
      'AND,((NETWORK,tcp),(DOMAIN,example.com)),IP-Link Residential',
      'SUB-RULE,(NETWORK,tcp),tcp-rules',
      'MATCH,IP-Link Residential',
    ]);
    expect(config['sub-rules']['tcp-rules'], [
      'DOMAIN,example.com,IP-Link Residential',
      'MATCH,DIRECT',
    ]);
  });

  test('disabled settings do not alter airport routing', () {
    final source = airport();
    expect(const ResidentialRouteConfig().apply(source), same(source));
  });

  test('fresh subscription content keeps residential settings', () {
    final source = airport();
    (source['proxies'] as List).add({'name': 'Airport JP', 'type': 'ss'});
    final updated = route.apply(source);
    expect((updated['proxies'] as List).length, 3);
    expect((updated['proxies'] as List).last['dialer-proxy'], 'Airport HK');
  });

  test(
    'rejects missing, group, chained and conflicting transit definitions',
    () {
      for (final kind in ['missing', 'group', 'chained', 'collision']) {
        final source = airport();
        if (kind == 'missing') source['proxies'] = [];
        if (kind == 'group') {
          (source['proxy-groups'] as List).add({
            'name': route.transit,
            'type': 'select',
          });
        }
        if (kind == 'chained') {
          (source['proxies'] as List).first['dialer-proxy'] = 'Other';
        }
        if (kind == 'collision') {
          (source['proxies'] as List).add({
            'name': ResidentialRouteConfig.routeName,
          });
        }
        expect(() => route.apply(source), throwsFormatException, reason: kind);
      }
    },
  );

  test('requires provider nodes to be hydrated before generating chains', () {
    final source = airport()..['proxies'] = [];
    source['proxy-providers'] = {
      'airport': {
        'type': 'http',
        'url': 'https://airport.example/subscription',
      },
    };
    expect(() => route.apply(source), throwsFormatException);
  });

  test('only checked nodes gain chains; originals and groups remain', () {
    final source = airport();
    (source['proxies'] as List).addAll(<Map<String, String>>[
      {'name': 'Airport JP', 'type': 'ss'},
      {'name': 'Airport US', 'type': 'ss'},
    ]);
    const multi = ResidentialRouteConfig(
      enabled: true,
      server: '192.0.2.30',
      username: 'demo',
      password: 'secret',
      transits: ['Airport HK', 'Airport JP'],
    );
    final updated = multi.apply(source);
    final proxies = updated['proxies'] as List;
    expect(proxies.take(3).toList(), source['proxies']);
    expect(proxies.skip(3).map((node) => node['dialer-proxy']), [
      'Airport HK',
      'Airport JP',
    ]);
    expect(
      proxies.map((node) => node['name']),
      isNot(contains(multi.nodeName('Airport US'))),
    );
    expect((updated['proxy-groups'] as List).last['proxies'], [
      multi.nodeName('Airport HK'),
      multi.nodeName('Airport JP'),
    ]);
    expect(
      ResidentialRouteConfig.fromJson(multi.toJson()).selectedTransits,
      multi.selectedTransits,
    );
  });

  test(
    'node names match desktop endpoint and account hash without passwords',
    () {
      expect(route.nodeName('Airport HK'), 'Airport HK 住宅-30-77643868');
      const changedPassword = ResidentialRouteConfig(
        server: '192.0.2.30',
        username: 'demo',
        password: 'other',
      );
      expect(
        changedPassword.nodeName('Airport HK'),
        route.nodeName('Airport HK'),
      );
      expect(route.nodeName('Airport HK'), isNot(contains(route.password)));
    },
  );

  test('legacy single node settings migrate to one selected node', () {
    final old = route.toJson()..remove('transits');
    expect(ResidentialRouteConfig.fromJson(old).selectedTransits, [
      'Airport HK',
    ]);
  });

  test(
    'multi-node routes reject missing, duplicate and generated-name collisions',
    () {
      for (final names in [
        <String>[],
        ['Airport HK', 'Airport HK'],
        ['Airport HK', 'Missing'],
      ]) {
        final invalid = ResidentialRouteConfig(
          enabled: true,
          server: '192.0.2.30',
          transits: names,
        );
        expect(() => invalid.apply(airport()), throwsFormatException);
      }
      final source = airport();
      (source['proxies'] as List).add({
        'name': route.nodeName('Airport HK'),
        'type': 'ss',
      });
      expect(() => route.apply(source), throwsFormatException);
    },
  );

  test(
    'parses IPv6 and percent-encoded credentials without converting plus',
    () {
      final parsed = ResidentialRouteConfig.parseSocksUrl(
        'socks5://demo%2Buser:p%3Aa%40ss%23word@[2001:db8::30]:1080',
      );
      expect(parsed.server, '2001:db8::30');
      expect(parsed.username, 'demo+user');
      expect(parsed.password, 'p:a@ss#word');
    },
  );

  test('does not include credential text in parser errors', () {
    const secret = 'do-not-echo-password';
    try {
      ResidentialRouteConfig.parseSocksUrl('https://demo:$secret@host:0');
      fail('URL should have been rejected');
    } on FormatException catch (error) {
      expect(error.toString(), isNot(contains(secret)));
    }
  });

  test(
    'saved endpoints round-trip to hidden URL without changing credentials',
    () {
      for (final endpoint in [
        route,
        const ResidentialRouteConfig(
          server: '2001:db8::30',
          port: 443,
          username: 'u:+@',
          password: 'p% #:@',
        ),
        const ResidentialRouteConfig(server: '192.0.2.30', port: 1080),
      ]) {
        final parsed = ResidentialRouteConfig.parseSocksUrl(endpoint.socksUrl);
        expect(parsed.server, endpoint.server);
        expect(parsed.port, endpoint.port);
        expect(parsed.username, endpoint.username);
        expect(parsed.password, endpoint.password);
      }
      expect(const ResidentialRouteConfig().socksUrl, '');
    },
  );

  test(
    'rejects invalid ports and SOCKS5 credentials longer than 255 bytes',
    () {
      for (final port in [0, 65536]) {
        expect(
          () => ResidentialRouteConfig(
            server: 'host',
            port: port,
          ).validateEndpoint(),
          throwsFormatException,
        );
      }
      expect(
        () => ResidentialRouteConfig(
          server: 'host',
          username: 'demo',
          password: List.filled(128, '界').join(),
        ).validateEndpoint(),
        throwsFormatException,
      );
    },
  );

  test(
    'saved credentials persist per profile without affecting another profile',
    () async {
      SharedPreferences.setMockInitialValues({});
      await ResidentialRouteStore.save(101, route);
      expect((await ResidentialRouteStore.load(101)).toJson(), route.toJson());
      expect((await ResidentialRouteStore.load(102)).enabled, false);
      final restored = ResidentialRouteConfig.fromJson(
        jsonDecode(jsonEncode((await ResidentialRouteStore.load(101)).toJson()))
            as Map<String, dynamic>,
      );
      expect(
        restored.apply(airport())['rules'].last,
        'MATCH,IP-Link Residential',
      );
    },
  );

  test(
    'malformed settings fail instead of silently selecting a direct route',
    () async {
      SharedPreferences.setMockInitialValues({
        'ip_link_residential_v1_101': '{broken',
      });
      await expectLater(ResidentialRouteStore.load(101), throwsFormatException);
    },
  );
}
