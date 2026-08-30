# Synapse V4 视觉改版方案

设计源：[`synapse-v4.png`](synapse-v4.png)（Network Control Console / Synapse V4）。
本文是把这套设计落到现有 Flutter 代码的实施方案，不是设计稿的复述。

现状基线：`lib/ui/` 8 个文件约 3400 行，token 集中在 `lib/ui/theme.dart`
（`AppPalette` theme extension + `Gap` + `AppFonts`），双主题与中英文已接通，
73 个测试通过。本次改版只动表现层，不动 `lib/state/`、`lib/data/`、`lib/platform/`。
（例外都来自后面两轮真机 —— 设备上的报错逼出了 `lib/data/` 的 DNS 配置修复和规则集
内置，以及 `lib/platform/` 的一个目录查询。那些不属于改版，只是搭同一趟车。）

---

## 1. 设计 token 映射

设计稿右下角给出了完整 token 表。逐项对到代码：

### 1.1 颜色

设计稿的 7 个色值是**暗色**定义。项目有亮色主题，所以每个语义色需要一组暗/亮值。
下表「对比度」是前景色对该主题 `surface` 的 WCAG 比值，我已逐个算过。

| 语义 | 暗色 | 对比度 | 亮色 | 对比度 | 说明 |
|---|---|---|---|---|---|
| `bg` | `#000E13` | — | `#F4F6F8` | — | 页面底色，比 surface 更深一档 |
| `surface` | `#141B21` | — | `#FFFFFF` | — | 面板填充 |
| `surface2` | `#1F2430` | — | `#F5F6F9` | — | 面板内嵌（代码块、输入框） |
| `surface3` | `#2A3140` | — | `#E9EBEF` | — | 抬升层（chip、snackbar） |
| `border` | `#1AFFFFFF` | — | `#14000000` | — | 常规描边 |
| `borderStrong` | `#2EFFFFFF` | — | `#29000000` | — | 强调描边 |
| `text` | `#E2E6F1` | 13.9 | `#0B1220` | 18.7 | 正文 |
| `muted` | `#8A93A6` | 5.6 | `#5C6779` | 5.7 | 次级文字，过 4.5:1 |
| `faint` | `#6E7889` | 3.9 | `#7C8698` | 3.7 | 三级文字/禁用态 |
| `violet` | `#6C40FF` | 白字 5.5 | `#5B34E8` | 白字 5.9 | **填充**色：按钮、选中态 |
| `violetSoft` | `#B9A9FF` | 8.4 | `#4C28D6` | 8.1 | **前景**色：图标、链接 |
| `mint` | `#22E1A6` | 10.3 | `#0B7F58` | 5.0 | 已连接/健康 |
| `sky` | `#7FD2FF` | 10.4 | `#116E96` | 5.7 | **新增**：数据/图表第二色 |
| `amber` | `#F4B860` | 9.8 | `#9A6300` | 5.1 | 警告 |
| `danger` | `#F07979` | 6.4 | `#C5323C` | 5.4 | 错误 |

三点必须说明：

1. **`sky` 是新增语义色。** 设计稿调色板里有 `7FD2FF`，当前 `AppPalette` 没有对应项。
   它在设计中承担图表第二色（上行 vs 下行）和 glow 高光。加字段，不要拿 `mint` 凑。

2. **亮色不是暗色的机械反转。** `mint #22E1A6` 直接放到白底只有 **1.70:1**，
   `sky #7FD2FF` 只有 **1.67:1** —— 两者作为前景色在亮色主题下完全不可读。
   所以亮色的 mint/sky 是重新取的深色值。这条约束现有测试
   （`localization_theme_test.dart` 的 `light mode is not a mechanical inversion of dark`）
   已经在守，改 token 时它会继续守着。

3. **`violet` 是填充色，不做前景。** `#6C40FF` 在 surface 上只有约 2.4:1，
   但作为按钮底色配白字是 5.5:1，合格。前景一律用 `violetSoft`。

### 1.2 字体

| 角色 | 设计稿 | 当前代码 | 动作 |
|---|---|---|---|
| Display | Space Grotesk 700 / `-0.03em` / 大写 | 已内置，600 字重，未强制大写 | 调字重与字距 |
| Body | Inter 400 / 500 / 行高 1.4 | 已内置 | 行高从 1.45 调到 1.4 |
| Data / Code | **JetBrains Mono** 400 / 500 | `'monospace'`（平台字体） | **需新增字体文件** |

`monoStyle()` 有 15 处调用点，全部会因为换成 JetBrains Mono 而改变字形宽度 ——
延迟数字、速率、端口这些等宽对齐的地方要回归看一遍。

JetBrains Mono 和另两个字体一样**不含中文字形**，`AppFonts.cjkFallback`
的回退链要继续挂在 mono 样式上（当前已挂，别在重写时丢掉）。

### 1.3 间距

设计稿：8px 网格，刻度 `4 8 12 16 24 32 48 64 96 128`。

当前 `Gap`：`4 8 12 16 20 32`。**`xl = 20` 不在网格上**，且缺 48 以上的大间距
（设计稿的英雄区留白需要）。改成：

```dart
class Gap {
  static const xs = 4.0;    // 保持
  static const sm = 8.0;    // 保持
  static const md = 12.0;   // 保持
  static const lg = 16.0;   // 保持
  static const xl = 24.0;   // 20 → 24（对齐网格）
  static const xxl = 32.0;  // 保持
  static const x3 = 48.0;   // 新增
  static const x4 = 64.0;   // 新增
  static const x5 = 96.0;   // 新增
}
```

`xl` 从 20 变 24 会让所有用到它的地方（页面边距、卡片内距）松一档，这是预期变化。

### 1.4 圆角

设计稿：`4 8 12 16 24`，五档。

当前代码有 **22 处** `circular()` 字面量，散落 9 个不同值（`2 8 9 10 11 12 14 15 18 22`）。
这是需要收敛的技术债。新增：

```dart
class AppRadius {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}
```

命名用 `AppRadius` 而不是 `Radius_`：`Radius` 被 `dart:ui` 占了，必须换名，
但尾下划线过不了 `camel_case_types` lint（P0 的验收门槛是 analyze 干净）。
`App` 前缀也和已有的 `AppPalette` / `AppFonts` 一致。

映射：`2→4`、`8/9/10/11→8`、`12→12`、`14/15→16`、`18→16`、`22→24`。

### 1.5 发光与阴影

设计稿有独立的 GLOW / SHADOW 展示块 —— 这是这套设计的**视觉签名**，
现在代码里只有一处很淡的 `boxShadow`（连接拨盘）。需要一组可复用的发光定义：

```dart
/// 强调元素的外发光。alpha 分层，不是单层模糊。
static List<BoxShadow> glow(Color c, {double intensity = 1}) => [
  BoxShadow(color: c.withValues(alpha: .28 * intensity), blurRadius: 24, spreadRadius: -4),
  BoxShadow(color: c.withValues(alpha: .12 * intensity), blurRadius: 48, spreadRadius: 2),
];
```

亮色主题下发光要显著减弱（`intensity` 约 0.35），否则白底上会糊成一团脏色。

### 1.6 动效

设计稿：默认曲线 `cubic-bezier(0.22, 1, 0.36, 1)`（即 `Curves.easeOutQuint` 近似），
时长 `Instant 0 / Fast 150 / Normal 300 / Slow 500 / Slower 800`。

当前代码 5 处时长字面量：`160 / 180 / 320 / 1600`。收敛到：

```dart
class Motion {
  static const curve = Cubic(0.22, 1, 0.36, 1);
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 500);
  static const slower = Duration(milliseconds: 800);
}
```

映射：`160→fast`、`180→fast`、`320→normal`、`1600→` 呼吸动画保持自有时长（不属这套刻度）。

---

## 2. 数据缺口（重要）

设计稿展示了若干我们**当前拿不到真实数据**的指标。照抄会变成假数据，必须先定处理方式。

| 设计稿元素 | 数据现状 | 建议 |
|---|---|---|
| `+12.6% vs last 1h` 环比 | `ProxyTraffic` 只有瞬时值与累计值，无历史序列 | 加一个滚动历史 buffer（约 1h / 60 样本），才能算环比 |
| `PACKET LOSS 0.12%` | sing-box Clash API 不提供丢包率 | **删掉这张卡**，换成「内存占用」（`ProxyTraffic.memory` 已有） |
| 每个节点一条吞吐 sparkline | 流量是全局的，无 per-node 统计 | 改为**延迟历史**曲线（测速时可积累），或先留空 |
| 每个节点的 `42.8 MB/s` 速率 | 同上，无 per-node 数据 | 只显示延迟，去掉速率列 |
| `ACTIVE NODES 12 / 24` | 「活跃」在我们的模型里没有定义（只有选中/未选中） | 改为「可用 / 总数」，以测速结果为准 |
| `LATENCY 24ms -3ms` 环形表 | 有当前延迟，无上次对比 | 保留环形表，去掉 `-3ms`，或存一次上次测速值 |

`ProxyTraffic` 现有字段：`uplink` `downlink` `uplinkTotal` `downlinkTotal`
`connectionsIn` `connectionsOut` `memory`。CONNECTIONS 卡和 mini 柱图可以用真实数据。

---

## 3. 结构差异

| 维度 | 设计稿 | 当前实现 | 决定 |
|---|---|---|---|
| 导航项 | 4（DASHBOARD / NODES / RULES / CONFIG） | 5（首页 / 节点 / 规则 / 日志 / 设置） | **保持 5 项**。日志是排障入口，不能藏进设置 |
| 侧栏 | 桌面固定侧栏 + 英雄字标 | 已有 218px 侧栏 | 加字标与状态胶囊，宽度调到 240 |
| 首屏 | 桌面仪表盘（大图表 + 4 张指标卡） | 移动优先（连接拨盘为主） | 分岔：宽屏走仪表盘，窄屏保留拨盘 |
| CONFIG 页 | 独立页，带 YAML 编辑器 | 设置页里的只读预览弹层 | **不做编辑器**。改成语法高亮的只读视图 |
| 背景 | 流体/粒子艺术图 | 纯色 | 用 `CustomPainter` 画极轻的网格 + 渐晕，不引入位图资源 |

背景艺术图这一项要说清楚：设计稿的流体渲染图是位图素材，我不打算引入
——它会给每个页面加几百 KB，且在小屏上会和内容抢注意力。用程序化绘制的
低对比度网格替代，保留「控制台」观感，成本接近零。

---

## 4. 实施阶段

每阶段结束都要 `flutter analyze` 干净 + 73 个既有测试通过。

**P0 — token 层**（`lib/ui/theme.dart`，约 390 行，改动最集中）
1. `AppPalette` 换色值，新增 `sky` 字段（含 `copyWith` / `lerp`）
2. 新增 `AppRadius`、`Motion`、`glow()`
3. `Gap.xl` 20→24，补 `x3/x4/x5`
4. 接入 JetBrains Mono（下载字体 → `pubspec.yaml` → `AppFonts.mono`）
5. 更新对比度测试，把 `sky` 纳入断言

P0 完成时整个应用配色即刻变化，但布局不动 —— 这是一个可独立验证的检查点。

**P1 — 共享组件**（`lib/ui/widgets.dart`，562 行）
`Panel`（发光描边）、`SectionLabel`（大写字距）、`StatusPill`、`SegmentedChoice`、
`SettingRow`、`EmptyState`、`Sparkline`（渐变 + sky 第二色）。
所有 `circular()` 字面量换成 `AppRadius`，所有时长换成 `Motion`。

**P2 — 页面**（按改动量排序）
- `home_page.dart`（614 行）：宽屏仪表盘布局，指标卡，环形延迟表
- `settings_page.dart`（519 行）：分组重排，CONFIG 只读高亮视图
- `nodes_page.dart`（425 行）：节点行改版（区域码 + 协议 + 延迟），去掉无数据的速率列
- `rules_page.dart`（175 行）：规则行加类型徽章（DIRECT / PROXY / BLOCK）
- `import_sheet.dart`（171 行）、`logs_page.dart`（156 行）：跟随 token
- `main.dart`（341 行）：侧栏字标、状态胶囊、宽度 240

**P3 — 新组件**
`GlowCard`、`MetricCard`、`RingGauge`（环形延迟表）、`MiniBars`（连接数柱图）、
`ConsoleBackground`（程序化网格背景）。

**P4 — 验证**
双主题 × 中英文 × 移动/桌面 四个维度的截图回归；对比度测试扩展到新增色；
真机安装确认中文字形在新 mono 字体下正常回退。

### P4 执行结果

P0–P3 已完成。P4 三项中两项以自动化测试落地，第三项受硬件限制未能完成。

**四维回归** —— `test/localization_theme_test.dart` 的 `render matrix` 组，
两主题 × 两语言 × 移动(420×900)/桌面(1280×900) 生成 8 个用例，每个都带中文节点名
和一条日志（空图表会掩盖布局问题），逐个切换五个 tab 断言无异常。不是截图对比，
但能抓住只在某一个角落出现的布局崩溃 —— 单独固定三个维度的测试会漏掉这类问题。

**对比度** —— 扩展时发现两个真实缺陷，都是算出比值而非目测才暴露的：
1. `faint` 在两套配色下都低于 4.5:1（深色 3.90、浅色 3.67），而它实际承载 10px
   正文内容（日志时间戳、节点地址、配置预览标点、版本号、输入提示），不只是装饰。
   两个色值都已提亮/加深，现为深色 5.07:1、浅色 5.40:1。`surface3` 上仍不达标，
   但那层只画一个禁用图标，已在字段注释里记录为例外。
2. 徽章文字画在自身颜色 10% 填充上时，浅色模式跌到 4.37:1。同色调填充在两套主题里
   把对比度推向相反方向 —— 深色底上填充被提亮、远离文字，白底上被拉向文字，
   所以浅色模式是约束方。扫描后取 .07（深色最差 4.63、浅色 4.56），
   收进 `tintFill()`，注释指向会先失败的那条断言。

**CJK 回退** —— 先做成静态断言（真机确认见「真机一轮」），过程中查出第三个缺陷：
组件主题上的 `textStyle` 不与 `textTheme` 合并，按钮会把它作为新的
`DefaultTextStyle` 装上、替换环境样式，所以裸写的 `TextStyle` 会同时丢掉 Inter
和回退链 —— 中文按钮文字（含首屏「连接」）本会渲染成豆腐块。
六处（三种按钮、snackbar、输入提示、导航栏标签）统一走 `_componentStyle()`，
`component themes carry the fallback too` 守住。

**当时未完成** —— 真机安装确认。release APK 已能打出（75.0MB，四个字体文件都在包内），
但当时本机没有连接 adb 设备，`flutter devices` 只列出 Linux 桌面目标，装机那一步做不了。
静态断言只能证明每个样式都带了回退链，不能证明设备上的字体实际命中。这一条后来补上了
（见「真机一轮」）；`intensity` 系数（§5.3）仍等真机对比。

打包环境（踩过的坑，记下来省得重找）：
- 系统 `java` 是 **JRE**（`jre-openjdk`，26.0.2），没有 `javac`，Gradle 会以
  `Toolchain installation ... does not provide the required capabilities: [JAVA_COMPILER]`
  失败。可用的完整 JDK 在 `~/.gradle/jdks/eclipse_adoptium-17-amd64-linux.2`
  （Temurin 17.0.20），用 `JAVA_HOME` 指过去即可。
- 必须显式给 `ANDROID_HOME=~/Android/sdk`（`local.properties` 里的 `sdk.dir` 是小写
  `sdk`），否则报 `No Android SDK found`。
- **必须带 `--target-platform android-arm64`**。`abiFilters` 只约束 AGP 自己打包的库，
  Flutter 引擎从 Maven 来、不受约束，所以不带这个 flag 会多出 armeabi-v7a 和 x86_64
  的 `libflutter.so`/`libapp.so`（包从 75MB 涨到 109.6MB），而 `libbox.so` 只有 arm64
  —— 这两个 ABI 装上去会在启动 VPN 时崩。带 flag 后残留的两个 ABI 目录里只剩一个
  10KB 的 androidx `libdatastore_shared_counter.so` 桩，无引擎、无 libbox。
- `libbox.aar` 已在 checkout 里（arm64，17.6MB，被 gitignore 忽略）。
  `scripts/build-libbox.sh` 仍硬要求 JDK 17，但重建 libbox 不在打包路径上。

### 细化轮

P4 之后又走了两轮对照设计图的收口，都是算出来或量出来才发现的问题：

**发光穿透半透明填充** —— `BoxShadow` 画在容器填充的**后面**，所以半透明填充会
让光晕从自身透出来。首屏拨盘的 118px 圆盘和字标的 30px 徽标都中了这一条：
拨盘上的细节行实测只有 1.97:1，而当时的对比度测试把填充建模成一次扁平混合、
读到 4.72 并通过。改法是用 `Color.alphaBlend(accent@x, surface)` 预合成成不透明
填充，光晕就留在形状外面 —— 拨盘 1.97–3.58 升到深色 8.57/4.71、浅色 5.04/5.05。
连带的规矩：任何把 tint 建模成扁平混合的对比度测试，都得先确认那个形状底下没有阴影。

**滚动与布局** —— 设置页滚到底会欠滚，因为 `SliverList` 只测量已构建的子节点，
第一次读到的 `maxScrollExtent` 偏小；改成循环直到 extent 不再增长。
日志页原本写死 `SizedBox(height: 460)`，在桌面窗口太短、在手机上面板下方留约
200px 空白；换成 `PageFrame.fill`，用 `SliverFillRemaining` 把表头之外的剩余视口
交给最后一个子节点（`hasScrollBody` 必须保持默认的 `true`：`false` 会去测子节点的
固有高度，而里面有 `ListView`，viewport 拒绝报告固有尺寸）。空状态是一张短卡片，
所以按 `fill: logs.isNotEmpty` 传，不把它拉满。

**金标截图** —— `test/visual_snapshot_test.dart`，11 张 PNG，`VISUAL_SNAPSHOTS=1`
时才跑（默认跳过，所以 CI 不会因字体渲染差异变红）。逐像素比对，覆盖首屏两种状态
× 深浅 × 中英 × 移动/桌面，加上 rules 和 logs 两页 —— 这两页此前没有任何像素覆盖。
日志时钟通过 `FakeProxyController.emitLog` 注入固定时间以保证确定性。

**又两条对比度断言** —— 拨盘在自身 9% 圆盘上的三种状态色，以及规则行图标
（`violetSoft` 画在 `violet@13%` 的图标块上，实测 7.63/6.63，图标标准是 3:1）。
后者视觉上很宽裕，加断言是因为它跨两个 token 加一个 alpha，而既有的徽章测试
结构上看不到它 —— 那个测试只会把一个颜色放在它自己的 tint 上。

门禁：`flutter analyze` 干净，123 个测试全通过（原 73 → 123），
另有 11 个金标用例默认跳过。

### 真机一轮

用户把 release APK 侧载到手机上跑了一次，截图带回三件事 —— 一条确认、两个缺陷。
两个缺陷互不相干（一个引擎、一个 UI），分开修。

**确认：CJK 在设备上真的命中。** 截图里「夜深了」「连接状态一览」「连接失败」
「实时流量」「下载」「上传」和五个导航标签（首页/节点/规则/日志/设置）全部正常出字，
没有豆腐块 —— P4 只能静态断言的那一条，现在有实拍证据。

**缺陷一：sing-box 起不来。** 三个远程 rule-set 全部下载失败，报
`lookup raw.githubusercontent.com: read udp [::1]:59673->[::1]:53: connection refused`。
链路一路查到底：`route.default_domain_resolver` 指向 `dns-local`（`type: local`）→
libbox 去问 `PlatformInterface.localDNSTransport()` → 我们的 `BoxPlatform.kt` 返回
`null` → libbox 退回 Go 自己的解析器读 `/etc/resolv.conf` → Android 上这个文件没有
可用 nameserver → Go 默认打回环 → 每一次启动期查询都死在 `[::1]:53`。而远程
rule-set 初始化失败在 sing-box 里是**致命**的（没有 per-rule-set 的 optional 开关），
所以整个 start 被它带崩。

改法是把依赖平台的 `local` 换成一台纯 UDP 的 `dns-bootstrap`：`server` 只填 IP 字面量
（用户的 `directDnsHost` 本身是 IP 就复用它，否则退到 `223.5.5.5` —— AliDNS 墙内外
都通），这样它自己不需要被解析，且 DNS server 默认直连、不需要隧道先起来。
`dns-direct`（主机名形式）和 `route.default_domain_resolver` 两个消费方都指向它。
注意 **不能**给它加 `'detour': direct`：空的 direct outbound 会被
`common/dialer/detour.go` 在启动时判为「detour to an empty direct outbound makes no
sense」直接拒绝。真正让它在隧道外走通的是 `autoDetectInterfaceControl`
（`BoxPlatform.kt:103`），而不是 detour。

顺带把 `_remoteRuleSet` 的 `download_detour` 从 `direct` 改成 `proxy`：这几个是 CN
rule-set，需要它们的用户恰恰就是直连不到 raw.githubusercontent.com 的用户，`direct`
对目标受众必然失败。出口节点自己的地址由上面那台 bootstrap 解析，所以下载这一步
不依赖它正在下载的东西。

两处都是纯配置改动，`BoxPlatform.kt` 没动 —— 认真实现 `localDNSTransport()` 是另一条
更大的路。**离线启动仍然会失败**，这是 sing-box 的设计（远程 rule-set 初始化致命），
要修得把 `.srs` 打进包里，这一轮没做（下一轮做了，见「规则集内置」）。

**缺陷二：长引擎错误糊满首屏。** 那条几百字符的错误无界渲染，压过连接拨盘、
「连接」按钮和实时流量卡片，身后还透出一份正确截断的副本。第一个假设（`notice_text.dart`
或拨盘的固定高度盒子）读代码就被排除了 —— `_stageDetail` 两个渲染点早就带
`maxLines: 2` + ellipsis。真凶是 `lib/main.dart` 里 `SnackBar(content: Text(...))`
根本没设上限，而 `SnackBarBehavior.floating` 会无限向上长；「两份重叠」则是那条
`backgroundColor` 用了 18% alpha 的半透明 danger，底下的拨盘直接读穿上来。
改成 `maxLines: 3` + ellipsis（全文在日志页，这里是警报不是报告），背景用
`Color.alphaBlend` 预合成成不透明。回归测试用截图里那条一字不改的设备原文喂进去 ——
其它测试全都只喂短消息，这正是它能溜出去的原因；把 clamp 撤掉能让新测试红，装回去变绿。

**金标的时钟接缝。** 上面的改动一个像素都没碰，却有六张金标变红
（首屏三张 + 浅色 + 中文 + nodes）。没有盲目重录：读
`test/failures/*_isolatedDiff.png` 看到首屏的差异只是「evening」一个词、nodes 的差异
是「N 天前」那一段 —— 根因是 UI 里五处 `DateTime.now()`，隔了一夜问候语从晚上翻成
早上、订阅又老了一天。加 `lib/ui/clock.dart` 一个 `clockNow` 接缝把这五处收口，
截图 harness 里 `pinClock(DateTime(2026, 8, 29, 21, 30))`（选傍晚，命中设计评审时看的
那条问候语分支）。`--update-goldens` 跑完 `git status test/snapshots/` 一个字节没变 ——
金标本来就是对的，只是需要把时钟钉住。

门禁：`flutter analyze` 干净，127 个测试全通过（123 → 127：三个 bootstrap DNS 配置
测试 + 一个 snackbar 截断回归），金标 11/11 在钉住的时钟下通过。

### 应用图标

之前一直是 Flutter 模板那个默认图标（`mipmap-xxxhdpi/ic_launcher.png` 与模板文件
md5 完全一致），所以没有「现有的」可用，重画了一个。

标记就是首屏那个连接拨盘：缺口开在正下方的 300° 仪表环 + 从环起点填起的薄荷色扇段 +
中心实心的节点。颜色全部取自 `AppPalette.dark`，没有引入新色值 —— 底 `bg`，环
`violetSoft`（守「violet 只做填充，前景用 violetSoft」那条规矩），扇段和节点 `mint`，
再加一层 22% 的 violet 径向光晕，和应用自己在拨盘后面画的那层同一个做法。

交付四层：
- `drawable/ic_launcher_background.xml` + `ic_launcher_foreground.xml` ——
  API 26+ 的自适应图标，矢量。前景几何半径 27.5 + 7 宽描边 = 触及 r=31，落在 66dp
  安全圆（r=33）以内，这是唯一一条会被各家启动器静默裁掉的规则。
- `ic_launcher_monochrome.xml` —— Android 13 主题图标层。启动器只取 alpha，
  所以把双色去掉：薄荷扇段本来就压在环上，拍平之后是隐形的。
- `mipmap-*dpi/ic_launcher.png` 与 `ic_launcher_round.png` 各五档 —— minSdk 是 24，
  Android 7.x 还吃这套。pre-26 系统不替你切形状，所以这两份 PNG 自带底板
  （圆角方 / 整圆），而自适应那两层把形状交给系统遮罩。
- 母版 `docs/design/icon/ic_launcher.svg`、`ic_launcher_round.svg` +
  `scripts/build-icons.sh`（rsvg-convert 出图，不进构建流程，改完 SVG 要重跑并提交 PNG）。

`test/android_resources_test.dart` 直接读打进包的资源而不是复述它们：图标色必须**是**
palette 里的色（调色板一改，图标漂移就红）、前景对最坏情况底色（光晕正中心那次混合，
不是裸底色）≥ 3:1、几何不越安全圆、两套 PNG 五档都存在且尺寸对（读 IHDR）、
方图和圆图的字节必须不同（否则就是圆孔里塞方板）、两个入口的自适应 XML 三层都在。
反向验过：把环改成 `violet` 会红在「foregrounds take violetSoft」，
把半径推到 31.5 会红在「reaches outside the safe circle」。

APK 里也核过：`aapt2 dump resources` 列出 `mipmap/ic_launcher` 和
`mipmap/ic_launcher_round` 各自的五档 PNG 加 anydpi-v26 的 XML，
`dump xmltree` 确认 manifest 的 `icon`/`roundIcon` 指向这两个、且三层都绑到真实 drawable。

`roundIcon` 只有 API 25 的圆形启动器会问，所以 `ic_launcher_round.svg` 只换了底板
（整圆代替圆角方），标记和配色一字不改；26+ 两个入口都走同一套自适应层，形状归系统。

**没做**：web/windows 那两个 scaffold 目录里的默认图标 —— 那两个平台跑不了这个应用
（libbox 只有 arm64 的 Android 库）。

### 启动闪屏

模板留下的白底（`launch_background.xml` → `@android:color/white`）在一个近黑的应用
前面会闪一下白。改成 `@color/splash_background`，`values/` 是 `AppPalette.light.bg`、
`values-night/` 是 `dark.bg` —— 跟随系统，正好和 `AppThemeMode.system`（默认值）一致。

不止闪屏那一层：`NormalTheme` 的 `windowBackground` 原本是 `?android:colorBackground`,
由父主题决定（`Theme.Light` → 白、`Theme.Black` → 纯黑），而这个窗口在闪屏撤掉、
Flutter 第一帧画出来之间是可见的，之后还一直在 UI 背后。两套 styles 都指到同一个颜色，
所以交接是隐形的，而不只是「差不多黑」。

顺手删了 `drawable-v21/launch_background.xml`：minSdk 是 24，`-v21` 永远命中，
未限定的那份是死文件 —— 留着只会有两份互相漂移的可能。

踩到一个坑：删掉 `-v21` 那份的同一次构建里报
`resource drawable/launch_background not found`，文件明明在。是 AGP 资源合并的增量状态
和「同名文件一个被删、一个被改」对不上，`flutter clean` 后干净通过 —— 不是真的资源错误。

门禁：`flutter analyze` 干净，135 个测试全通过（127 → 135：8 个 Android 资源测试），
金标 11/11。

### 规则集内置

第二次侧载，同一条链路的下一段：错误从 `[::1]:53` 变成
`initialize rule-set[0]: initial rule-set: geosite-cn: Get "https://raw.githubusercontent
.com/…"`。截图在**原因之前**就断了 —— 上一轮的 clamp 正在起作用，全文只在日志页 ——
所以从图上分不清是 DNS 还没通还是可达性问题。

但这一段不需要分清。启动期去 GitHub 拿文件这件事本身就是错的，三条理由各自独立：

1. 远程 rule-set 初始化在 sing-box 里是**致命**的，且没有 per-rule-set 的 optional
   开关。一个 URL 不通，整条隧道起不来。
2. CN 规则集的目标用户，恰恰就是直连不到 raw.githubusercontent.com 的那批人。
3. `download_detour: proxy` 救不了它。rule-set 是在 route 组装期需要的，
   那个 outbound 此刻还不能承载流量 —— 上一轮加这个 detour 时我把它当成了解法，
   它只是把失败原因换了一个。

所以把三个 `.srs` 打进 APK（合计 97KB，在 75.2MB 的包里可以忽略），启动时解到
`filesDir/rule-sets/`，配置改成 `type: local` + `path`。启动期零网络，离线也能起。

**顺带查出一个与网络无关的缺陷。** `geoip-cn` 的 URL 指向 `SagerNet/sing-geosite`，
而 geoip 规则集在 `SagerNet/sing-geoip` —— 前者是 404。curl 实测：
`sing-geosite/rule-set/geoip-cn.srs` → 404，`sing-geoip/rule-set/geoip-cn.srs` → 200。
也就是说 rule-set[1] 在任何网络条件下都必然失败，跟墙没关系。两个仓库的差别现在同时
写在 `_remoteRuleSet` 的注释、抓取脚本的表格和一条断言里。

**目录从哪来。** 没有引 `path_provider`：它当前的 Android 实现会拖进 JNI 绑定和
build hooks（`pub get` 实测多出 16 个包，含 `jni` / `objective_c` / `hooks`），
为一个字符串付这个构建面积不值得。改成在既有的 `singbox/control` channel 上加一个
`dataDir`，返回 `filesDir.absolutePath` —— 正好就是 libbox `SetupOptions.basePath`
那个目录，规则文件和引擎状态同处一地。`configureFlutterEngine` 在 Dart entrypoint
之前执行，所以 `main()` 里 `await` 它是安全的（顺序反了会静默拿到 null）。
桌面没有 host 应答，`prepare()` 返回 null，配置退回 remote —— 那条路径依然脆弱，
但桌面本来也没有引擎。

**代价是新鲜度**：列表只有 APK 那么新。`scripts/fetch-rule-sets.sh` 重取并提交即可；
国家段和广告域名列表变化很慢。脚本会校验 `SRS` 文件头，免得把 404 页面或门户登录页
当成规则集提交进去。这一轮没做应用内更新 —— 那需要一个能优雅失败的下载入口，
关键是它必须不在启动路径上（下一轮做了，见「规则集更新」）。

11 个新测试（`test/rule_sets_test.dart` 8 个 + `config_builder_test.dart` 3 个）。
最要紧的一条是把两个模块对起来：`extractTo` 写 `$dir/$tag.srs`，`ConfigBuilder`
指 `$dir/$tag.srs`，两份 tag 列表各在一边 —— 测试解包一次再逐个 `File.existsSync()`，
tag 漂移就红。另外守着：资源确实是 `SRS` 开头的编译产物而不是 HTML、pubspec 真的
打包了那个目录（漏了就静默退回下载）、尺寸变了要重写而没变的不该每次启动重写
（用 mtime 验，不是内容）、Kotlin 那边确实应答了 Dart 调的那个方法名。
反向验过：`path` 改个扩展名 → 「the config points at the files unpacking creates」红；
geoip 指回 sing-geosite → 「each from its own repository」红。

门禁：`flutter analyze` 干净，146 个测试全通过（135 → 146），金标 11/11。
APK 75.2MB，`unzip -l` 确认三个 `.srs` 都在 `assets/flutter_assets/assets/rule-sets/`，
`.so` 仍只有 arm64 那一组。

### 规则集更新

内置解决了启动，剩下的是新鲜度。这一轮补上更新的一半：手动一个按钮，自动一次连接。
两条约束先说清楚，它们决定了其余所有设计：

1. **下载不能在启动路径上。** 引擎读的是磁盘上的文件；下载失败、超时、离线，
   代价只能是一份旧列表，不能是起不来。所以更新只发生在启动**之后**，
   而且从不被 await。
2. **新列表下次连接生效。** `local` rule-set 是启动时读的。既然如此就不要偷偷
   `reload`（那会掐掉所有活动连接），而是把这句话直接写进提示：
   「规则集已更新，下次连接时生效」。

**下载走哪条路。** 这里有个反直觉的点：连着 VPN 时，应用自己的请求**并不**走隧道。
`BoxPlatform.kt` 里 `addDisallowedApplication(service.packageName)` 把本应用排除在
隧道外（不排除的话订阅抓取会回环进一个还没起来的代理）。也就是说直连不到 GitHub 的
用户，连上之后照样直连不到。解法是配置里无条件加一个环回 `mixed` 入站
（`127.0.0.1:2080`），更新时把 `HttpClient.findProxy` 指向它 —— 这是应用内 HTTP
唯一能从选中节点出去的路径。显式写 `listen: 127.0.0.1`：sing-box 的默认监听地址
会把一个开放代理暴露给整个局域网。

顺带修好一处早就在的谎：`systemProxy` 开着时 tun 的 `platform.http_proxy` 宣告的就是
`127.0.0.1:2080`，而此前**没有任何东西在那个端口上监听**。现在那个承诺是真的，
端口两边都取 `ConfigBuilder.localProxyPort`，有测试盯着它们相等。

**内置和下载会互相覆盖。** 上一轮的 `extractTo` 用「资源长度 == 磁盘文件长度」判断
要不要重写；下载来的列表长度天然不同，于是每次启动都会把新列表覆盖回旧的 —— 提交时
没看出来。现在目录里多一份隐藏清单 `.installed.json`（记 `assets` 长度、时间戳、
`downloaded`），三条规则按顺序判定：文件不在 → 写；**资源**与清单记录的不一致 → 写
（这条保证新版 APK 的列表仍能盖过下载）；否则只在没有下载记录且磁盘文件与资源不符时
写（修复被截断的副本）。`markDownloaded` 只改时间戳和 `downloaded`，不动资源长度 ——
正因为不动，装了新 APK 才认得出自己的新资源。

**什么时候自动跑。** 首次进入 connected 时，每次运行只试一次（连不上就是连不上，
每次连接都静默重试只是在锤上游）。「陈旧」的判定里，内置装机**总是**算陈旧：
它的时间戳是应用首次运行的时间，跟列表本身编译于何时毫无关系 —— 同样的理由，
设置页那一行在内置状态下显示「随应用内置」而不是一个年龄。下载过的按 7 天算。
自动那次完全静默：用户没要求，一份旧列表也不是需要他处理的失败。手动那次两种结果
都报，且失败报的是 `NoticeKind` 而不是更新器的英文原文（它列的是失败的 tag 名，
对用户没有可操作信息，离线/被墙/上游抖动读起来还都一样）。

**写入是原子的。** 先写 `.new` 再 rename，配置指向的那个文件永远不会是半个。
每个 tag 失败只影响它自己，成功的保留新字节，但清单只在全部落地后才盖章 ——
半次运行下次重试，而不是被记成「已是最新」。响应体先过 `SRS` 头 + 长度下限：
HTTP 200 的门户登录页和代理错误页都是有内容的，写进去只会在设备上、启动时、
以一份读不出来的规则集的形式炸掉。另有 8MB 上限，免得一个错 URL 在校验之前
先把手机填满。

24 个新测试（`rule_set_updater_test.dart` 7 + `rule_set_state_test.dart` 10 +
`rule_sets_test.dart` 5 + `config_builder_test.dart` 2，另重录一张金标）。更新器那组
起了一个真的本地 `HttpServer`（没有 mock 框架，也不想引），按上游真实路径提供响应；
重点全在坏响应上：404 后旧文件必须原样在、HTML 页和过短的 body 必须被拒且不落盘、
`.new` 不留残骸。状态那组盯两条不变量：连接时 `viaLocalProxy` 为真、
以及一个永不完成的下载**不能**拖住 `connect()`（挂住更新器，断言 `connect()` 照常返回、
引擎已启动、下载还开着且没人等它）。`findProxy` 在 `dart:io` 里只能写不能读，
所以那个决定抽成了静态的 `proxyDirective`，测试断言它指的端口就是配置监听的端口。

界面上是「路由」组里一行，位置在「代理」和「网络」之间：规则集决定包**去哪**，
比名字怎么解析高一层。相对时间那个 helper 从 `nodes_page` 提到了 `ui/clock.dart` ——
两处在用，而且它必须跟着那个可 pin 的时钟走，否则金标每小时红一次。

门禁：`flutter analyze` 干净，181 个测试全通过（146 → 181），金标 11/11
（`settings_mobile.png` 因为多了一组而重录）。真机未验：这一轮的两条路径
（环回代理出站、连接后自动更新）都要设备才能确认，目前只有单元测试覆盖。

---

### 侧载反馈：订阅、日志、多来源

release APK 装上之后报回来三件事,一条一条。

**1. 更新订阅失败,而且是英文。** 截图里那句
`Subscription fetch failed: HandshakeException: Connection terminated during handshake`
同时出现在订阅行的副标题和 snackbar 上,一个中文界面里。背后是两个缺陷:抓取从来没走
过隧道(跟规则集下载犯的是同一个错,只是那处上一轮刚修完),以及界面显示的就是异常字符串
本身 —— 它还被持久化进了订阅记录。

路径这半:`local_proxy.dart` 把「应用自己的 HTTP 怎么出去」抽成一处,上一轮写在更新器里的
`proxyDirective` 搬了过来。现在订阅抓取和规则集下载共用同一个决定,`addDisallowedApplication`
那个事实也只解释一遍。`AppState` 两条导入路径都传 `viaLocalProxy: isConnected`,
`fetchSubscription` **先隧道后直连**,而且只有 `unreachable` 才值得试第二条路 ——
404 或者一份垃圾 body 是面板自己的回答,再问一遍还是同一句。直连那次会把带 token 的 URL
重新暴露给局域网,这是今天就有的行为,所以顺序上隧道在前。

文案这半:`ImportException` 带一个 `SubscriptionFailure`(`unreachable`、`httpStatus`
+ 状态码、`unusableContent`、`badSource`),`Subscription` 把它持久化成 `last_failure` /
`last_failure_status`,`notice_text.dart` 里一个 `subscriptionFailureText` 喂三个渲染点
(snackbar、节点页分组副标题、设置页那一行)—— 一个来源不可能把自己描述得跟当初那条消息
不一样。旧记录里的英文句子直接丢弃、不迁移,下一次刷新写进一个 kind。分类的边界就是用户
下一步做什么:只有 `unreachable` 提示「先连接再更新」。`copyWith` 在这里不够用 ——
`?? this.x` 会让一个新原因旁边留着上一次的 `404`,所以配了个 `Subscription.failed()`,
两个字段只能一起动。

**2. 日志开头的乱码。** libbox 是按终端写的,行首带 ANSI 转义:
`\x1B[37mDEBUG\x1B[0m[0000] [\x1B[38;5;83m…`。Flutter 不解释它们,于是每个 `\x1B`
渲染成一个豆腐块,还跟着「复制全部」进剪贴板。剥离放在 `ProxyLogEntry` 构造器里 ——
两个生产者都从这里过,测试的 fake 也一样,所以没有第二个入口需要记得处理。`[0000]`
那个运行时长是 libbox 的输出,留着。

**3. 多个订阅怎么切。** 先回答问题:分组按订阅顺序渲染,每个来源的行都在同一个滚动视图里,
所以第二个订阅的第一个节点在第一个订阅最后一行之下 —— 56 个节点就是要滑过 56 行,
而且这 56 个 `_NodeRow` **widget** 每次 build 都要造一遍(`PageFrame` 用的是
`SliverList.list`,element 和布局仍然是懒的,但搜索框每敲一键都会重造一整棵)。补的是一行
来源 chip,只在 `sources.length > 1` 时出现
(单来源的金标因此不动):`null` 是全部、`''` 是手动添加、其余是订阅 id,选中的来源被删掉
会自己回落到全部。筛选 chip 和来源 chip 抽成同一个 `_ChoiceChipCell`,来源名限宽 148
单行省略,长名字撑不开那一行。

顺带两处:`rulesSetsNote` 还在说规则集「首次使用时下载、每周自动更新」,内置那一轮之后
这话是假的,改成「随应用内置,可在设置中更新;新下载的列表在下次连接时生效」。金标的
fixture 也有个一直存在的不一致 —— 5 个节点没有 `subscriptionId`,却又摆着一个订阅,
于是页面渲染出一个空的订阅分组加一个「手动添加」组;来源 chip 一上来就把它暴露了
(它数出两个来源)。fixture 改成节点属于 `sub1`,另加一张两来源的金标。

16 个新测试。`importer_test.dart` 那组起了个真的本地 `HttpServer`(照 `rule_set_updater_test`
的样子):403 报成 `httpStatus` 且带上码、HTML body 是 `unusableContent` 而不是传输失败、
没人监听是 `unreachable` 且消息里不含 query 里的 token;还有一条把 2080 占住只做
accept-then-destroy,断言隧道被试过、直连仍然成功(端口被占则 skip)。
`subscription_state_test.dart` 用一个假 importer 盯持久化的那半:记下来的是原因不是句子、
重启后还在、下一次成功清掉、不是 `ImportException` 的错不算在来源头上,以及
`viaLocalProxy` 跟着连接状态。节点页那组断言两来源出 chip、单来源不出、手动是其中一个来源、
删掉选中的来源会回落。

门禁:`flutter analyze` 干净,198 个测试全通过(181 → 198),金标 12/12
(`nodes_mobile`、`rules_mobile` 重录,新增 `nodes_mobile_two_sources`)。真机未验:
隧道优先的抓取要在设备上对着一个真被墙的面板才能确认,新的中文文案在设备上的渲染也还
没看过 —— 这两件都只有单元测试覆盖。

---

### 分组折叠

来源 chip 解决的是「只看这一个」,折叠解决的是「把这一个收起来」——两件事都留着:chip
是筛选,折叠是让几个来源的表头挨在一起,不用滑过第一个订阅的 56 行才看到第二个。

四条规则,顺序就是踩坑的顺序:

1. **默认展开。** 这个页面最常走的一趟是「进来、点一个节点」,默认折叠会把它变成两次点击。
2. **折叠状态持久化。** 存在 `Storage` 的 `collapsed_sources.v1`(一个 `StringList`),
   `AppState` 开机读进 `_collapsedSources`,`toggleSourceCollapsed()` 写回加 notify。
   放页面 `State` 里也能跑,但那样每次离开标签页回来都要重新折一遍 —— 折叠是用户干的活,
   不该让他重复干。`removeSubscription()` 里顺手把 id 摘掉:id 不复用,留着就是死数据。
3. **搜索期间有匹配的分组临时展开**,选中某个来源 chip 时那个来源也一样,两种情况都不改存储
   状态。判断收在一个闭包里:`expanded(id) = 查询非空 || source == id || !isSourceCollapsed(id)`。
   少了这条,搜出来的东西藏在 chevron 后面,读起来是「没有结果」而不是「被折起来了」。
4. **命中区不能打架。** 表头本来就有刷新和删除两个 `IconButton`,chevron 因此不自己占命中区
   (`Panel` 的 `onTap` 管整行),否则名字那一栏还要再让出一块宽度。手动添加那组的表头是
   `SectionLabel`,只有一行小字高,给它补了 8pt 上下内边距才够点。

`_FoldChevron` 是 `AnimatedRotation(turns: collapsed ? -0.25 : 0, Motion.fast)` 包一个
`Icons.expand_more`:展开朝下、折叠朝右,和常规的展开箭头一致。

7 个新测试(节点页那组):折叠藏行留表头、重启后还折着、搜索能穿透折叠而清空查询后又折回去、
选中 chip 的来源照样显示但存储状态不动、删除按钮的点击不会顺手折叠、手动添加组同样能折、
删掉来源后存储里不留 id。门禁:`analyze` 干净,193 通过 / 13 skip(金标),金标 13/13 ——
`nodes_mobile`、`nodes_mobile_two_sources` 因为多了 chevron 重录,新增
`nodes_mobile_folded`(第一个来源折起来、第二个来源的表头紧跟其后)。

---

### Clash API 加密钥

`external_controller` 原来裸听在 `127.0.0.1:9291`,没有任何认证。在桌面上这还算能接受,
在 Android 上不行:回环地址对机上每个应用都是开放的,谁都能 POST 一下把用户的出口换掉,
或者把连接列表读走 —— 而连接列表就是用户的浏览历史。

没有直接关掉监听,因为 libbox 的流量数字是从 clash 服务器读的,关掉这一项首页的上下行就归零了。
改成留着监听、加一个随机 `secret`:

1. **128 位,`Random.secure()`。** 默认的 `Random` 用时钟播种,而时钟是机上每个应用都读得到的东西,
   猜出来的令牌等于没有令牌。
2. **持久化在 `Storage` 的 `clash_secret.v1`。** 每次启动重新生成也能跑(反正没人拿它做长连接),
   但那样日志和配置预览里的值每次都变,排查问题时对不上。首次启动生成并写回,之后一直读。
3. **`ConfigBuilder.build()` 的 `clashSecret` 是 `required`,没有默认值。** 给它一个空串默认值
   等于把这个洞留在原地等人忘记传 —— 编译期报错比运行期裸监听好。
4. **`previewConfig()` 里换成 `<hidden>`。** 预览是给用户看配置长什么样的,不是发凭据的地方;
   用户会截图。

### 自动选择

`urltest` 组一直在配置里(`ConfigTags.auto`,是 `proxy` 选择器的成员之一),但界面上没有入口,
用户只能手动挑一个节点。加了个「自动」行。

实现上是往已有的「选中节点 id」这一个键里塞一个哨兵值 `AppState.autoSelection = '[auto]'`,
而不是新开一个 `bool autoMode`。理由是这两个状态天然互斥:选了自动就没有选中的节点,
用两个字段存一个互斥的事实,早晚会出现「自动开着但同时又选了香港」这种谁也说不清的状态。
`selectedNode` 在自动模式下返回 null,界面据此把高亮画在自动那一行。
方括号是有意的:节点 id 是时间戳的 36 进制,不可能撞上。

节点为空时不算自动模式(`_nodes.isNotEmpty`)——`urltest` 没有东西可挑,
这时候显示「自动」是在骗人。

### 测速排序与真实代理延迟

两件事一起做,因为按延迟排序的前提是那个延迟值得排。

**排序模式存 `Storage` 的 `node_sort.v1`,不进 `AppSettings`。** `AppSettings` 的每个字段都进配置,
而写 `AppSettings` 要走 `applySettings`,它会重载正在跑的隧道 —— 点一下排序按钮把连接重启一遍,
显然不对。`NodeSort` 存的是 `key` 字符串不是 `index`:以后往枚举中间插一项,`index` 会静默改变
已存的含义。`sortNodes` 用 `indexed` 做稳定排序,否则两个同毫秒的节点会在每次 rebuild 之间换位置。
没有测量值的两种状态排在所有实测节点之后,而且「还没测」排在「测不通」前面 —— 没测是个未知,
测不通是个答案,答案该垫底。

**延迟改成问引擎要,不再只做 TCP 握手。** 一次到服务器地址的握手只能说明那个端口有人应答,
说明不了走这个代理能不能出去 —— 而后者才是用户点测速时想知道的。真实数字只有一个来源:
libbox 的 `CommandClient.urlTest(groupTag)`,引擎会拿测试 URL 真的从每个成员走一遍,
结果随 group 订阅推回来(`CommandClientOptions.addCommand(Libbox.CommandGroup)`,
`writeGroups` 里每个 `OutboundGroupItem` 带 `URLTestDelay`)。

Dart 侧四个决定:

1. **连着才问引擎,没连就退回握手探测。** 没有隧道时无从「穿过隧道」测量,
   握手至少能回答「这个端点还在不在」。`urlTest` 在没有 command client 时抛
   `IllegalStateException`,所以隧道在检查和调用之间消失了也会落到探测分支,不会两头空。
2. **`delay == 0` 是 libbox 的「没有结果」**(没测过,或者上次测失败),Kotlin 和 `ProxyGroup`
   都原样透传,由 Dart 决定它的含义:先当作还没报,超时后再标不可达。把 0 直接当成 0ms
   会让一个测不通的节点排在最前面。
3. **只有 `ConfigBuilder.outboundTag(node)` 能从标签走回节点。** 引擎说的是标签,
   映射不到节点的成员直接跳过 —— `auto` 组自己就是 `proxy` 的成员之一。
4. **超时 10 秒,可注入。** 每个成员都在发真实请求,慢但能用的节点值得等;
   测试注入 50ms 跑「零延迟不算测量」那条,不用真等一轮。

`writeGroups` 里所有东西都要在回调内拷成普通 `Map`:libbox 的迭代器是 Go 内存上的
call-scoped 视图,而且 Flutter 的 channel 也搬不动迭代器。`getURLTestDelay()` 写成显式 getter
调用,不是 Kotlin 属性语法 —— 首字母缩写开头的合成属性名有歧义,显式调用不用赌它合成成什么。

**Kotlin 那一半编得过,但没在真机上跑过。** `emitGroups`、`urlTest`、
`addCommand(Libbox.CommandGroup)`、`writeGroups`、以及方法通道的 `"urlTest"` 分支,
`assembleRelease` 都对着真的 `libbox.aar` 编译过了,所以签名
(`urlTest(String)`、`CommandGroup = 2`、`OutboundGroupItem.getURLTestDelay()`、
`OutboundGroup.getSelected()/getItems()`、`CommandClientOptions.addCommand(int)`)是对的。
没验证的是运行时行为:引擎到底会不会在 `urlTest` 之后把 group 推回来、推回来的
`URLTestDelay` 是不是我们期待的那个量级、断开时抛不抛 `IllegalStateException`——
这些要装到设备上点一次测速才知道,这台机器没有 adb 设备。

### 订阅自动刷新

连上的那一刻顺手刷新过期的远程订阅,和 `_maybeAutoUpdateRuleSets` 并排,理由也一样:
这个应用要翻过去的那道墙,常常也挡着机场面板 —— 隧道起来之前那个 URL 根本拉不动。

1. **阈值 12 小时。** 面板轮换节点是天级别的事,半天足够「歇了一阵回来跟上」,
   又不至于变成轮询。从没拉过的来源(`updatedAt == null`)按定义就是过期。
2. **静默。** 用户点的是连接,不是更新;成功没什么可说,失败记在那个来源自己那行上,
   出问题时他会去那儿看。`refreshSubscription(id, {silent = false})` 把三处提示都收在 `!silent` 后面。
3. **一次开机只试一轮**,而且和规则集用两个独立的标志(`_autoUpdateTried`/`_autoRefreshTried`)——
   合成一个的话,一边的上游挂了会连带另一边永远不再试。
4. **并发靠 `_refreshing` 那个集合挡**,不新加标志。它本来就是转圈动画的在飞集合,
   自动刷新和用户在同一秒点刷新,后来的那个直接返回。

12 个新测试(两组):测速这边 8 个 —— 断开时走探测且不问引擎、握手无应答算不可达、
连接时标签能映射回节点、引擎没提到的成员不动、零延迟不算测量、隧道消失退回探测、
成员全部报到就提前结束、在飞时第二次调用被忽略;自动刷新那边 9 个 —— 过期的会重拉、
从没拉过算过期、几分钟前拉过的不动、只重拉过期的那些、手动来源永远不拉、全程不弹提示、
失败只记在行上、重连不会再拉一次、自动拉的同时用户点一下不会拉两遍。
门禁:`analyze` 干净,242 通过 / 13 skip(金标),金标 13/13 —— 一张都没重录,
这四项都不改渲染出来的东西(排序按钮那一格在金标里本来就是空的图标位)。

---

## 5. 待定项

1. **JetBrains Mono 授权与体积** —— OFL 许可，可商用。完整 TTF 约 200KB，
   建议只打包 Regular + Medium 两个字重。
2. **首屏在窄屏的取舍** —— 设计稿是桌面仪表盘。移动端是保留现有连接拨盘
   （用户点击目标大、单手可达），还是压缩版仪表盘？倾向保留拨盘。
3. **发光在亮色主题的强度** —— 需要真机对比后定 `intensity` 系数，
   `0.35` 只是起始值。
