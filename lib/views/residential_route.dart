import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/residential_route/config.dart';
import 'package:fl_clash/residential_route/editor.dart';
import 'package:fl_clash/residential_route/store.dart';
import 'package:fl_clash/widgets/keyboard_inset_hold.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ResidentialRouteView extends ConsumerStatefulWidget {
  const ResidentialRouteView({super.key});

  @override
  ConsumerState<ResidentialRouteView> createState() =>
      _ResidentialRouteViewState();
}

class _ResidentialRouteViewState extends ConsumerState<ResidentialRouteView> {
  late final _profile = ref.read(currentProfileProvider);
  late final _load = _loadSettings();

  Future<({ResidentialRouteConfig config, List<String> nodes})>
  _loadSettings() async {
    final profile = _profile;
    if (profile == null) throw const FormatException('No airport profile');
    final config = await ResidentialRouteStore.load(profile.id);
    final source = await ref.read(coreHandlerProvider).getConfig(profile.id);
    final groups = ref.read(groupsProvider);
    final groupNames = groups.map((group) => group.name).toSet();
    final names = <String>{
      for (final node in source['proxies'] as List? ?? [])
        if (node is Map &&
            node['dialer-proxy'] == null &&
            node['name'] is String)
          node['name'] as String,
      for (final group in groups)
        for (final node in group.all)
          if (!groupNames.contains(node.name)) node.name,
    };
    names.removeWhere(
      (name) =>
          name == ResidentialRouteConfig.routeName ||
          const {
            'DIRECT',
            'REJECT',
            'REJECT-DROP',
            'PASS',
            'GLOBAL',
          }.contains(name.toUpperCase()),
    );
    return (config: config, nodes: names.toList()..sort());
  }

  Future<bool> _save(ResidentialRouteConfig config, bool connect) async {
    final profile = _profile!;
    final container = ProviderScope.containerOf(context, listen: false);
    if (container.read(currentProfileProvider)?.id != profile.id) {
      throw const FormatException('Airport profile changed');
    }
    await ResidentialRouteStore.save(profile.id, config);
    final setup = container.read(setupActionProvider.notifier);
    if (config.enabled) setup.changeMode(Mode.rule);
    final applied = connect
        ? await setup.setRunning(true, initialize: true)
        : await setup.applyProfile(force: true);
    if (!applied) throw const FormatException('Configuration was not applied');
    if (container.read(currentProfileProvider)?.id != profile.id) return false;
    final core = container.read(coreHandlerProvider);
    await core.closeConnections();
    if (!connect) return true;
    final testUrl = container.read(appSettingProvider).testUrl;
    final delay = await core.getDelay(
      testUrl,
      ResidentialRouteConfig.routeName,
    );
    return container.read(currentProfileProvider)?.id == profile.id &&
        delay?.value != null &&
        delay!.value! > 0;
  }

  @override
  Widget build(BuildContext context) {
    final text = context.appLocalizations;
    return KeyboardInsetHold(
      child: CommonScaffold(
        title: text.residentialRouteTitle,
        body: ListView(
          padding: EdgeInsets.fromLTRB(20, context.appBarInset, 20, 24),
          children: [
            if (_profile != null) ...[
              Text(_profile.realLabel),
              const SizedBox(height: 16),
            ],
            FutureBuilder(
              future: _load,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(text.residentialRouteLoadError);
                }
                final data = snapshot.data;
                if (data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ResidentialRouteEditor(
                  initial: data.config,
                  nodes: data.nodes,
                  labels: {
                    'description': text.residentialRouteDescription,
                    'enabled': text.residentialRouteEnabled,
                    'url': text.residentialRouteUrl,
                    'parse': text.residentialRouteParse,
                    'server': text.residentialRouteServer,
                    'port': text.residentialRoutePort,
                    'username': text.residentialRouteUsername,
                    'password': text.residentialRoutePassword,
                    'showPassword': text.residentialRouteShowPassword,
                    'transit': text.residentialRouteTransit,
                    'transitHelp': text.residentialRouteTransitHelp,
                    'connect': text.residentialRouteConnect,
                    'save': text.residentialRouteSave,
                    'working': text.residentialRouteWorking,
                    'saved': text.residentialRouteSaved,
                    'verified': text.residentialRouteVerified,
                    'failed': text.residentialRouteFailed,
                    'urlError': text.residentialRouteUrlError,
                    'endpointError': text.residentialRouteEndpointError,
                  },
                  onSave: _save,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
