import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/residential_route/config.dart';
import 'package:fl_clash/residential_route/connection.dart';
import 'package:fl_clash/residential_route/editor.dart';
import 'package:fl_clash/residential_route/store.dart';
import 'package:fl_clash/widgets/keyboard_inset_hold.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/views/proxies/common.dart';
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

  Future<({ResidentialRouteConfig config, Map<String, Proxy> nodes})>
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
          config.selectedTransits.map(config.nodeName).contains(name) ||
          const {
            'DIRECT',
            'REJECT',
            'REJECT-DROP',
            'PASS',
            'GLOBAL',
          }.contains(name.toUpperCase()),
    );
    final proxies = <String, Proxy>{
      for (final node in source['proxies'] as List? ?? [])
        if (node is Map && node['name'] is String && node['type'] is String)
          node['name'] as String: Proxy(
            name: node['name'] as String,
            type: node['type'] as String,
          ),
      for (final group in groups)
        for (final node in group.all) node.name: node,
    };
    return (
      config: config,
      nodes: {
        for (final name in names.toList()..sort())
          name: proxies[name] ?? Proxy(name: name, type: '-'),
      },
    );
  }

  Future<ResidentialRouteOutcome> _save(
    ResidentialRouteConfig config,
    bool connect,
  ) async {
    final profile = _profile!;
    final container = ProviderScope.containerOf(context, listen: false);
    final setup = container.read(setupActionProvider.notifier);
    final core = container.read(coreHandlerProvider);
    bool isCurrent() =>
        container.read(currentProfileProvider)?.id == profile.id;
    return applyResidentialRoute(
      config: config,
      connect: connect,
      isCurrent: isCurrent,
      save: () => ResidentialRouteStore.save(profile.id, config),
      apply: () {
        if (config.enabled) setup.changeMode(Mode.rule);
        return connect
            ? setup.setRunning(true, initialize: true)
            : setup.applyProfile(force: true);
      },
      select: (name) async {
        final result = await core.changeProxy(
          ChangeProxyParams(
            groupName: ResidentialRouteConfig.routeName,
            proxyName: name,
          ),
        );
        if (result.message.isNotEmpty || !isCurrent()) return false;
        container
            .read(profilesActionProvider.notifier)
            .updateCurrentSelectedMap(ResidentialRouteConfig.routeName, name);
        final proxies = container.read(proxiesActionProvider.notifier);
        proxies.updateCurrentGroupName(ResidentialRouteConfig.routeName);
        await proxies.updateGroups();
        return true;
      },
      closeConnections: core.closeConnections,
      test: (name) async {
        try {
          final delay = await core.getDelay(
            container.read(appSettingProvider).testUrl,
            name,
          );
          return delay?.value != null && delay!.value! > 0;
        } catch (_) {
          return false;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = context.appLocalizations;
    return KeyboardInsetHold(
      child: CommonScaffold(
        title: text.residentialRouteTitle,
        body: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.fromLTRB(20, context.contentTopPadding, 20, 24),
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
                    nodes: data.nodes.keys.toList(),
                    nodeHeight: getItemHeight(ProxyCardType.shrink),
                    nodeBuilder: (_, name, selected, onTap) => ProxyCard(
                      groupName: ResidentialRouteConfig.routeName,
                      testUrl: null,
                      proxy: data.nodes[name] ?? Proxy(name: name, type: '-'),
                      groupType: GroupType.Selector,
                      type: ProxyCardType.shrink,
                      selectionOverride: selected,
                      onSelectionChanged: onTap,
                    ),
                    onTestNodes: ref.watch(isStartProvider)
                        ? () => ref
                              .read(proxiesActionProvider.notifier)
                              .delayTest(data.nodes.values.toList())
                        : null,
                    labels: {
                      'description': text.residentialRouteDescription,
                      'enabled': text.residentialRouteEnabled,
                      'url': text.residentialRouteUrl,
                      'urlHelp': text.residentialRouteUrlHelp,
                      'testNodes': text.delayTest,
                      'delayFailed': text.residentialRouteDelayFailed,
                      'transit': text.residentialRouteTransit,
                      'transitHelp': text.residentialRouteTransitHelp,
                      'connect': text.residentialRouteConnect,
                      'save': text.residentialRouteSave,
                      'working': text.residentialRouteWorking,
                      'saved': text.residentialRouteSaved,
                      'verified': text.residentialRouteVerified,
                      'failed': text.residentialRouteFailed,
                      'unverified': text.residentialRouteUnverified,
                      'airportUnavailable':
                          text.residentialRouteAirportUnavailable,
                      'applyFailed': text.residentialRouteApplyFailed,
                      'selectionFailed': text.residentialRouteSelectionFailed,
                      'profileChanged': text.residentialRouteProfileChanged,
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
      ),
    );
  }
}
