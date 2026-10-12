import 'dart:convert';

class ResidentialRouteConfig {
  static const routeName = 'IP-Link Residential';

  final bool enabled;
  final String server;
  final int port;
  final String username;
  final String password;
  final String transit;

  const ResidentialRouteConfig({
    this.enabled = false,
    this.server = '',
    this.port = 1080,
    this.username = '',
    this.password = '',
    this.transit = '',
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
  };

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
    if (transit.isEmpty ||
        transit.contains(',') ||
        transit == routeName ||
        const {
          'DIRECT',
          'REJECT',
          'REJECT-DROP',
          'PASS',
          'GLOBAL',
        }.contains(transit.toUpperCase())) {
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
    final groups = config['proxy-groups'] as List? ?? [];
    if ([
      ...proxies,
      ...groups,
    ].any((item) => item is Map && item['name'] == routeName)) {
      throw const FormatException(
        'Residential route name conflicts with profile',
      );
    }
    if (groups.any((item) => item is Map && item['name'] == transit)) {
      throw const FormatException('Choose a transit node, not a proxy group');
    }
    final inline = proxies.where(
      (item) => item is Map && item['name'] == transit,
    );
    if (inline.isEmpty && (config['proxy-providers'] as Map? ?? {}).isEmpty) {
      throw const FormatException(
        'Transit node no longer exists in this profile',
      );
    }
    if (inline.any((item) => (item as Map)['dialer-proxy'] != null)) {
      throw const FormatException('Transit node already has a proxy chain');
    }
    proxies.add({
      'name': routeName,
      'type': 'socks5',
      'server': server,
      'port': port,
      if (username.isNotEmpty) 'username': username,
      if (password.isNotEmpty) 'password': password,
      'udp': false,
      'dialer-proxy': transit,
    });
    config['proxies'] = proxies;
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
