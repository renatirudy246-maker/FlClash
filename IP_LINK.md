# IP-Link residential routing

This is a modified FlClash build, started on 2026-10-11. Upstream is
<https://github.com/chen08209/FlClash>, based on commit
`4b59eca853778d4e7be3de26589252889c899bc5`. The fork is
<https://github.com/renatirudy246-maker/FlClash>. The upstream GPL-3.0 license
and notices are retained.

## Use

1. Import and select your airport subscription as usual.
2. Open the link button on the dashboard, or Tools → Residential route · IP-Link.
3. Paste the full `socks5://username:password@host:port` URL into the single
   hidden field. Saving parses it automatically. Existing settings fill it
   automatically on upgrade. Percent-encode reserved characters in credentials,
   and bracket IPv6 hosts in URLs. Authentication-free SOCKS5 URLs also work.
4. Tap one or more airport node cards and tap Save and connect. Cards show
   the protocol and the same latency data as the proxy page; their test button
   measures the airport node. Only selected nodes gain corresponding
   `original-name 住宅-tag` SOCKS5 nodes. Original nodes and groups remain.
   The `IP-Link Residential` group contains only residential versions.
   Connect selects the first selected item; switch residential nodes in this
   group afterward. Its tests measure the complete chain. The proxy page shows
   the live residential exit in rule mode; remembered airport group selections
   are independent. A stopped client or a different mode is identified explicitly.
   For provider-only subscriptions, connect the original airport profile first,
   then reopen this page to populate provider nodes.
5. The button shows progress immediately; results appear above it and in a
   snackbar. Results distinguish configuration application, node selection,
   airport testing and residential testing. A successful airport test followed
   by a failed residential test is reported as applied but unverified.
   Success requires testing the selected residential node through the core.
   This tests connectivity, not the provider's claim
   that an address is residential. Confirm the exit address on the phone.
6. Close the page and leave FlClash's VPN service running. To restore the
   original airport routing, disable residential routing and save/apply.

## Behavior

The source subscription is not edited. Residential settings are stored under
a separate, versioned, per-profile key in app-private SharedPreferences,
using the same local storage plugin already used by FlClash. Each runtime
config build applies the settings after ordinary overrides. Subscription
updates and app restarts therefore rebuild the chain from current airport
content. Changing to another profile does not copy residential credentials.
For provider-based profiles, the selected concrete nodes are copied from the
existing provider cache into the runtime config because the dialer lookup only
sees inline proxies. The cache is reread on each apply; missing or ambiguous
nodes fail instead of selecting another transit. No extra provider server runs.

The generated residential SOCKS5 outbound uses `dialer-proxy` pointing at the
airport node, matching the Windows `setup_residential_routes.ps1` backend in
the IP-Link project. The generated configuration uses rule mode. Proxy rule
targets become the residential selection group; DIRECT, REJECT, REJECT-DROP and PASS
rules remain, including nested sub-rules. Existing proxy groups/providers are
retained. Node tags use the desktop host/port/account SHA256 prefix, excluding
passwords. Legacy single-node settings load as a one-item selection.
Saving and applying closes existing connections so a previous
airport route cannot continue under the old selection.

There is no companion app, local configuration server, extra foreground
service or second VPN. The persistent runtime YAML contains everything
the existing core/service needs. As with the desktop implementation,
the residential outbound has `udp: false`; UDP applications are outside
this first implementation. Passwords are obscured in the form and are not
logged by this feature. Settings and generated YAML contain credentials in
the app's private storage and are not independently uploaded.

Invalid saved settings, unsupported versions, missing inline transit nodes,
proxy-group selections, pre-chained inline transit nodes and reserved-name
collisions are rejected. If rebuilding an enabled residential profile fails,
the runtime file contains rejection rules instead of the upstream empty/default
configuration; malformed saved settings follow the same path. A failed
probe is displayed as unverified; it does not prove the exit address. The
existing VPN lifecycle remains owned by SetupAction and the Android service.

## Validation and build

Use the upstream toolchains and build instructions in `.agents/commands.md`.
Do not disable native asset hooks in a packaged build.

Some NDK distributions, including the Windows build and hosted Linux build
used here, omit libclang. Install an external libclang library and configure
`hooks.user_defines.rust_api.libclang_path` in your local build configuration.
The override is validated and used only when building Android.
The build hook uses the NDK's resource headers and the minimum API reported by
Flutter instead of the dependency's hard-coded API 35. Windows builders whose
Pub cache and checkout are on different drives may also need the local Gradle
property `kotlin.incremental=false`.

Targeted tests:

```text
flutter pub get
dart run intl_utils:generate
flutter analyze --no-fatal-infos
flutter test test/common/residential_route_test.dart test/common/residential_route_task_test.dart test/widgets/residential_route_editor_test.dart test/providers/setup_action_test.dart
```

The `IP-Link Android` GitHub Actions workflow builds this fork's
`residential-route` branch on a hosted runner, including analysis and the
targeted routing tests. Download the `FlClash-IP-Link-arm64` artifact from the
successful run. The APK includes both native asset hooks and requires an
ARM64 phone with Android 7.0 (API 24) or newer. With no release keystore
configured, the test package uses a development certificate and the package
`com.follow.clash.iplink`, which can coexist with stable FlClash and the earlier
`com.follow.clash.dev` test build without removing their settings. Cloud runner
certificates change between builds; locally delivered APKs are re-signed with a
persistent private test keystore so future local deliveries can update in place.
Stop the other client's VPN before connecting this build. This is a test
distribution; the build workflow does not publish a stable release.
The release UI omits the pre-release ribbon; safe-mode and debug warnings remain.

The current residential/proxy checks passed 92 targeted Flutter tests and root
Dart analysis, with 98.07% residential-module coverage. An isolated Mihomo fixture
verified both airport-to-residential chains, node switching, restart persistence
and failure without direct fallback on incorrect credentials.
Broader local widget/localization checks passed 584 tests with two environment
limitations: the dynamic-message lint does not normalize Windows separators,
and a script-editor test needs a native Rust library absent from the lightweight
test checkout. The full native-enabled suite runs in hosted CI; these local
checks do not establish that the complete suite passes on Windows.

Additional acceptance must check the Android page, a real chain and exit IP,
closing the configuration page, service restart, subscription refresh and
disabling the feature. A unit test or successful APK build alone does not
establish device/network acceptance.
