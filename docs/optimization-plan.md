# SingBox Client 优化评审与迭代计划

> 评审基线：`841f6d6 Fix Windows TUN elevation handoff`
> 评审范围：Android、Linux、Windows 运行时，桌面 Shell，配置与订阅数据流，以及状态和持久化生命周期。
> 文档性质：代码评审与后续计划；实施进度会随已落地功能同步更新。

## 实施进度

评审后的结构重构已落地，计划中的以下项已在 `ed9cce5` 之后完成：

- **运行时与持久化串行、状态拆分**：`lib/state` 按关注点拆出 `app_state_config`、`app_state_connection`、
  `app_state_import`、`app_state_latency`、`app_state_notice`、`app_state_rules`、`app_state_runtime`，
  取代单一大 `AppState`。
- **共享配置事实（第一/三阶段）**：新增 `lib/platform/config_facts.dart`，把从渲染 JSON 提取端口、
  API secret、混合入口和 TUN 信息的逻辑统一为 `ConfigFacts`。
- **共享桌面运行时基础（第三阶段）**：`lib/platform/proxy_controller_base.dart` 成为公共抽象，
  Linux/Windows/Android 各自控制器差异化覆盖，配合 `unsupported` 占位控制器保留未实现平台的可用性。
- **UI 模块化**：`home_page` 拆为 `home_active_node`、`home_connection`、`home_dashboard`、`home_traffic`，
  通用控件拆为 `widgets_data` / `widgets_layout`；`lib/app.dart` 承载应用装配，`main.dart` 退化为入口。
- **动态端口和统一配置校验（第三阶段）**：新增 `lib/data/port_allocator.dart`，每次启动前在
  loopback 上探测端口；原先固定的 9291 / 2080 降级为 `ConfigBuilder.defaultClashApiPort` /
  `defaultLocalProxyPort`，仅在被其他代理软件占用时才更换，用户自己的防火墙规则和面板书签因此继续有效。
  端口在权限授予之后、`start` 之前选定（这是内核绑定前的最后时机），并在整个会话内保持不变——reload
  必须渲染出运行中内核已经绑定的同一组端口，否则会切断桌面运行时轮询的控制通道。分配失败不致命，
  回退到首选端口对，与该分配器存在之前的行为一致。应用自身的三个 HTTP 取数路径（订阅导入、规则集
  下载、出口 IP 查询）随 `viaLocalProxy` 一并接收会话端口。
  校验则统一到 `_renderConfig()`：所有平台的配置都从这里离开状态层，此前只有桌面控制器会在边界的
  另一侧检查输入，Android 则把 JSON 直接交给 libbox。现在同一个 `ConfigFacts` 在配置离开之前就会
  拒绝它，并以结构化的 `NoticeKind.configInvalid` 上报（错误信息只指出字段名，绝不含取值——配置中
  带有节点凭据和 Clash API token）。
- **背景信号场接入真实流量**：`ConsoleBackground` 的节点/链路场此前是固定图形加 12 秒自由循环，
  在饱和下载和空闲隧道下看起来完全一样；且自 `1487a3e` 拆分 shell 之后没有任何位置传入
  `showSignals`，实际是死代码。现在由 `app_state` 的 `downlinkHistory` / `uplinkHistory` 驱动，
  归一化方式与 `TrafficFlowChart` 一致，因此背景和前景图表对同一次突发的表述不会矛盾。动画改为
  每个采样一次心跳而非 `repeat()`：空闲隧道自行静止，不再常驻 ticker——顺带修正了一个隐患，
  常驻 ticker 会让任何渲染已连接界面的 widget 测试永远等不到帧稳定，只能超时而非失败。前景
  `SignalArtwork` 进一步改为低频底图漂移、少量主丝线波动和无跳点的羽化高光，空闲与减弱动画
  状态保持静止。
- **链式代理（第三阶段）**：`ProxyNode` 持久化上游节点 ID，节点页提供「链式代理」选择面板，
  配置渲染时将多跳关系解析为 sing-box `detour` 标签；删除节点、刷新订阅和重载运行中的配置都会
  清理或应用关系，并在状态边界阻止自环与环路。`auto` 仍按链的入口节点测速，链中每一跳可继续
  指向下一跳。配置边界同时按 endpoint ID 合并重复记录，保留节点页别名但避免生成重复 outbound
  tag，兼容旧版本已经保存的重复订阅数据。

- **共享桌面运行时基座（第三阶段，部分完成）**：新增 `lib/platform/desktop_runtime.dart`，
  `DesktopRuntime` 承载两个桌面控制器此前各写一遍的四条广播流、会话代号记账
  （`beginSession` / `isCurrentSession`，用于让被取代的启动作废）、生命周期串行队列
  （`enqueueLifecycle`，失败不污染队列）、每会话仅报一次错的闩锁，以及子进程 stdout/stderr
  的行泵。Linux 与 Windows 控制器各减约 175 行，改为继承同一基座。
  平台差异（核心发现、tun 授权、停止信号、系统代理接管）刻意留在子类——把它们也硬塞进
  一个形状，就不是重构而是重写了。
  这次抽取顺带暴露出一处**已经发生的行为分叉**：Linux 的注释写明 `/group/{n}/delay` 是
  Clash.Meta 扩展、sing-box 并不实现，因此逐个成员测速；而 Windows 的 `urlTest()` 正是在调
  这个接口。两份实现各自演化正是计划里担心的风险，已在下方「抽取共享桌面运行时」记录待办。

后续计划（Windows 单实例/提权 IPC、API 超时轮询、WinINet journal、系统代理接管状态等 P0/P1 项）仍在
本计划范围内待实施。本重构时的全量验证：`flutter analyze` 无告警，`flutter test` 全绿。

## 结论摘要

当前版本的核心链路已经完整：配置可以从导入流转到平台运行时，Android 使用前台 VPN 服务，Linux 和 Windows 由桌面进程监管 sing-box，桌面端还具备系统代理恢复、单实例和托盘能力。现有测试也覆盖了主要纯 Dart 逻辑。

下一阶段的主要风险不在界面，而在异步操作的并发一致性、跨平台生命周期语义和 Windows 异常恢复。建议先处理可能造成连接中断、双实例或代理残留的问题，再进行运行时抽象和功能扩展。

## 现有基础

- `ProxyController` 已经隔离了 UI 与原生权限、进程、VPN 和系统代理细节。
- Android 服务生命周期独立于 Flutter 引擎，具备重连时回放状态的基础。
- Linux 配置文件使用受限权限的 XDG 数据目录，Windows 使用每次运行的配置文件。
- 日志和 UI 通知已经做了限流或批处理，Linux 的代理组轮询间隔也比 Windows 更保守。
- 当前测试结果：全量测试 `567 passed / 17 skipped`，静态分析通过；Windows UAC、WinINet 和真实 TUN 仍缺少目标平台上的实时验证。

## 优先级问题

### P0：统一运行时操作的串行化

`AppState` 中的 `_busy` 主要用于界面展示，并不能阻止 `connect`、`disconnect`、`reload`、导入和订阅刷新交错执行。控制器在异步启动尚未完成时也可能再次收到启动请求。`_absorb()` 还会启动未等待的持久化任务，导致导入页面已经结束但数据尚未落盘。

潜在结果：

- 新旧核心进程交替启动或停止；
- 配置文件、选中节点和订阅列表互相覆盖；
- 关闭应用过快时丢失刚导入的数据；
- 一个操作失败后覆盖另一个操作产生的状态或提示。

建议：

1. 在 `AppState` 增加统一的异步操作队列或互斥锁，至少覆盖运行时操作和持久化操作。
2. 给每次运行分配递增的 operation/session id，忽略旧运行的迟到事件。
3. 让导入吸收和存储写入返回 `Future`，调用方等待并处理异常。
4. 对连接、断开和重载增加明确的状态转移表，而不是仅依赖布尔变量。

验收标准：快速连续点击连接/断开、同时导入两个订阅、导入后立即退出时，最终进程、UI 状态和存储内容保持一致，且不会出现未处理异常。

### P0：设置变更只重载真正影响核心配置的字段

`AppState.applySettings()` 当前对所有设置变更都执行 `reload()`。但是主题、语言和关闭到托盘属于展示或桌面 Shell 配置，并不会进入 sing-box 配置。连接状态下切换这些选项会不必要地重启代理并中断现有连接。

建议把设置分为三类：

- **运行时配置**：代理模式、系统代理、DNS、规则、监听端口等，变更后才重载核心；
- **展示配置**：主题、语言、日志展示等，只更新 UI；
- **Shell 配置**：关闭行为、托盘相关设置，只更新桌面 Shell。

可以通过配置指纹或显式字段分组判断是否需要重载，并为每一类设置增加测试。

### P0：修正 Android 与桌面端不同的生命周期语义

通用的 Flutter `detached` 生命周期处理会调用 `state.disconnect()`，但 Android 的 VPN 属于独立的前台服务，设计目标是 Flutter 引擎被销毁后隧道仍然运行。两者语义冲突，可能导致页面或引擎暂时脱离时错误停止 VPN。

建议：

- Android 不因 Flutter 引擎 `detached` 自动断开 VPN；
- 桌面端继续在真正退出时执行完整的 `shutdown`；
- 启动或重新连接 Flutter 引擎时，优先读取服务当前状态；
- 添加 Android activity/service 与桌面生命周期的分平台测试。

### P0：增强 Windows 提权交接和单实例保证

当前 UAC 流程启动管理员子进程后，旧进程只等待固定的短时间便退出，缺少“新进程已成功接管”的确认。子进程初始化失败时，用户可能只看到原窗口消失。Windows 单实例在固定 TCP 端口绑定失败、但又探测不到旧实例时会放行，这会给双实例和端口冲突留下窗口。

建议：

- 使用 Named Mutex 判断唯一实例；
- 使用 Named Pipe 或等价 IPC 做激活和提权接管确认；
- 子进程完成单实例注册、配置初始化并进入可用状态后，再通知父进程退出；
- 接管失败时保留旧窗口并展示可诊断错误；
- 桌面退出流程最后才释放单实例资源。

相关验收场景：普通模式切换 TUN、UAC 拒绝、UAC 子进程启动失败、旧实例卡死、端口被其他程序占用、旧实例正在恢复系统代理时再次启动。

### P1：让 WinINet 代理恢复具备崩溃一致性

Windows 原生桥接目前按多个注册表值依次写入，并且先启用代理再写服务器地址。进程在中间退出时可能留下半成品代理设置；恢复逻辑若发现当前服务器地址不匹配，也可能无法判断这是应用残留还是用户已经主动修改。

建议采用轻量 journal：

1. 记录完整的用户原始快照和本次应用配置；
2. 先写入完整的服务器、例外、PAC 等值；
3. 最后一步才切换启用标记并发送 WinINet 通知；
4. 启动、停止和异常退出都执行幂等恢复；
5. 恢复失败时进入明确的 degraded/error 状态并提供人工修复提示。

### P1：补齐 API 超时和轮询策略

Linux Clash API 的 HTTP/WebSocket 请求没有统一的连接和读取超时，因此启动 readiness 的总截止时间并不能约束一个已经挂起的请求。Windows 每秒同时轮询流量和代理组，并且每次请求都创建新的 `HttpClient`，资源开销和日志噪声都偏高。

建议：

- 为 HTTP 请求设置连接、读取和总超时；
- 为 WebSocket 建连和断开设置超时；
- 复用桌面端 API client；
- 流量保持约 1 秒更新，代理组改为 5 秒或事件触发；
- 启动失败、API 超时和核心进程退出只产生一次最终错误状态。

### P1：区分“核心运行”和“系统代理已生效”

在 Linux 不支持 `gsettings` 或 KDE 配置工具的桌面环境中，系统代理可能没有实际应用，但控制器仍会报告 `connected`。这会让用户误以为所有流量已经接管。

建议将状态拆成核心状态和接管状态，至少在 UI 中明确显示：

- 核心已连接，系统代理已应用；
- 核心已连接，但系统代理后端不可用；
- TUN 已启用；
- 仅运行本地混合端口，未接管系统流量。

### P1：收紧订阅导入的并发和内存边界

订阅导入复用带有可变 `findProxy` 策略的 `HttpClient`。不同订阅并发请求时，代理策略可能互相覆盖；订阅响应体也没有统一的最大大小限制。

建议：

- 每个请求使用独立 client，或把代理策略变成不可变的请求参数；
- 限制响应体大小，并在超过上限时提前终止；
- 限制并发刷新数量；
- 对超时、截断响应和解析失败提供不同的用户提示。

## P2：功能和维护性改进

### 清理或实现未完成配置

`perAppProxyEnabled` 和 `perAppProxyBypass` 已接入设置 UI、配置渲染和 Android VPN builder。后续可补充对不可启动应用的管理，以及更细的应用分类和批量操作。

### 统一配置事实和错误模型

Linux 和 Windows 都需要从渲染后的 JSON 中提取端口、API secret、混合入口和 TUN 信息，但目前解析逻辑分散。建议抽取共享的 typed `ConfigFacts` 和配置校验器，统一处理格式错误、版本不兼容和缺失字段。

同时把目前的英文字符串错误改为结构化错误码，例如：

- `coreNotFound`；
- `coreVersionTooOld`；
- `permissionDenied`；
- `elevationHandoffFailed`；
- `systemProxyUnavailable`；
- `apiTimeout`。

UI 再根据平台和语言进行本地化，避免底层错误直接透传英文。

### 抽取共享桌面运行时（第一步已完成，其余待做）

`LinuxProxyController` 和 `WindowsProxyController` 重复了进程监管、启动 readiness、日志解析、流量统计、代理组更新和停止清理逻辑。原计划抽取四层：

- ~~会话记账与生命周期串行化~~：已完成，见「实施进度」中的 `DesktopRuntime` 条目；
- `DesktopProcessRuntime`：进程启动、退出、信号和超时——两侧仍各自实现，且**语义本就不同**
  （Linux 发 `SIGTERM`，Windows 先 `SIGINT` 再逐级升级），强行统一会变成改行为而非重构，
  应先确认哪一种是想要的，再决定是否收拢；
- `ClashApiRuntime`：HTTP/WebSocket、认证、重连和轮询——**这层是当前最值得做的**，见下；
- ~~`ConfigFacts`~~：已完成，见「实施进度」；
- 平台适配层：权限、系统代理、核心路径和进程参数——差异是真实的，保留在各自控制器中。

**重构过程中发现的既有分叉（已查证并修正）**：Linux 的 `urlTest()` 注释断言 `/group/{n}/delay` 是
Clash.Meta 扩展、sing-box 并不实现，因此它逐个测试成员；而 Windows 的 `urlTest()` 一直在调这个接口。
查证结论是**注释错了**：该路由位于 `experimental/clashapi/api_meta_group.go`，自 v1.12.0（本仓库
`singBoxMinimumVersion`）起就已挂载；对本机运行的 sing-box 1.14.0 实测 `GET /group/proxy/delay`
返回 200 与 `{"auto":444,"direct":444}`。已在 `ClashApiClient` 补上 `groupDelay()`，Linux 改为优先
一次请求测完整组，逐个测速降级为兜底路径（用于其他 Clash 实现，或批量测速失败时——它还能渐进
回填结果）。实测确认的三处引擎行为已写进该方法的文档：缺少或无法解析 `timeout` 返回 400；未能连通
的成员被省略而非报 0（因此调用方应保留旧读数，而不是用 0 覆盖）；`http://` 的 url 会被引擎丢弃。

分叉的**根因仍在**：Windows 完全没有走 `ClashApiClient`，而是手写了一套 `HttpClient` 请求
（`_apiRequest` / `_pollStats` / `_pollGroups` / `_selectedOutbound`）。把 Windows 迁到
`ClashApiClient` 会消掉约 200 行重复代码，并让两个平台不可能再对同一个内核给出相反判断，但它会
**改变 Windows 的行为**（轮询换成 WebSocket），因此属于独立一项、需要在 Windows 上验证，不应混在
行为保持型重构里。

### 端口、核心和平台边界

- ~~固定的 Clash API 与本地混合端口容易和其他代理软件冲突，后续可改为运行时动态分配并注入配置。~~
  已完成，见「实施进度」中的动态端口条目。
- Windows 当前主要检查核心文件是否存在；应补充最低版本、文件权限和可选 hash 校验。
- 桌面 Shell 声明支持 macOS，但仓库没有 macOS runtime 实现，应统一平台支持声明。

### 链式代理（前置代理）

sing-box 的 Dial Fields 提供 `detour`：出站 A 设 `detour: "B"` 后，A 的流量经由 B 建立连接，B 还可以继续
`detour` 到 C，落地形态即「机房中转 → 家宽出口」。渲染层改动很小——`ProxyNode.toOutbound()` 已经是
`...raw` 透传，`detour` 只是多一个字段。工作量在模型和 UI：需要表达「节点 A 经由节点 B」这一关系，
并决定它与 `auto`（urltest）组的交互——链上的节点是否参与自动测速、以及测速结果归属于链还是归属于出口。

一个容易踩的硬性限制：设置 `detour` 后该出站的其他 dial 字段全部失效（socket 由上游打开），因此
`bind_interface`、`domain_resolver` 这类必须写在上游那一条上。

已完成：`ProxyNode.detourNodeId` 负责持久化关系，节点页用 bottom sheet 选择直接连接或上游节点，
状态层在保存和运行中 reload 前再次校验环路，订阅刷新/删除会清理失效引用。配置渲染先建立节点
tag 表，再把节点 ID 解析成 sing-box outbound tag；重复 endpoint ID 只输出首条 outbound，避免
旧订阅数据触发 `duplicate outbound tag` 并阻塞整个隧道启动。`auto` 仍选择入口节点并参与测速，
链上的每一跳可以继续设置自己的 `detour`。

### OpenVPN 节点支持（独立大项，需评估收益）

与链式代理是两件事，不应混在一起推进。现状有三处阻碍：

- `importer.dart` 只处理分享链接、sing-box JSON 和 base64 链接列表，没有 YAML 解析器，Clash 风格的
  订阅（`proxies:` 列表）目前无法导入；
- sing-box 中 openvpn-client 是 **endpoint 而非 outbound**，且自 1.14.0 才提供，而本仓库
  `singBoxMinimumVersion` 仍为 `(1, 12)`，`NodeProtocol` 也没有对应项（`fromTag` 会判为 `unknown`）。
  它要渲染进 `endpoints` 数组，与现有 outbound 渲染路径不是一回事；
- 字段名与 Clash 差异较大（`ca`/`cert`/`key` → `tls.certificate`/`client_certificate`/`client_key`，
  `data-ciphers` → `data_ciphers`，`tls-auth`/`tls-crypt` → `tls.control_wrap`），`raw` 透传救不了，
  必须写字段映射。另外 TLS 模式下 `cipher` 会被忽略，只在 `static_key` 模式生效。

需要注意 endpoint **不安装操作系统路由**：`routes` 不写入系统路由表，`redirect_gateway` 也只表达偏好、
不装默认路由，`block-local` 不支持。这对「家宽落地」的实际效果有影响，建议先在单个节点上验证再投入。

`tools/vpngate2singbox.php` 已经能把 VPNGate 的 .ovpn 转成 sing-box endpoint 配置（含 `detour` 参数），
可用于在抬升内核底线之前先行验证协议本身是否可用。

## 推荐迭代顺序

### 第一阶段：一致性和安全退出

- 设置字段分组，避免展示设置触发 reload；
- 增加运行时操作队列和持久化队列；
- 修正 Android `detached` 行为；
- 修正桌面退出时单实例释放顺序；
- 补充 Linux API 请求超时和重复错误抑制。

### 第二阶段：Windows 可靠性

- Named Mutex/IPC 单实例；
- UAC 子进程 ready ack；
- WinINet journal 和幂等恢复；
- Windows live test：UAC、TUN、核心退出、代理残留和 Job Object。

### 第三阶段：结构和功能扩展

- 抽取共享桌面运行时；
- ~~动态端口和统一配置校验~~（已完成，见「实施进度」）；
- ~~链式代理（`detour`）~~（已完成模型、节点页配置、持久化、环路校验和运行中 reload）；
- 完成或移除按应用代理配置；
- 结构化错误与完整本地化；
- 扩展不支持 GNOME/KDE 的 Linux 桌面代理后端。

OpenVPN 节点支持不列入本阶段顺序：它要抬升内核底线到 1.14、新增 YAML 解析和 endpoint 渲染路径，
规模与上面各项不在一个量级，且实际收益需要先用 `tools/vpngate2singbox.php` 在单个节点上验证。
确认协议可用之后再单独排期。

## 验收与回归要求

每阶段至少应覆盖：

- 连接、断开、重载、切换节点的快速连续操作；
- 导入、刷新、删除订阅与应用退出并发发生；
- Android 引擎重建、后台服务持续运行和重新绑定；
- Linux API 不响应、核心异常退出、系统代理后端缺失；
- Windows UAC 拒绝、提权启动失败、第二实例激活、WinINet 恢复和外部程序占用端口；
- 配置中包含敏感信息时，日志和错误信息不得泄露完整凭据。

纯 Dart 测试继续作为基础；涉及真实权限、注册表、TUN、VPN 服务和桌面代理的场景需要在对应操作系统上增加集成或手工验收记录。
