# Synapse V4 视觉改版方案

设计源：[`synapse-v4.png`](synapse-v4.png)（Network Control Console / Synapse V4）。
本文是把这套设计落到现有 Flutter 代码的实施方案，不是设计稿的复述。

现状基线：`lib/ui/` 8 个文件约 3400 行，token 集中在 `lib/ui/theme.dart`
（`AppPalette` theme extension + `Gap` + `AppFonts`），双主题与中英文已接通，
73 个测试通过。本次改版只动表现层，不动 `lib/state/`、`lib/data/`、`lib/platform/`。

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
class Radius_ {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}
```

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
2. 新增 `Radius_`、`Motion`、`glow()`
3. `Gap.xl` 20→24，补 `x3/x4/x5`
4. 接入 JetBrains Mono（下载字体 → `pubspec.yaml` → `AppFonts.mono`）
5. 更新对比度测试，把 `sky` 纳入断言

P0 完成时整个应用配色即刻变化，但布局不动 —— 这是一个可独立验证的检查点。

**P1 — 共享组件**（`lib/ui/widgets.dart`，562 行）
`Panel`（发光描边）、`SectionLabel`（大写字距）、`StatusPill`、`SegmentedChoice`、
`SettingRow`、`EmptyState`、`Sparkline`（渐变 + sky 第二色）。
所有 `circular()` 字面量换成 `Radius_`，所有时长换成 `Motion`。

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

---

## 5. 待定项

1. **JetBrains Mono 授权与体积** —— OFL 许可，可商用。完整 TTF 约 200KB，
   建议只打包 Regular + Medium 两个字重。
2. **首屏在窄屏的取舍** —— 设计稿是桌面仪表盘。移动端是保留现有连接拨盘
   （用户点击目标大、单手可达），还是压缩版仪表盘？倾向保留拨盘。
3. **发光在亮色主题的强度** —— 需要真机对比后定 `intensity` 系数，
   `0.35` 只是起始值。
