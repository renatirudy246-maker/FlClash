import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

abstract final class ResidentialRouteStore {
  static String _key(int profileId) => 'ip_link_residential_v1_$profileId';

  static Future<ResidentialRouteConfig> load(int profileId) async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_key(profileId));
    if (value == null) return const ResidentialRouteConfig();
    try {
      return ResidentialRouteConfig.fromJson(
        Map<String, dynamic>.from(jsonDecode(value) as Map),
      );
    } catch (_) {
      throw const FormatException('Residential settings could not be read');
    }
  }

  static Future<void> save(int profileId, ResidentialRouteConfig config) async {
    if (config.enabled) config.validate();
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(
      _key(profileId),
      jsonEncode(config.toJson()),
    )) {
      throw const FormatException('Residential settings could not be saved');
    }
  }
}
