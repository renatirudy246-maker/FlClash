import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/residential_route/config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
    'provider transit is restored from its cache and refreshed on apply',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'residential-provider-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final state = MakeRealProfileState(
        profilesPath: directory.path,
        profileId: 9,
        rawConfig: {
          'proxy-providers': {
            'airport': {
              'type': 'http',
              'url': 'https://airport.example/subscription',
              'override': {'additional-prefix': 'prefix ', 'udp': false},
            },
          },
          'rules': ['MATCH,DIRECT'],
        },
        realPatchConfig: const PatchClashConfig(),
        overrideDns: false,
        overrideNtp: false,
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [],
        defaultUA: 'FlClash-Test',
      );
      final original =
          loadYaml((await makeRealProfileTask(state)).yaml) as YamlMap;
      final cache = File(
        original['proxy-providers']['airport']['path'] as String,
      );
      await cache.parent.create(recursive: true);
      Future<void> writeCache(int port) => cache.writeAsString(
        'proxies:\n  - name: Airport\n    type: socks5\n    server: 192.0.2.1\n    port: $port\n    username: airport-user\n    password: airport-password\n    udp: true\n',
      );
      const route = ResidentialRouteConfig(
        enabled: true,
        server: '192.0.2.2',
        port: 1080,
        transit: 'prefix Airport',
      );
      await writeCache(1081);
      final first =
          loadYaml(
                (await makeRealProfileTask(
                  state,
                  residentialRoute: route,
                )).yaml,
              )
              as YamlMap;
      expect(first['proxies'].first['name'], 'prefix Airport');
      expect(first['proxies'].first['password'], 'airport-password');
      expect(first['proxies'].first['udp'], false);
      expect(first['proxies'].last['dialer-proxy'], 'prefix Airport');
      expect(state.rawConfig.containsKey('proxies'), false);
      await writeCache(1082);
      final refreshed =
          loadYaml(
                (await makeRealProfileTask(
                  state,
                  residentialRoute: route,
                )).yaml,
              )
              as YamlMap;
      expect(refreshed['proxies'].first['port'], 1082);
      await cache.writeAsString('proxies: []');
      await expectLater(
        makeRealProfileTask(state, residentialRoute: route),
        throwsFormatException,
      );
    },
  );

  test(
    'runtime generator applies residential routing after added rules',
    () async {
      const state = MakeRealProfileState(
        profilesPath: '/profiles',
        profileId: 7,
        rawConfig: {
          'proxies': [
            {
              'name': 'Airport',
              'type': 'socks5',
              'server': '192.0.2.1',
              'port': 1080,
            },
          ],
          'rules': ['DOMAIN,local.example,DIRECT', 'MATCH,Airport'],
        },
        realPatchConfig: PatchClashConfig(mode: Mode.global),
        overrideDns: false,
        overrideNtp: false,
        appendSystemDns: false,
        proxyGroups: [],
        rules: [],
        addedRules: [
          Rule(
            ruleAction: RuleAction.DOMAIN_SUFFIX,
            content: 'added.example',
            ruleTarget: 'MATCH',
          ),
        ],
        defaultUA: 'FlClash-Test',
      );
      const residential = ResidentialRouteConfig(
        enabled: true,
        server: '192.0.2.2',
        port: 1081,
        username: 'fixture',
        password: 'fixture-password',
        transit: 'Airport',
      );
      final result = await makeRealProfileTask(
        state,
        residentialRoute: residential,
      );
      final runtime = loadYaml(result.yaml) as YamlMap;
      expect(runtime['mode'], 'rule');
      expect(runtime['rules'], [
        'DOMAIN-SUFFIX,added.example,IP-Link Residential',
        'DOMAIN,local.example,DIRECT',
        'MATCH,IP-Link Residential',
      ]);
      expect(runtime['proxies'].last['dialer-proxy'], 'Airport');
      expect(runtime['proxies'].last['password'], 'fixture-password');
      final restored =
          loadYaml((await makeRealProfileTask(state)).yaml) as YamlMap;
      expect(restored['proxies'], hasLength(1));
      expect(restored['mode'], 'global');
      expect(restored['rules'].last, 'MATCH,Airport');
      expect(result.md5, isNot((await makeRealProfileTask(state)).md5));
    },
  );
}
