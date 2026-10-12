import 'config.dart';

enum ResidentialRouteOutcome {
  saved,
  verified,
  unverified,
  airportUnavailable,
  applyFailed,
  selectionFailed,
  profileChanged,
}

Future<ResidentialRouteOutcome> applyResidentialRoute({
  required ResidentialRouteConfig config,
  required bool connect,
  required Future<void> Function() save,
  required Future<bool> Function() apply,
  required Future<bool> Function(String name) select,
  required Future<void> Function() closeConnections,
  required Future<bool> Function(String name) test,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return ResidentialRouteOutcome.profileChanged;
  await save();
  if (!isCurrent()) return ResidentialRouteOutcome.profileChanged;
  if (!await apply()) return ResidentialRouteOutcome.applyFailed;
  if (!isCurrent()) return ResidentialRouteOutcome.profileChanged;
  if (connect && config.enabled) {
    if (!await select(config.nodeName(config.selectedTransits.first))) {
      return ResidentialRouteOutcome.selectionFailed;
    }
    if (!isCurrent()) return ResidentialRouteOutcome.profileChanged;
  }
  await closeConnections();
  if (!isCurrent()) return ResidentialRouteOutcome.profileChanged;
  if (!connect) return ResidentialRouteOutcome.saved;
  final transit = config.selectedTransits.first;
  if (!await test(transit)) {
    return isCurrent()
        ? ResidentialRouteOutcome.airportUnavailable
        : ResidentialRouteOutcome.profileChanged;
  }
  if (!isCurrent()) return ResidentialRouteOutcome.profileChanged;
  final passed = await test(config.nodeName(transit));
  if (!isCurrent()) return ResidentialRouteOutcome.profileChanged;
  return passed
      ? ResidentialRouteOutcome.verified
      : ResidentialRouteOutcome.unverified;
}
