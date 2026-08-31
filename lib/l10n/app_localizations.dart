import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'SingBox Client'**
  String get appTitle;

  /// No description provided for @appShortName.
  ///
  /// In en, this message translates to:
  /// **'SingBox'**
  String get appShortName;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// No description provided for @actionImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get actionImport;

  /// No description provided for @actionUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get actionUpdate;

  /// No description provided for @actionRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get actionRefresh;

  /// No description provided for @actionConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get actionConnect;

  /// No description provided for @actionDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get actionDisconnect;

  /// No description provided for @actionTestLatency.
  ///
  /// In en, this message translates to:
  /// **'Test latency'**
  String get actionTestLatency;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navNodes.
  ///
  /// In en, this message translates to:
  /// **'Nodes'**
  String get navNodes;

  /// No description provided for @navRules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get navRules;

  /// No description provided for @navLogs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get navLogs;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @railOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get railOverview;

  /// No description provided for @stageConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get stageConnected;

  /// No description provided for @stageDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get stageDisconnected;

  /// No description provided for @stageConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get stageConnecting;

  /// No description provided for @stageDisconnecting.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting'**
  String get stageDisconnecting;

  /// No description provided for @stageAwaitingPermission.
  ///
  /// In en, this message translates to:
  /// **'Awaiting permission'**
  String get stageAwaitingPermission;

  /// No description provided for @stageFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get stageFailed;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get greetingEvening;

  /// No description provided for @greetingNight.
  ///
  /// In en, this message translates to:
  /// **'Good night'**
  String get greetingNight;

  /// No description provided for @homeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your connection at a glance'**
  String get homeSubtitle;

  /// No description provided for @homeReadyToConnect.
  ///
  /// In en, this message translates to:
  /// **'Ready to connect'**
  String get homeReadyToConnect;

  /// No description provided for @homeProtected.
  ///
  /// In en, this message translates to:
  /// **'Protected'**
  String get homeProtected;

  /// No description provided for @homeProtectedFor.
  ///
  /// In en, this message translates to:
  /// **'Protected · {uptime}'**
  String homeProtectedFor(String uptime);

  /// No description provided for @homeCheckTheLogs.
  ///
  /// In en, this message translates to:
  /// **'Check the logs'**
  String get homeCheckTheLogs;

  /// No description provided for @homeNoNodesYet.
  ///
  /// In en, this message translates to:
  /// **'No nodes yet'**
  String get homeNoNodesYet;

  /// No description provided for @homeAddNodes.
  ///
  /// In en, this message translates to:
  /// **'Add nodes'**
  String get homeAddNodes;

  /// No description provided for @homeImportPrompt.
  ///
  /// In en, this message translates to:
  /// **'Import a subscription or paste share links to get started.'**
  String get homeImportPrompt;

  /// No description provided for @homeLiveTraffic.
  ///
  /// In en, this message translates to:
  /// **'Live traffic'**
  String get homeLiveTraffic;

  /// No description provided for @homeDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get homeDownload;

  /// No description provided for @homeUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get homeUpload;

  /// No description provided for @homeActiveNode.
  ///
  /// In en, this message translates to:
  /// **'Active node'**
  String get homeActiveNode;

  /// No description provided for @homeNoNodeSelected.
  ///
  /// In en, this message translates to:
  /// **'No node selected'**
  String get homeNoNodeSelected;

  /// No description provided for @homeChangeNode.
  ///
  /// In en, this message translates to:
  /// **'Change node'**
  String get homeChangeNode;

  /// No description provided for @homeSession.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get homeSession;

  /// No description provided for @homeTotals.
  ///
  /// In en, this message translates to:
  /// **'Totals'**
  String get homeTotals;

  /// No description provided for @homeDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get homeDownloaded;

  /// No description provided for @homeUploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get homeUploaded;

  /// No description provided for @homeConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get homeConnections;

  /// No description provided for @homeMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get homeMemory;

  /// No description provided for @homeLatency.
  ///
  /// In en, this message translates to:
  /// **'Latency'**
  String get homeLatency;

  /// No description provided for @homeAvailableNodes.
  ///
  /// In en, this message translates to:
  /// **'Available nodes'**
  String get homeAvailableNodes;

  /// Nodes that answered a latency probe, out of the total imported.
  ///
  /// In en, this message translates to:
  /// **'{available} / {total}'**
  String homeAvailableOf(int available, int total);

  /// No description provided for @homeUptime.
  ///
  /// In en, this message translates to:
  /// **'Uptime'**
  String get homeUptime;

  /// No description provided for @homeOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get homeOverview;

  /// No description provided for @homeTrafficFlow.
  ///
  /// In en, this message translates to:
  /// **'Traffic flow'**
  String get homeTrafficFlow;

  /// No description provided for @homeLastMinute.
  ///
  /// In en, this message translates to:
  /// **'Last 60s'**
  String get homeLastMinute;

  /// No description provided for @homeUntestedNodes.
  ///
  /// In en, this message translates to:
  /// **'Not tested yet'**
  String get homeUntestedNodes;

  /// No description provided for @nodesTitle.
  ///
  /// In en, this message translates to:
  /// **'Nodes'**
  String get nodesTitle;

  /// No description provided for @nodesSearch.
  ///
  /// In en, this message translates to:
  /// **'Search nodes'**
  String get nodesSearch;

  /// No description provided for @nodesFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get nodesFilterAll;

  /// No description provided for @nodesFilterFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get nodesFilterFavorites;

  /// No description provided for @nodesFilterFast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get nodesFilterFast;

  /// No description provided for @nodesGroupManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get nodesGroupManual;

  /// Tooltip on the sort button while the list is in source order: names what tapping it does, not the current state.
  ///
  /// In en, this message translates to:
  /// **'Sort by latency'**
  String get nodesSortLatency;

  /// Tooltip on the sort button while the list is in latency order. 'Source order' is the order the subscription itself handed the nodes over.
  ///
  /// In en, this message translates to:
  /// **'Sort by source order'**
  String get nodesSortSource;

  /// Source picker, shown only with more than one source: without it the second subscription's nodes are only reachable by scrolling past all of the first's.
  ///
  /// In en, this message translates to:
  /// **'All sources'**
  String get nodesSourceAll;

  /// The urltest group as a selection: the engine measures the nodes and picks the fastest by itself. Named as a choice alongside the nodes, not as a setting.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get nodesAuto;

  /// No description provided for @nodesAutoBody.
  ///
  /// In en, this message translates to:
  /// **'Fastest node, chosen by the engine'**
  String get nodesAutoBody;

  /// No description provided for @nodesNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get nodesNoMatches;

  /// No description provided for @nodesNoMatchesBody.
  ///
  /// In en, this message translates to:
  /// **'No nodes match the current search or filter.'**
  String get nodesNoMatchesBody;

  /// No description provided for @nodesNothingImported.
  ///
  /// In en, this message translates to:
  /// **'Nothing imported yet'**
  String get nodesNothingImported;

  /// No description provided for @nodesImportBody.
  ///
  /// In en, this message translates to:
  /// **'Import a subscription URL, paste share links, or load a sing-box config file.'**
  String get nodesImportBody;

  /// No description provided for @nodesImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import nodes'**
  String get nodesImportTitle;

  /// No description provided for @nodesRemoveSource.
  ///
  /// In en, this message translates to:
  /// **'Remove source?'**
  String get nodesRemoveSource;

  /// No description provided for @nodesRemoveSourceBody.
  ///
  /// In en, this message translates to:
  /// **'This removes {name} and its {count, plural, =1{1 node} other{{count} nodes}} from this device.'**
  String nodesRemoveSourceBody(String name, int count);

  /// No description provided for @nodesCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 node} other{{count} nodes}}'**
  String nodesCountLabel(int count);

  /// No description provided for @nodesUntested.
  ///
  /// In en, this message translates to:
  /// **'Untested'**
  String get nodesUntested;

  /// No description provided for @nodesUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Unreachable'**
  String get nodesUnreachable;

  /// No description provided for @rulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get rulesTitle;

  /// No description provided for @rulesHowRouted.
  ///
  /// In en, this message translates to:
  /// **'How traffic is routed'**
  String get rulesHowRouted;

  /// No description provided for @rulesRoutingMode.
  ///
  /// In en, this message translates to:
  /// **'Routing mode'**
  String get rulesRoutingMode;

  /// No description provided for @rulesModeGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get rulesModeGlobal;

  /// No description provided for @rulesModeRule.
  ///
  /// In en, this message translates to:
  /// **'Rule'**
  String get rulesModeRule;

  /// No description provided for @rulesModeDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get rulesModeDirect;

  /// No description provided for @rulesModeGlobalBody.
  ///
  /// In en, this message translates to:
  /// **'Everything goes through the proxy.'**
  String get rulesModeGlobalBody;

  /// No description provided for @rulesModeRuleBody.
  ///
  /// In en, this message translates to:
  /// **'Mainland China sites and IPs stay direct, everything else is proxied.'**
  String get rulesModeRuleBody;

  /// No description provided for @rulesModeDirectBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing is proxied. The tunnel stays up but traffic goes out directly.'**
  String get rulesModeDirectBody;

  /// No description provided for @rulesActive.
  ///
  /// In en, this message translates to:
  /// **'Active rules'**
  String get rulesActive;

  /// No description provided for @rulesDnsInterception.
  ///
  /// In en, this message translates to:
  /// **'DNS interception'**
  String get rulesDnsInterception;

  /// No description provided for @rulesDnsInterceptionBody.
  ///
  /// In en, this message translates to:
  /// **'Queries are answered by the built-in resolver'**
  String get rulesDnsInterceptionBody;

  /// No description provided for @rulesPrivateAddresses.
  ///
  /// In en, this message translates to:
  /// **'Private addresses'**
  String get rulesPrivateAddresses;

  /// No description provided for @rulesPrivateAddressesBody.
  ///
  /// In en, this message translates to:
  /// **'LAN and loopback stay direct'**
  String get rulesPrivateAddressesBody;

  /// No description provided for @rulesChinaDirect.
  ///
  /// In en, this message translates to:
  /// **'China direct'**
  String get rulesChinaDirect;

  /// No description provided for @rulesOnlyInRuleMode.
  ///
  /// In en, this message translates to:
  /// **'Only applies in Rule mode'**
  String get rulesOnlyInRuleMode;

  /// No description provided for @rulesAdsAndTrackers.
  ///
  /// In en, this message translates to:
  /// **'Ads and trackers'**
  String get rulesAdsAndTrackers;

  /// No description provided for @rulesRejectedViaGeosite.
  ///
  /// In en, this message translates to:
  /// **'Rejected via geosite'**
  String get rulesRejectedViaGeosite;

  /// No description provided for @rulesNotFiltered.
  ///
  /// In en, this message translates to:
  /// **'Not filtered'**
  String get rulesNotFiltered;

  /// No description provided for @rulesStateOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get rulesStateOff;

  /// No description provided for @rulesStateOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get rulesStateOn;

  /// Badge on a rule row: matching traffic leaves without the proxy. Mirrors the sing-box outbound keyword, so it stays uppercase Latin in every locale.
  ///
  /// In en, this message translates to:
  /// **'DIRECT'**
  String get rulesBadgeDirect;

  /// Badge on a rule row: matching traffic goes through the selected node. Mirrors the sing-box outbound keyword, so it stays uppercase Latin in every locale.
  ///
  /// In en, this message translates to:
  /// **'PROXY'**
  String get rulesBadgeProxy;

  /// Badge on a rule row: matching traffic is rejected. Mirrors the sing-box reject action, so it stays uppercase Latin in every locale.
  ///
  /// In en, this message translates to:
  /// **'BLOCK'**
  String get rulesBadgeBlock;

  /// Badge on the DNS interception row. That rule hijacks queries to the built-in resolver rather than routing them, so it gets its own verb instead of DIRECT/PROXY/BLOCK.
  ///
  /// In en, this message translates to:
  /// **'DNS'**
  String get rulesBadgeDns;

  /// No description provided for @rulesChinaDirectBody.
  ///
  /// In en, this message translates to:
  /// **'geosite-cn and geoip-cn bypass the proxy'**
  String get rulesChinaDirectBody;

  /// The last rule row: the config's `final` outbound, which catches traffic no earlier rule matched.
  ///
  /// In en, this message translates to:
  /// **'Everything else'**
  String get rulesFallback;

  /// No description provided for @rulesFallbackProxy.
  ///
  /// In en, this message translates to:
  /// **'Goes through the selected node'**
  String get rulesFallbackProxy;

  /// No description provided for @rulesFallbackDirect.
  ///
  /// In en, this message translates to:
  /// **'Leaves directly; the tunnel stays up'**
  String get rulesFallbackDirect;

  /// Footer under the rule list. The lists are unpacked from the app on first run rather than fetched, and the engine reads them off disk when it starts, so an update cannot reach a running tunnel.
  ///
  /// In en, this message translates to:
  /// **'Rule sets ship with the app and update from Settings. A new download applies at the next connect.'**
  String get rulesSetsNote;

  /// No description provided for @logsTitle.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logsTitle;

  /// No description provided for @logsFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get logsFollowing;

  /// No description provided for @logsPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get logsPaused;

  /// No description provided for @logsCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get logsCopyAll;

  /// No description provided for @logsCopied.
  ///
  /// In en, this message translates to:
  /// **'Logs copied'**
  String get logsCopied;

  /// No description provided for @logsNoneYet.
  ///
  /// In en, this message translates to:
  /// **'No logs yet'**
  String get logsNoneYet;

  /// No description provided for @logsNothingLogged.
  ///
  /// In en, this message translates to:
  /// **'Nothing logged yet'**
  String get logsNothingLogged;

  /// No description provided for @logsConnectToSee.
  ///
  /// In en, this message translates to:
  /// **'Connect the tunnel to see runtime output from sing-box.'**
  String get logsConnectToSee;

  /// No description provided for @logsEntryCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry} other{{count} entries}}'**
  String logsEntryCount(int count);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tune your connection'**
  String get settingsSubtitle;

  /// No description provided for @settingsSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get settingsSubscriptions;

  /// No description provided for @settingsAddSubscription.
  ///
  /// In en, this message translates to:
  /// **'Add subscription or nodes'**
  String get settingsAddSubscription;

  /// No description provided for @settingsAddSubscriptionBody.
  ///
  /// In en, this message translates to:
  /// **'URL, share links, or a sing-box config'**
  String get settingsAddSubscriptionBody;

  /// No description provided for @settingsProxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get settingsProxy;

  /// No description provided for @settingsTunStack.
  ///
  /// In en, this message translates to:
  /// **'TUN stack'**
  String get settingsTunStack;

  /// No description provided for @settingsSystemProxy.
  ///
  /// In en, this message translates to:
  /// **'System HTTP proxy'**
  String get settingsSystemProxy;

  /// No description provided for @settingsSystemProxyBody.
  ///
  /// In en, this message translates to:
  /// **'Also expose a proxy on the tunnel for apps that ignore the VPN'**
  String get settingsSystemProxyBody;

  /// No description provided for @settingsStrictRoute.
  ///
  /// In en, this message translates to:
  /// **'Strict route'**
  String get settingsStrictRoute;

  /// No description provided for @settingsStrictRouteBody.
  ///
  /// In en, this message translates to:
  /// **'Block traffic that tries to escape the tunnel'**
  String get settingsStrictRouteBody;

  /// No description provided for @settingsRouting.
  ///
  /// In en, this message translates to:
  /// **'Routing'**
  String get settingsRouting;

  /// No description provided for @settingsRuleSets.
  ///
  /// In en, this message translates to:
  /// **'Rule sets'**
  String get settingsRuleSets;

  /// No description provided for @settingsRuleSetsBundled.
  ///
  /// In en, this message translates to:
  /// **'Bundled with the app'**
  String get settingsRuleSetsBundled;

  /// No description provided for @settingsRuleSetsDownloaded.
  ///
  /// In en, this message translates to:
  /// **'downloaded {ago}'**
  String settingsRuleSetsDownloaded(String ago);

  /// No description provided for @settingsRuleSetsRemote.
  ///
  /// In en, this message translates to:
  /// **'Fetched by the engine at start'**
  String get settingsRuleSetsRemote;

  /// No description provided for @settingsNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get settingsNetwork;

  /// No description provided for @settingsRemoteDns.
  ///
  /// In en, this message translates to:
  /// **'Remote DNS'**
  String get settingsRemoteDns;

  /// No description provided for @settingsDirectDns.
  ///
  /// In en, this message translates to:
  /// **'Direct DNS'**
  String get settingsDirectDns;

  /// No description provided for @settingsDnsHint.
  ///
  /// In en, this message translates to:
  /// **'Accepts https://, tls://, quic://, h3://, udp:// and tcp:// URLs.'**
  String get settingsDnsHint;

  /// No description provided for @settingsFakeIp.
  ///
  /// In en, this message translates to:
  /// **'FakeIP'**
  String get settingsFakeIp;

  /// No description provided for @settingsFakeIpBody.
  ///
  /// In en, this message translates to:
  /// **'Faster lookups; breaks apps that need real addresses'**
  String get settingsFakeIpBody;

  /// No description provided for @settingsIpv6.
  ///
  /// In en, this message translates to:
  /// **'IPv6'**
  String get settingsIpv6;

  /// No description provided for @settingsIpv4Only.
  ///
  /// In en, this message translates to:
  /// **'IPv4 only'**
  String get settingsIpv4Only;

  /// No description provided for @settingsPreferIpv4.
  ///
  /// In en, this message translates to:
  /// **'Prefer IPv4, allow IPv6'**
  String get settingsPreferIpv4;

  /// No description provided for @settingsMtu.
  ///
  /// In en, this message translates to:
  /// **'MTU'**
  String get settingsMtu;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get settingsDiagnostics;

  /// No description provided for @settingsRuntimeLogs.
  ///
  /// In en, this message translates to:
  /// **'Runtime logs'**
  String get settingsRuntimeLogs;

  /// No description provided for @settingsEntriesBuffered.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry buffered} other{{count} entries buffered}}'**
  String settingsEntriesBuffered(int count);

  /// No description provided for @settingsGeneratedConfig.
  ///
  /// In en, this message translates to:
  /// **'Generated config'**
  String get settingsGeneratedConfig;

  /// No description provided for @settingsGeneratedConfigBody.
  ///
  /// In en, this message translates to:
  /// **'Inspect what is sent to sing-box'**
  String get settingsGeneratedConfigBody;

  /// No description provided for @settingsConfigCopied.
  ///
  /// In en, this message translates to:
  /// **'Config copied'**
  String get settingsConfigCopied;

  /// No description provided for @settingsContainsCredentials.
  ///
  /// In en, this message translates to:
  /// **'Contains credentials. Do not share.'**
  String get settingsContainsCredentials;

  /// No description provided for @settingsLogLevel.
  ///
  /// In en, this message translates to:
  /// **'Log level'**
  String get settingsLogLevel;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsAppVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get settingsAppVersion;

  /// No description provided for @settingsCore.
  ///
  /// In en, this message translates to:
  /// **'sing-box core'**
  String get settingsCore;

  /// No description provided for @settingsChecking.
  ///
  /// In en, this message translates to:
  /// **'checking…'**
  String get settingsChecking;

  /// No description provided for @settingsRemoveSubscription.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String settingsRemoveSubscription(String name);

  /// No description provided for @settingsRemoveSubscriptionBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes its {count, plural, =1{1 node} other{{count} nodes}} from this device.'**
  String settingsRemoveSubscriptionBody(int count);

  /// No description provided for @importTitle.
  ///
  /// In en, this message translates to:
  /// **'Import nodes'**
  String get importTitle;

  /// No description provided for @importNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get importNameOptional;

  /// No description provided for @importPasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get importPasteFromClipboard;

  /// No description provided for @importPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get importPaste;

  /// No description provided for @importFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get importFile;

  /// No description provided for @importInProgress.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get importInProgress;

  /// No description provided for @importHint.
  ///
  /// In en, this message translates to:
  /// **'Subscription URL, share links (vless, vmess, trojan, ss, hysteria2, tuic), or a sing-box JSON config.'**
  String get importHint;

  /// No description provided for @noticeNeedNodes.
  ///
  /// In en, this message translates to:
  /// **'Add a node or subscription first'**
  String get noticeNeedNodes;

  /// No description provided for @noticePermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'VPN permission denied'**
  String get noticePermissionDenied;

  /// No description provided for @noticeSwitchFailed.
  ///
  /// In en, this message translates to:
  /// **'Switch failed: {detail}'**
  String noticeSwitchFailed(String detail);

  /// No description provided for @noticeReloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Reload failed: {detail}'**
  String noticeReloadFailed(String detail);

  /// No description provided for @noticeNoUrlToRefresh.
  ///
  /// In en, this message translates to:
  /// **'{name} has no URL to refresh'**
  String noticeNoUrlToRefresh(String name);

  /// No description provided for @noticeSubscriptionUpdated.
  ///
  /// In en, this message translates to:
  /// **'{name}: {count, plural, =1{1 node} other{{count} nodes}}'**
  String noticeSubscriptionUpdated(String name, int count);

  /// No description provided for @noticeNodesImported.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 node imported} other{{count} nodes imported}}'**
  String noticeNodesImported(int count);

  /// No description provided for @noticeNodesImportedSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 node imported} other{{count} nodes imported}}, {skipped} skipped'**
  String noticeNodesImportedSkipped(int count, int skipped);

  /// No description provided for @importedDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get importedDefaultName;

  /// Nothing answered: offline, blocked, or the TLS handshake was dropped. The hint matters because the app's own traffic does not go through the tunnel unless it is aimed at the local inbound.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the subscription. If it is blocked, connect first, then update again.'**
  String get noticeImportUnreachable;

  /// No description provided for @noticeImportHttpStatus.
  ///
  /// In en, this message translates to:
  /// **'The subscription returned HTTP {code}'**
  String noticeImportHttpStatus(int code);

  /// No description provided for @noticeImportUnusable.
  ///
  /// In en, this message translates to:
  /// **'No usable nodes in what came back'**
  String get noticeImportUnusable;

  /// No description provided for @noticeImportBadSource.
  ///
  /// In en, this message translates to:
  /// **'Not a usable subscription or config'**
  String get noticeImportBadSource;

  /// The engine reads local rule-sets when it starts, so a fresh download cannot apply to a running tunnel.
  ///
  /// In en, this message translates to:
  /// **'Rule sets updated — active at the next connect'**
  String get noticeRuleSetsUpdated;

  /// No description provided for @noticeRuleSetsUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update the rule sets; keeping the current lists'**
  String get noticeRuleSetsUpdateFailed;

  /// No description provided for @noticeRuleSetsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This platform has no local rule sets to update'**
  String get noticeRuleSetsUnavailable;

  /// No description provided for @platformUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The {platform} runtime is not implemented yet. Config rendering and node management still work.'**
  String platformUnsupported(String platform);

  /// No description provided for @nodesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{nodes} endpoints · {sources} sources'**
  String nodesSubtitle(int nodes, int sources);

  /// No description provided for @nodesUpdatedAgo.
  ///
  /// In en, this message translates to:
  /// **'updated {ago}'**
  String nodesUpdatedAgo(String ago);

  /// No description provided for @nodesDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days} days left'**
  String nodesDaysLeft(int days);

  /// No description provided for @nodesExpired.
  ///
  /// In en, this message translates to:
  /// **'expired'**
  String get nodesExpired;

  /// No description provided for @agoJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get agoJustNow;

  /// No description provided for @agoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String agoMinutes(int minutes);

  /// No description provided for @agoHours.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String agoHours(int hours);

  /// No description provided for @agoDays.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String agoDays(int days);

  /// No description provided for @latencyFail.
  ///
  /// In en, this message translates to:
  /// **'fail'**
  String get latencyFail;

  /// No description provided for @latencyUnknown.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get latencyUnknown;

  /// No description provided for @logsNewestLast.
  ///
  /// In en, this message translates to:
  /// **'newest last'**
  String get logsNewestLast;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return L10nEn();
    case 'zh':
      return L10nZh();
  }

  throw FlutterError(
      'L10n.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
