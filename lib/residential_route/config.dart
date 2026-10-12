import 'dart:convert';

import 'package:crypto/crypto.dart';

class ResidentialRouteConfig {
  static const routeName = 'IP-Link Residential';

  final bool enabled;
  final String server;
  final int port;
  final String username;
  final String password;
  final String transit;
  final List<String> transits;

  const ResidentialRouteConfig({
    this.enabled = false,
    this.server = '',
    this.port = 1080,
    this.username = '',
    this.password = '',
    this.transit = '',
    this.transits = const [],
  });

  factory ResidentialRouteConfig.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported residential settings version');
    }
    return ResidentialRouteConfig(
      enabled: json['enabled'] as bool,
      server: json['server'] as String,
      port: json['port'] as int,
      username: json['username'] as String,
      password: json['password'] as String,
      transit: json['transit'] as String,
      transits: (json['transits'] as List? ?? []).cast<String>(),
    );
  }

  factory ResidentialRouteConfig.parseSocksUrl(String value) {
    Uri uri;
    try {
      uri = Uri.parse(value.trim());
    } on FormatException {
      throw const FormatException('Invalid SOCKS5 URL');
    }
    if (uri.scheme != 'socks5' ||
        !uri.hasPort ||
        uri.host.isEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Use socks5://username:password@host:port');
    }
    final separator = uri.userInfo.indexOf(':');
    if (separator < 1) {
      throw const FormatException('SOCKS5 URL needs a username and password');
    }
    try {
      final config = ResidentialRouteConfig(
        server: uri.host,
        port: uri.port,
        username: Uri.decodeComponent(uri.userInfo.substring(0, separator)),
        password: Uri.decodeComponent(uri.userInfo.substring(separator + 1)),
      );
      config.validateEndpoint();
      return config;
    } on FormatException {
      throw const FormatException('Invalid SOCKS5 address or credentials');
    }
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'enabled': enabled,
    'server': server,
    'port': port,
    'username': username,
    'password': password,
    'transit': transit,
    'transits': transits,
  };

  List<String> get selectedTransits =>
      transits.isNotEmpty ? transits : (transit.isEmpty ? const [] : [transit]);

  String nodeName(String name) {
    final host = server.trim();
    final hash = sha256
        .convert(utf8.encode('$host:$port|$username'))
        .toString()
        .substring(0, 8)
        .toUpperCase();
    final ipv4 = RegExp(r'^\d+\.\d+\.\d+\.(\d+)$').firstMatch(host);
    var hint =
        ipv4?.group(1) ??
        host.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
    if (hint.isEmpty) hint = 'IP';
    if (hint.length > 6 && ipv4 == null) hint = hint.substring(0, 6);
    return '${name.trim()} 住宅-$hint-$hash';
  }

  void validateEndpoint() {
    if (server.isEmpty ||
        RegExp(r'[\s/@?#]').hasMatch(server) ||
        server.contains('://') ||
        port < 1 ||
        port > 65535) {
      throw const FormatException('Invalid SOCKS5 server or port');
    }
    if (username.isEmpty != password.isEmpty ||
        utf8.encode(username).length > 255 ||
        utf8.encode(password).length > 255) {
      throw const FormatException('Invalid SOCKS5 username or password');
    }
  }

  void validate() {
    validateEndpoint();
    if (selectedTransits.isEmpty ||
        selectedTransits.toSet().length != selectedTransits.length ||
        selectedTransits.any(
          (name) =>
              name.isEmpty ||
              name.contains(',') ||
              name == routeName ||
              const {
                'DIRECT',
                'REJECT',
                'REJECT-DROP',
                'PASS',
                'GLOBAL',
              }.contains(name.toUpperCase()),
        )) {
      throw const FormatException('Select an airport transit node');
    }
  }

  Map<String, dynamic> apply(Map<String, dynamic> source) {
    if (!enabled) return source;
    validate();
    final config = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(source)) as Map,
    );
    final proxies = List<dynamic>.from(config['proxies'] as List? ?? []);
    final groups = List<dynamic>.from(config['proxy-groups'] as List? ?? []);
    final managedNames = {routeName, ...selectedTransits.map(nodeName)};
    if (managedNames.length != selectedTransits.length + 1) {
      throw const FormatException('Residential node names must be unique');
    }
    if ([
      ...proxies,
      ...groups,
    ].any((item) => item is Map && managedNames.contains(item['name']))) {
      throw const FormatException(
        'Residential route name conflicts with profile',
      );
    }
    if (groups.any(
      (item) => item is Map && selectedTransits.contains(item['name']),
    )) {
      throw const FormatException('Choose a transit node, not a proxy group');
    }
    for (final name in selectedTransits) {
      final inline = proxies.where(
        (item) => item is Map && item['name'] == name,
      );
      if (inline.length != 1) {
        throw const FormatException(
          'Transit node no longer exists in this profile',
        );
      }
      if (inline.any((item) => (item as Map)['dialer-proxy'] != null)) {
        throw const FormatException('Transit node already has a proxy chain');
      }
      proxies.add({
        'name': nodeName(name),
        'type': 'socks5',
        'server': server,
        'port': port,
        if (username.isNotEmpty) 'username': username,
        if (password.isNotEmpty) 'password': password,
        'udp': false,
        'dialer-proxy': name,
      });
    }
    config['proxies'] = proxies;
    groups.add({
      'name': routeName,
      'type': 'select',
      'proxies': [...selectedTransits.map(nodeName), ...selectedTransits],
    });
    config['proxy-groups'] = groups;
    config['mode'] = 'rule';
    final rules = (config['rules'] as List? ?? [])
        .cast<String>()
        .map(_routeRule)
        .toList();
    if (!rules.any((rule) => rule.startsWith('MATCH,'))) {
      rules.add('MATCH,$routeName');
    }
    config['rules'] = rules;
    final subRules = config['sub-rules'];
    if (subRules is Map) {
      config['sub-rules'] = {
        for (final entry in subRules.entries)
          entry.key: (entry.value as List)
              .cast<String>()
              .map(_routeRule)
              .toList(),
      };
    }
    return config;
  }

  String _routeRule(String rule) {
    if (rule.startsWith('SUB-RULE,')) return rule;
    final parts = rule.split(',');
    var targetIndex = parts.length - 1;
    if (parts.last.toLowerCase() == 'no-resolve') targetIndex--;
    if (targetIndex < 1) {
      throw const FormatException('Invalid routing rule in airport profile');
    }
    final target = parts[targetIndex].trim().toUpperCase();
    if (!const {'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS'}.contains(target)) {
      parts[targetIndex] = routeName;
    }
    return parts.join(',');
  }
}
