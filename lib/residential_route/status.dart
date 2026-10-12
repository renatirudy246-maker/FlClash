import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'config.dart';

class ResidentialRouteStatus extends ConsumerWidget {
  const ResidentialRouteStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref
        .watch(groupsProvider)
        .getGroup(ResidentialRouteConfig.routeName);
    if (group == null) return const SizedBox.shrink();
    final text = context.appLocalizations;
    final running = ref.watch(isStartProvider) && !ref.watch(suspendProvider);
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final selected = group.all
        .where((node) => node.name == group.now)
        .firstOrNull;
    final residential =
        selected != null &&
        selected.type.toLowerCase() == 'socks5' &&
        selected.name.contains(' 住宅-');
    final title = !running
        ? text.residentialRouteStopped
        : mode != Mode.rule
        ? text.residentialRouteOtherMode
        : !residential
        ? text.residentialRouteNotSelected
        : text.residentialRouteActive(selected.name);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, key: const ValueKey('residential-active-route')),
          if (running && mode == Mode.rule && residential)
            Text(
              text.residentialRouteGroupHelp,
              style: context.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
