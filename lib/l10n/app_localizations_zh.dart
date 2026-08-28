// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class L10nZh extends L10n {
  L10nZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'SingBox 客户端';

  @override
  String get appShortName => 'SingBox';

  @override
  String get actionCancel => '取消';

  @override
  String get actionSave => '保存';

  @override
  String get actionCopy => '复制';

  @override
  String get actionRemove => '删除';

  @override
  String get actionImport => '导入';

  @override
  String get actionUpdate => '更新';

  @override
  String get actionRefresh => '刷新';

  @override
  String get actionConnect => '连接';

  @override
  String get actionDisconnect => '断开';

  @override
  String get actionTestLatency => '测试延迟';

  @override
  String get navHome => '首页';

  @override
  String get navNodes => '节点';

  @override
  String get navRules => '规则';

  @override
  String get navLogs => '日志';

  @override
  String get navSettings => '设置';

  @override
  String get railOverview => '概览';

  @override
  String get stageConnected => '已连接';

  @override
  String get stageDisconnected => '未连接';

  @override
  String get stageConnecting => '正在连接';

  @override
  String get stageDisconnecting => '正在断开';

  @override
  String get stageAwaitingPermission => '等待授权';

  @override
  String get stageFailed => '连接失败';

  @override
  String get greetingMorning => '早上好';

  @override
  String get greetingAfternoon => '下午好';

  @override
  String get greetingEvening => '晚上好';

  @override
  String get greetingNight => '夜深了';

  @override
  String get homeSubtitle => '连接状态一览';

  @override
  String get homeReadyToConnect => '可以连接';

  @override
  String get homeProtected => '已保护';

  @override
  String homeProtectedFor(String uptime) {
    return '已保护 · $uptime';
  }

  @override
  String get homeCheckTheLogs => '查看日志';

  @override
  String get homeNoNodesYet => '还没有节点';

  @override
  String get homeAddNodes => '添加节点';

  @override
  String get homeImportPrompt => '导入订阅或粘贴分享链接即可开始。';

  @override
  String get homeLiveTraffic => '实时流量';

  @override
  String get homeDownload => '下载';

  @override
  String get homeUpload => '上传';

  @override
  String get homeActiveNode => '当前节点';

  @override
  String get homeNoNodeSelected => '未选择节点';

  @override
  String get homeChangeNode => '更换节点';

  @override
  String get homeSession => '本次会话';

  @override
  String get homeTotals => '累计';

  @override
  String get homeDownloaded => '已下载';

  @override
  String get homeUploaded => '已上传';

  @override
  String get homeConnections => '连接数';

  @override
  String get nodesTitle => '节点';

  @override
  String get nodesSearch => '搜索节点';

  @override
  String get nodesFilterAll => '全部';

  @override
  String get nodesFilterFavorites => '收藏';

  @override
  String get nodesFilterFast => '低延迟';

  @override
  String get nodesGroupManual => '手动添加';

  @override
  String get nodesNoMatches => '没有匹配项';

  @override
  String get nodesNoMatchesBody => '没有节点符合当前的搜索或筛选条件。';

  @override
  String get nodesNothingImported => '还没有导入内容';

  @override
  String get nodesImportBody => '导入订阅链接、粘贴分享链接,或载入 sing-box 配置文件。';

  @override
  String get nodesImportTitle => '导入节点';

  @override
  String get nodesRemoveSource => '删除来源?';

  @override
  String nodesRemoveSourceBody(String name, int count) {
    return '将从本机删除 $name 及其 $count 个节点。';
  }

  @override
  String nodesCountLabel(int count) {
    return '$count 个节点';
  }

  @override
  String get nodesUntested => '未测试';

  @override
  String get nodesUnreachable => '无法连接';

  @override
  String get rulesTitle => '规则';

  @override
  String get rulesHowRouted => '流量如何分流';

  @override
  String get rulesRoutingMode => '路由模式';

  @override
  String get rulesModeGlobal => '全局';

  @override
  String get rulesModeRule => '规则';

  @override
  String get rulesModeDirect => '直连';

  @override
  String get rulesModeGlobalBody => '所有流量都走代理。';

  @override
  String get rulesModeRuleBody => '中国大陆的网站和 IP 直连,其余走代理。';

  @override
  String get rulesModeDirectBody => '不走代理。隧道保持开启,但流量直接出网。';

  @override
  String get rulesActive => '生效中的规则';

  @override
  String get rulesDnsInterception => 'DNS 接管';

  @override
  String get rulesDnsInterceptionBody => '由内置解析器应答查询';

  @override
  String get rulesPrivateAddresses => '私有地址';

  @override
  String get rulesPrivateAddressesBody => '局域网和回环地址保持直连';

  @override
  String get rulesChinaDirect => '大陆直连';

  @override
  String get rulesOnlyInRuleMode => '仅在规则模式下生效';

  @override
  String get rulesAdsAndTrackers => '广告与追踪';

  @override
  String get rulesRejectedViaGeosite => '通过 geosite 拦截';

  @override
  String get rulesNotFiltered => '未过滤';

  @override
  String get rulesStateOff => '已关闭';

  @override
  String get rulesStateOn => '开启';

  @override
  String get rulesChinaDirectBody => 'geosite-cn 与 geoip-cn 绕过代理';

  @override
  String get rulesSetsNote => '规则集在首次使用时从 sing-geosite 镜像下载,每周自动更新。';

  @override
  String get logsTitle => '日志';

  @override
  String get logsFollowing => '自动跟随';

  @override
  String get logsPaused => '已暂停';

  @override
  String get logsCopyAll => '复制全部';

  @override
  String get logsCopied => '日志已复制';

  @override
  String get logsNoneYet => '还没有日志';

  @override
  String get logsNothingLogged => '暂无日志输出';

  @override
  String get logsConnectToSee => '连接隧道后即可看到 sing-box 的运行输出。';

  @override
  String logsEntryCount(int count) {
    return '$count 条';
  }

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSubtitle => '调整你的连接';

  @override
  String get settingsSubscriptions => '订阅';

  @override
  String get settingsAddSubscription => '添加订阅或节点';

  @override
  String get settingsAddSubscriptionBody => '订阅链接、分享链接,或 sing-box 配置';

  @override
  String get settingsProxy => '代理';

  @override
  String get settingsTunStack => 'TUN 网络栈';

  @override
  String get settingsSystemProxy => '系统 HTTP 代理';

  @override
  String get settingsSystemProxyBody => '同时在隧道上开放代理端口,供忽略 VPN 的应用使用';

  @override
  String get settingsStrictRoute => '严格路由';

  @override
  String get settingsStrictRouteBody => '阻止试图绕过隧道的流量';

  @override
  String get settingsNetwork => '网络';

  @override
  String get settingsRemoteDns => '远程 DNS';

  @override
  String get settingsDirectDns => '直连 DNS';

  @override
  String get settingsDnsHint =>
      '支持 https://、tls://、quic://、h3://、udp:// 和 tcp:// 形式的地址。';

  @override
  String get settingsFakeIp => 'FakeIP';

  @override
  String get settingsFakeIpBody => '解析更快,但会影响需要真实地址的应用';

  @override
  String get settingsIpv6 => 'IPv6';

  @override
  String get settingsIpv4Only => '仅 IPv4';

  @override
  String get settingsPreferIpv4 => '优先 IPv4,允许 IPv6';

  @override
  String get settingsMtu => 'MTU';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get settingsDiagnostics => '诊断';

  @override
  String get settingsRuntimeLogs => '运行日志';

  @override
  String settingsEntriesBuffered(int count) {
    return '已缓存 $count 条';
  }

  @override
  String get settingsGeneratedConfig => '生成的配置';

  @override
  String get settingsGeneratedConfigBody => '查看实际发送给 sing-box 的内容';

  @override
  String get settingsConfigCopied => '配置已复制';

  @override
  String get settingsContainsCredentials => '包含凭据,请勿分享。';

  @override
  String get settingsLogLevel => '日志级别';

  @override
  String get settingsAbout => '关于';

  @override
  String get settingsAppVersion => '应用版本';

  @override
  String get settingsCore => 'sing-box 内核';

  @override
  String get settingsChecking => '正在获取…';

  @override
  String settingsRemoveSubscription(String name) {
    return '删除 $name?';
  }

  @override
  String settingsRemoveSubscriptionBody(int count) {
    return '将从本机删除它的 $count 个节点。';
  }

  @override
  String get importTitle => '导入节点';

  @override
  String get importNameOptional => '名称(可选)';

  @override
  String get importPasteFromClipboard => '从剪贴板粘贴';

  @override
  String get importPaste => '粘贴';

  @override
  String get importFile => '文件';

  @override
  String get importInProgress => '正在导入…';

  @override
  String get importHint =>
      '订阅链接、分享链接(vless、vmess、trojan、ss、hysteria2、tuic),或 sing-box JSON 配置。';

  @override
  String get noticeNeedNodes => '请先添加节点或订阅';

  @override
  String get noticePermissionDenied => 'VPN 授权被拒绝';

  @override
  String noticeSwitchFailed(String detail) {
    return '切换失败:$detail';
  }

  @override
  String noticeReloadFailed(String detail) {
    return '重载失败:$detail';
  }

  @override
  String noticeNoUrlToRefresh(String name) {
    return '$name 没有可刷新的链接';
  }

  @override
  String noticeSubscriptionUpdated(String name, int count) {
    return '$name:$count 个节点';
  }

  @override
  String noticeNodesImported(int count) {
    return '已导入 $count 个节点';
  }

  @override
  String noticeNodesImportedSkipped(int count, int skipped) {
    return '已导入 $count 个节点,跳过 $skipped 个';
  }

  @override
  String get importedDefaultName => '已导入';

  @override
  String platformUnsupported(String platform) {
    return '$platform 平台的运行时尚未实现。配置生成和节点管理仍然可用。';
  }

  @override
  String nodesSubtitle(int nodes, int sources) {
    return '$nodes 个节点 · $sources 个来源';
  }

  @override
  String nodesUpdatedAgo(String ago) {
    return '$ago更新';
  }

  @override
  String nodesDaysLeft(int days) {
    return '剩余 $days 天';
  }

  @override
  String get nodesExpired => '已过期';

  @override
  String get agoJustNow => '刚刚';

  @override
  String agoMinutes(int minutes) {
    return '$minutes 分钟前';
  }

  @override
  String agoHours(int hours) {
    return '$hours 小时前';
  }

  @override
  String agoDays(int days) {
    return '$days 天前';
  }

  @override
  String get latencyFail => '失败';

  @override
  String get latencyUnknown => '—';

  @override
  String get logsNewestLast => '最新在下';
}
