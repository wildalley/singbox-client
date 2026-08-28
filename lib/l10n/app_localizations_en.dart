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
  String get rulesChinaDirectBody => 'geosite-cn and geoip-cn bypass the proxy';

  @override
  String get rulesSetsNote =>
      'Rule sets are downloaded from the sing-geosite mirror on first use and refreshed weekly.';

  @override
  String get logsTitle => 'Logs';

  @override
  String get logsFollowing => 'Following';

  @override
  String get logsPaused => 'Paused';

  @override
  String get logsCopyAll => 'Copy all';

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
  String get settingsTunStack => 'TUN stack';

  @override
  String get settingsSystemProxy => 'System HTTP proxy';

  @override
  String get settingsSystemProxyBody =>
      'Also expose a proxy on the tunnel for apps that ignore the VPN';

  @override
  String get settingsStrictRoute => 'Strict route';

  @override
  String get settingsStrictRouteBody =>
      'Block traffic that tries to escape the tunnel';

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
