// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'SingBox Client';

  @override
  String get appShortName => 'SingBox';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSave => 'Save';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionRemove => 'Remove';

  @override
  String get actionImport => 'Import';

  @override
  String get actionUpdate => 'Update';

  @override
  String get actionRefresh => 'Refresh';

  @override
  String get actionConnect => 'Connect';

  @override
  String get actionDisconnect => 'Disconnect';

  @override
  String get actionTestLatency => 'Test latency';

  @override
  String get navHome => 'Home';

  @override
  String get navNodes => 'Nodes';

  @override
  String get navRules => 'Rules';

  @override
  String get navLogs => 'Logs';

  @override
  String get navSettings => 'Settings';

  @override
  String get railOverview => 'Overview';

  @override
  String get stageConnected => 'Connected';

  @override
  String get stageDisconnected => 'Disconnected';

  @override
  String get stageConnecting => 'Connecting';

  @override
  String get stageDisconnecting => 'Disconnecting';

  @override
  String get stageAwaitingPermission => 'Awaiting permission';

  @override
  String get stageFailed => 'Failed';

  @override
  String get greetingMorning => 'Good morning';

  @override
  String get greetingAfternoon => 'Good afternoon';

  @override
  String get greetingEvening => 'Good evening';

  @override
  String get greetingNight => 'Good night';

  @override
  String get homeSubtitle => 'Your connection at a glance';

  @override
  String get homeReadyToConnect => 'Ready to connect';

  @override
  String get homeProtected => 'Protected';

  @override
  String homeProtectedFor(String uptime) {
    return 'Protected · $uptime';
  }

  @override
  String get homeCoverageTun => 'TUN active';

  @override
  String get homeCoverageSystemProxy => 'System proxy applied';

  @override
  String get homeCoverageSystemProxyUnavailable =>
      'Core connected · system proxy unavailable';

  @override
  String get homeCoverageLocalProxy => 'Local proxy only';

  @override
  String get homeCheckTheLogs => 'Check the logs';

  @override
  String get homeNoNodesYet => 'No nodes yet';

  @override
  String get homeAddNodes => 'Add nodes';

  @override
  String get homeImportPrompt =>
      'Import a subscription or paste share links to get started.';

  @override
  String get homeLiveTraffic => 'Live traffic';

  @override
  String get homeDownload => 'Download';

  @override
  String get homeUpload => 'Upload';

  @override
  String get homeActiveNode => 'Active node';

  @override
  String get homeNoNodeSelected => 'No node selected';

  @override
  String get trayShowWindow => 'Show window';

  @override
  String get trayHideWindow => 'Hide window';

  @override
  String get trayQuit => 'Quit';

  @override
  String get trayTooltipConnected => 'Connected';

  @override
  String get trayTooltipDisconnected => 'Not connected';

  @override
  String get settingsCloseToTray => 'Close to tray';

  @override
  String get settingsCloseToTrayBody =>
      'Closing the window leaves the tunnel running. Turn this off to quit instead.';

  @override
  String get homeExitIp => 'Exit IP';

  @override
  String get homeExitUnknown => 'Unknown';

  @override
  String get homeChangeNode => 'Change node';

  @override
  String get homeSession => 'Session';

  @override
  String get homeTotals => 'Totals';

  @override
  String get homeDownloaded => 'Downloaded';

  @override
  String get homeUploaded => 'Uploaded';

  @override
  String get homeConnections => 'Connections';

  @override
  String get homeMemory => 'Memory';

  @override
  String get homeLatency => 'Latency';

  @override
  String get homeAvailableNodes => 'Available nodes';

  @override
  String homeAvailableOf(int available, int total) {
    return '$available / $total';
  }

  @override
  String get homeUptime => 'Uptime';

  @override
  String get homeOverview => 'Overview';

  @override
  String get homeTrafficFlow => 'Traffic flow';

  @override
  String get homeLastMinute => 'Last 60s';

  @override
  String get homeUntestedNodes => 'Not tested yet';

  @override
  String get nodesTitle => 'Nodes';

  @override
  String get nodesSearch => 'Search nodes';

  @override
  String get nodesFilterAll => 'All';

  @override
  String get nodesFilterFavorites => 'Favorites';

  @override
  String get nodesFilterFast => 'Fast';

  @override
  String get nodesGroupManual => 'Manual';

  @override
  String get nodesSortLatency => 'Sort by latency';

  @override
  String get nodesSortSource => 'Sort by source order';

  @override
  String get nodesSourceAll => 'All sources';

  @override
  String get nodesAuto => 'Auto';

  @override
  String get nodesAutoBody => 'Fastest node, chosen by the engine';

  @override
  String get nodesNoMatches => 'No matches';

  @override
  String get nodesNoMatchesBody =>
      'No nodes match the current search or filter.';

  @override
  String get nodesNothingImported => 'Nothing imported yet';

  @override
  String get nodesImportBody =>
      'Import a subscription URL, paste share links, or load a sing-box config file.';

  @override
  String get nodesImportTitle => 'Import nodes';

  @override
  String get nodesRemoveSource => 'Remove source?';

  @override
  String nodesRemoveSourceBody(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nodes',
      one: '1 node',
    );
    return 'This removes $name and its $_temp0 from this device.';
  }

  @override
  String nodesCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nodes',
      one: '1 node',
    );
    return '$_temp0';
  }

  @override
  String get nodesUntested => 'Untested';

  @override
  String get nodesUnreachable => 'Unreachable';

  @override
  String get rulesTitle => 'Rules';

  @override
  String get rulesHowRouted => 'How traffic is routed';

  @override
  String get rulesRoutingMode => 'Routing mode';

  @override
  String get rulesModeGlobal => 'Global';

  @override
  String get rulesModeRule => 'Rule';

  @override
  String get rulesModeDirect => 'Direct';

  @override
  String get rulesModeGlobalBody => 'Everything goes through the proxy.';

  @override
  String get rulesModeRuleBody =>
      'Mainland China sites and IPs stay direct, everything else is proxied.';

  @override
  String get rulesModeDirectBody =>
      'Nothing is proxied. The tunnel stays up but traffic goes out directly.';

  @override
  String get rulesMatchOn => 'Match on';

  @override
  String get rulesSendTo => 'Send to';

  @override
  String get rulesCustom => 'Your rules';

  @override
  String get rulesCustomNote =>
      'Matched in order, above the bundled lists. Changes apply immediately.';

  @override
  String get rulesCustomEmpty => 'No rules of your own yet';

  @override
  String get rulesCustomEmptyBody =>
      'Add one to send a single domain, address, or port a different way.';

  @override
  String get rulesCustomAdd => 'Add rule';

  @override
  String get rulesCustomEdit => 'Edit rule';

  @override
  String get rulesMatcherDomain => 'Domain';

  @override
  String get rulesMatcherDomainSuffix => 'Domain and subdomains';

  @override
  String get rulesMatcherDomainKeyword => 'Domain contains';

  @override
  String get rulesMatcherIpCidr => 'IP or CIDR';

  @override
  String get rulesMatcherPort => 'Port';

  @override
  String get rulesMatcherProcessName => 'Process name';

  @override
  String get rulesTargetProxy => 'Proxy';

  @override
  String get rulesTargetDirect => 'Direct';

  @override
  String get rulesTargetBlock => 'Block';

  @override
  String get rulesValueHintDomain => 'example.com';

  @override
  String get rulesValueHintKeyword => 'tracker';

  @override
  String get rulesValueHintIpCidr => '10.0.0.0/8';

  @override
  String get rulesValueHintPort => '443';

  @override
  String get rulesValueHintProcess => 'curl';

  @override
  String get rulesProblemEmpty => 'Enter a value';

  @override
  String get rulesProblemPort => 'Must be a port from 1 to 65535';

  @override
  String get rulesProblemCidr => 'Must be an IP address or CIDR block';

  @override
  String get rulesProblemUrl => 'Enter a hostname, not a URL';

  @override
  String get rulesRuleDisabled => 'Off';

  @override
  String get rulesMoveUp => 'Move up';

  @override
  String get rulesMoveDown => 'Move down';

  @override
  String get rulesActive => 'Active rules';

  @override
  String get rulesDnsInterception => 'DNS interception';

  @override
  String get rulesDnsInterceptionBody =>
      'Queries are answered by the built-in resolver';

  @override
  String get rulesPrivateAddresses => 'Private addresses';

  @override
  String get rulesPrivateAddressesBody => 'LAN and loopback stay direct';

  @override
  String get rulesChinaDirect => 'China direct';

  @override
  String get rulesOnlyInRuleMode => 'Only applies in Rule mode';

  @override
  String get rulesAdsAndTrackers => 'Ads and trackers';

  @override
  String get rulesRejectedViaGeosite => 'Rejected via geosite';

  @override
  String get rulesNotFiltered => 'Not filtered';

  @override
  String get rulesStateOff => 'Off';

  @override
  String get rulesStateOn => 'On';

  @override
  String get rulesBadgeDirect => 'DIRECT';

  @override
  String get rulesBadgeProxy => 'PROXY';

  @override
  String get rulesBadgeBlock => 'BLOCK';

  @override
  String get rulesBadgeDns => 'DNS';

  @override
  String get rulesChinaDirectBody => 'geosite-cn and geoip-cn bypass the proxy';

  @override
  String get rulesFallback => 'Everything else';

  @override
  String get rulesFallbackProxy => 'Goes through the selected node';

  @override
  String get rulesFallbackDirect => 'Leaves directly; the tunnel stays up';

  @override
  String get rulesSetsNote =>
      'Rule sets ship with the app and update from Settings. A new download applies at the next connect.';

  @override
  String get logsTitle => 'Logs';

  @override
  String get logsFollowing => 'Following';

  @override
  String get logsPaused => 'Paused';

  @override
  String get logsCopyAll => 'Copy all';

  @override
  String get logsClear => 'Clear logs';

  @override
  String get logsCopied => 'Logs copied';

  @override
  String get logsNoneYet => 'No logs yet';

  @override
  String get logsNothingLogged => 'Nothing logged yet';

  @override
  String get logsConnectToSee =>
      'Connect the tunnel to see runtime output from sing-box.';

  @override
  String logsEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return '$_temp0';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSubtitle => 'Tune your connection';

  @override
  String get settingsSubscriptions => 'Subscriptions';

  @override
  String get settingsAddSubscription => 'Add subscription or nodes';

  @override
  String get settingsAddSubscriptionBody =>
      'URL, share links, or a sing-box config';

  @override
  String get settingsProxy => 'Proxy';

  @override
  String get settingsProxyMode => 'Proxy mode';

  @override
  String get settingsProxyModeTun => 'TUN';

  @override
  String get settingsProxyModeSystemProxy => 'System proxy';

  @override
  String get settingsTunStack => 'TUN stack';

  @override
  String get settingsSystemProxy => 'System HTTP proxy';

  @override
  String get settingsSystemProxyBody =>
      'Expose the local proxy; on Windows, also enable it in WinINet';

  @override
  String get settingsStrictRoute => 'Strict route';

  @override
  String get settingsStrictRouteBody =>
      'Block traffic that tries to escape the tunnel';

  @override
  String get settingsRouting => 'Routing';

  @override
  String get settingsRuleSets => 'Rule sets';

  @override
  String get settingsRuleSetsBundled => 'Bundled with the app';

  @override
  String settingsRuleSetsDownloaded(String ago) {
    return 'downloaded $ago';
  }

  @override
  String get settingsRuleSetsRemote => 'Fetched by the engine at start';

  @override
  String get settingsNetwork => 'Network';

  @override
  String get settingsRemoteDns => 'Remote DNS';

  @override
  String get settingsDirectDns => 'Direct DNS';

  @override
  String get settingsDnsHint =>
      'Accepts https://, tls://, quic://, h3://, udp:// and tcp:// URLs.';

  @override
  String get settingsFakeIp => 'FakeIP';

  @override
  String get settingsFakeIpBody =>
      'Faster lookups; breaks apps that need real addresses';

  @override
  String get settingsIpv6 => 'IPv6';

  @override
  String get settingsIpv4Only => 'IPv4 only';

  @override
  String get settingsPreferIpv4 => 'Prefer IPv4, allow IPv6';

  @override
  String get settingsMtu => 'MTU';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsDiagnostics => 'Diagnostics';

  @override
  String get settingsRuntimeLogs => 'Runtime logs';

  @override
  String settingsEntriesBuffered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries buffered',
      one: '1 entry buffered',
    );
    return '$_temp0';
  }

  @override
  String get settingsGeneratedConfig => 'Generated config';

  @override
  String get settingsGeneratedConfigBody => 'Inspect what is sent to sing-box';

  @override
  String get settingsConfigCopied => 'Config copied';

  @override
  String get settingsContainsCredentials =>
      'Contains credentials. Do not share.';

  @override
  String get settingsLogLevel => 'Log level';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAppVersion => 'App version';

  @override
  String get settingsCore => 'sing-box core';

  @override
  String get settingsChecking => 'checking…';

  @override
  String settingsRemoveSubscription(String name) {
    return 'Remove $name?';
  }

  @override
  String settingsRemoveSubscriptionBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nodes',
      one: '1 node',
    );
    return 'This deletes its $_temp0 from this device.';
  }

  @override
  String get importTitle => 'Import nodes';

  @override
  String get importNameOptional => 'Name (optional)';

  @override
  String get importPasteFromClipboard => 'Paste from clipboard';

  @override
  String get importPaste => 'Paste';

  @override
  String get importFile => 'File';

  @override
  String get importInProgress => 'Importing…';

  @override
  String get importHint =>
      'Subscription URL, share links (vless, vmess, trojan, ss, hysteria2, tuic), or a sing-box JSON config.';

  @override
  String get noticeNeedNodes => 'Add a node or subscription first';

  @override
  String get noticePermissionDenied => 'VPN permission denied';

  @override
  String noticeSwitchFailed(String detail) {
    return 'Switch failed: $detail';
  }

  @override
  String noticeReloadFailed(String detail) {
    return 'Reload failed: $detail';
  }

  @override
  String noticeNoUrlToRefresh(String name) {
    return '$name has no URL to refresh';
  }

  @override
  String noticeSubscriptionUpdated(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nodes',
      one: '1 node',
    );
    return '$name: $_temp0';
  }

  @override
  String noticeNodesImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nodes imported',
      one: '1 node imported',
    );
    return '$_temp0';
  }

  @override
  String noticeNodesImportedSkipped(int count, int skipped) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nodes imported',
      one: '1 node imported',
    );
    return '$_temp0, $skipped skipped';
  }

  @override
  String get importedDefaultName => 'Imported';

  @override
  String get noticeImportUnreachable =>
      'Could not reach the subscription. If it is blocked, connect first, then update again.';

  @override
  String noticeImportHttpStatus(int code) {
    return 'The subscription returned HTTP $code';
  }

  @override
  String get noticeImportUnusable => 'No usable nodes in what came back';

  @override
  String get noticeImportBadSource => 'Not a usable subscription or config';

  @override
  String get noticeImportTimeout => 'The subscription took too long to respond';

  @override
  String get noticeImportTooLarge => 'The subscription response is too large';

  @override
  String get noticeRuleSetsUpdated =>
      'Rule sets updated — active at the next connect';

  @override
  String get noticeRuleSetsUpdateFailed =>
      'Could not update the rule sets; keeping the current lists';

  @override
  String get noticeRuleSetsUnavailable =>
      'This platform has no local rule sets to update';

  @override
  String get noticeEngineMissing =>
      'No sing-box binary found. Install sing-box, or point SINGBOX_BINARY at one.';

  @override
  String noticeEngineTooOld(String version) {
    return 'sing-box $version is too old for this config; 1.12 or newer is needed.';
  }

  @override
  String noticeTunUnprivileged(String binary) {
    return 'TUN was not authorized. Connect again to get the prompt, grant it with: sudo setcap cap_net_admin,cap_net_raw+ep $binary — or switch to system proxy mode.';
  }

  @override
  String platformUnsupported(String platform) {
    return 'The $platform runtime is not implemented yet. Config rendering and node management still work.';
  }

  @override
  String nodesSubtitle(int nodes, int sources) {
    return '$nodes endpoints · $sources sources';
  }

  @override
  String nodesUpdatedAgo(String ago) {
    return 'updated $ago';
  }

  @override
  String nodesDaysLeft(int days) {
    return '$days days left';
  }

  @override
  String get nodesExpired => 'expired';

  @override
  String get agoJustNow => 'just now';

  @override
  String agoMinutes(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String agoHours(int hours) {
    return '${hours}h ago';
  }

  @override
  String agoDays(int days) {
    return '${days}d ago';
  }

  @override
  String get latencyFail => 'fail';

  @override
  String get latencyUnknown => '—';

  @override
  String get logsNewestLast => 'newest last';
}
