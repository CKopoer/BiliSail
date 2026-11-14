# DLNA 多网卡与 IPv4／IPv6 发现

日期：2026-11-14。

## 问题与实现

原搜索只绑定 `0.0.0.0`，由系统选择组播出口；Windows 同时启用以太网和 TUN／VPN 时，SSDP 可能进入虚拟网卡而未到达目标局域网。原实现也只发送 IPv4 搜索，且读取设备描述会阻塞后续回复处理。

- 每次搜索重新枚举 `NetworkInterface.list(includeLinkLocal: true)`，对非回环、非组播、非未指定的本地地址分别尝试绑定。IPv4 通过 `IP_MULTICAST_IF` 指定源地址，IPv6 通过 `IPV6_MULTICAST_IF` 指定接口索引；不按网卡名称或默认网关判断是否有效，不写入固定 IP、接口索引或系统路由。
- IPv4 发送到 `239.255.255.250:1900`，IPv6 使用每个接口的链路本地 SSDP 组 `[ff02::c]:1900`，IPv6 HOST 字段使用 `[ff02::c]:1900`。目标仍为 MediaRenderer、AVTransport 和 Bilibili NirvanaControl；启动及 1 秒后各发送一轮，不无限重试。主动搜索只收单播应答，不额外订阅被动 NOTIFY。
- 整次搜索共用 12 秒截止时间，包含接口枚举、绑定和描述请求。每次最多接纳 64 个带接口上下文的描述地址、64 个设备，同时最多执行 4 个描述请求；某个接口绑定、发送或收包失败不阻止其他接口。取消订阅、取消令牌、截止和 dispose 均释放 socket、订阅、重发定时器、排队任务和 HTTP。晚到的枚举／绑定／HTTP 不得重新启动搜索或发布设备。
- 以 UDN 合并设备，每个设备保留本次搜索验证成功的端点和源接口。重复回复不会重复读取描述；同一 URL 经不同接口发现仍分别验证。后来发现的 Bilibili 能力或同等能力的 IPv4 端点可更新同一设备条目。重复搜索重新读取网卡，并刷新重新发现设备的候选端点。
- IPv6 地址按二进制地址比较；URI 的 `%25` zone 与 socket 的 `%` scope 分别处理。链路本地描述、URLBase、AVTransport 和 Nirvana URL 绑定接收接口，拒绝跨主机或显式不同 scope 的地址。连接使用带 scope 的目标及本地源地址，HTTP URI／Host／TLS 对端身份使用去掉 scope 的地址；保留无账号凭据、禁止跳转和系统 TLS 验证。
- 控制优先使用之前成功的端点，其次优先 IPv4；TCP 建连失败可在同一 5 秒总预算内尝试其他已验证端点。建立连接后遇到超时、HTTP 错误、SOAP Fault 或回复丢失均直接失败，不向另一端点重放。实验身份投屏和弹幕命令只使用相应端点自己声明的 Nirvana 能力。

现有领域模型和投屏 UI 保持单设备条目；网卡和多个地址属于仓储内部的短期传输上下文，不增加持久化配置或依赖。

## 自动验证

新增 `test/features/playback/dlna_network_test.dart`、`dlna_discovery_test.dart`，覆盖：

- 多接口及双栈目标、显式组播选项、IPv4 源地址／IPv6 接口索引、坏接口隔离、接口重新枚举与有限重发。
- IPv6 等价写法、URI zone 编码、同一链路本地地址处于不同接口、作用域传递及跨主机／跨 scope 拒绝。
- 全局截止覆盖枚举、取消后晚到的绑定、主动取消订阅、dispose、描述请求并发上限及排队任务停止。
- 独立接口的慢描述不阻塞其他设备、回复去重、真实 IPv6 回环 UDP → HTTP 描述 → SOAP／Nirvana 控制。
- 同一 UDN 的 IPv4／IPv6 端点合并、TCP 建连失败后回退，以及 SOAP Fault／回复丢失不重放；按端点识别实验能力。
- 注入连接器并接入真实回环 HTTP 服务，校验链路本地目标／源地址的 scope 传到连接层，同时不进入 HTTP authority；此项不依赖测试机是否拥有某个实际链路本地地址。

定向回归命令：

```powershell
flutter test --no-pub test/features/playback/dlna_network_test.dart test/features/playback/dlna_discovery_test.dart test/features/playback/dlna_cast_repository_test.dart test/features/playback/casting_handoff_regression_test.dart test/features/playback/casting_controller_test.dart test/features/playback/api_cast_media_repository_test.dart
```

**63 项通过**，无条件跳过。新增文件及实现的定向静态分析无问题。日志：`build/dlna-dual-stack/targeted.log`。

首次完整 `tool/check.ps1 -SkipPub` 通过：根测试 **5396 项通过、13 项条件跳过**，格式、全项目分析、打包边界及四包测试通过；bili_api **920**、bili_player **256**、bili_danmaku **161**、bili_mux **5**。player 3 项、mux 10 项为条件跳过；未配置 `BILI_MUX_LIBRARY`，不能将 mux 原生用例计为通过。日志：`build/dlna-dual-stack/check.log`。

最后的 scope／HTTP authority 补充修正后：

- `tool/check.ps1 -SkipPub -Stage Lint` 再次通过。
- `tool/check.ps1 -SkipPub -Stage RootTests` 为 **5383 项通过、13 项条件跳过、17 项失败**，失败均位于 `playback_session_test.dart` 的 storyboard／timeline 场景（包括一项 30 秒超时）。运行期间工作区存在同期的 `playback_session.dart`、对应测试和播放器修改，这些文件未纳入本次变更；不能将这一轮全量复查记为通过。日志：`build/dlna-dual-stack/final-check.log`。
- 独立复跑上述完整测试文件 `flutter test --no-pub test/features/playback/playback_session_test.dart`，**293 项全部通过**，该轮失败未在独立运行中重现；没有为消除全量失败修改时间轴或播放器代码。日志：`build/dlna-dual-stack/timeline-recheck.log`。
- 随后顺序重跑本次 6 个投屏测试文件，**63 项全部通过**。先前并发启动两个 Flutter 测试进程时曾遇到 Windows `sqlite3.dll` 文件占用，顺序执行后消失；不计入代码测试失败。

## 验收边界

按本次用户要求不构建、不安装、不连接真实接收端执行控制。自动化的 IPv6 网络回归使用回环地址；真实电视、手机接收端、IPv6 链路本地 HTTP／SOAP、VPN 共存、切换网络及 Android／Apple／Linux 实机兼容性留给后续构建和设备验收。协议 fixture 与纯逻辑 scope 测试不等于这些实机路径已经通过。

DTD 发现及热重载工具均确认当前没有运行中的 DTD 调试应用，未执行实际热重载，也不为此启动或构建应用。

## 协议与实现依据

- [UPnP Device Architecture 1.1，附录 A](https://upnp.org/specs/arch/UPnP-arch-DeviceArchitecture-v1.1.pdf)：双栈搜索及 IPv6 链路本地 SSDP 地址。
- [Winsock IPPROTO_IP 选项](https://learn.microsoft.com/en-us/windows/win32/winsock/ipproto-ip-socket-options)：显式 IPv4 组播出口。
- [Dart IPv4MulticastInterface](https://api.dart.dev/dart-io/RawSocketOption/IPv4MulticastInterface.html)、[IPv6MulticastInterface](https://api.dart.dev/dart-io/RawSocketOption/IPv6MulticastInterface.html)：使用 SDK 提供的跨平台选项编号，不硬编码 Windows 常量。
