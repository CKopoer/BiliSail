# 乐播旧投屏控制地址兼容

日期：2026-11-14。

## 原因与修复

部分旧乐播接收端在设备描述的 `controlURL` 中声明 `_urn:schemas-upnp-org:service:AVTransport_control`。原实现直接调用 `Uri.resolve()`，冒号前的 `_urn` 被当作非法协议名并抛出 `FormatException`；`parseDescription()` 随后返回空设备列表，设备在发现阶段即被过滤。

设备描述解析现在通过同一私有入口解析 AVTransport 和已识别的 NirvanaControl 控制地址。仅当控制地址以 `_urn:schemas-upnp-org:service:` 开头时补充 `./`，再交给原有 [resolveDlnaUri](../../lib/features/playback/data/dlna_network.dart) 处理。兼容处理不应用于 URLBase；标准相对路径、绝对路径与 HTTP(S) 地址继续沿用原规则。

继续使用设备声明的 URLBase／描述目录与端口，不硬编码乐播端口或改成根路径；保留同主机、无凭据、无 fragment、HTTP(S) 及 IPv6 接口 scope 约束。未修改媒体地址、DIDL／SOAP 转义、控制命令串行化、取消或失败不重放规则，也未新增依赖。

实现位于 [DlnaCastRepository](../../lib/features/playback/data/dlna_cast_repository.dart)，回归位于 [dlna_cast_repository_test.dart](../../test/features/playback/dlna_cast_repository_test.dart)。

## 回归与验证

- 五组设备描述覆盖描述根目录／子目录、独立 URLBase 端口／目录和 IPv6 链路本地 scope；每组同时验证原始旧地址与已有 `./` 的相对地址，并覆盖 AVTransport 和 NirvanaControl。
- 标准地址对照覆盖相对路径、父目录、根路径、根路径下的 `_urn` 文件名和同主机 HTTP／HTTPS 绝对地址。
- 边界回归继续拒绝跨主机、带凭据、非 HTTP(S)、fragment、其他非法协议前缀及非法 URLBase。
- 本机真实 HTTP 模拟器接收旧控制路径上的 SetAVTransportURI／Play／Pause，验证签名地址、中文标题、DIDL 文本分层转义、无账号 header，以及 SOAP Fault 后不重放。
- 修复前相关测试文件 10 项通过、6 项失败；五组旧地址和实际 SOAP 交接均因设备列表为空而失败。修复后结果见下方检查记录。

固定 Flutter 3.47.6／Dart 3.13.5 下的本轮结果：

- 六个投屏相关测试文件 **70 项全部通过、无跳过**，覆盖本次新增 7 项回归及已有发现、交接、取消和账号隔离场景。日志：`build/validation/piliplus-2680-2026-11-14/final-targeted-tests.log`。
- 本次两个 Dart 文件定向静态分析无问题；文档 14 处相对链接及本次文件的 `git diff --check` 通过。
- 已运行 `tool/check.ps1 -SkipPub`，打包边界、原生来源脚本和根应用／四包格式检查通过；随后全项目静态分析在同期路由、评论、消息等修改处报告 12 条诊断并中止。其中包括 `router.dart` 缺少必填 `link`、`CommentsRepository.locate` 暂未定义及无关 lint。未修改这些文件；根应用全量和四包测试未由该次命令执行，不能将完整检查记为通过。日志：`build/validation/piliplus-2680-2026-11-14/check.log`。
- 首轮六文件回归的 `api_cast_media_repository_test.dart` 曾因同期 `message_client.dart` 语法错误无法加载，其余 58 项通过；该语法错误随后消失，以上最终 70 项完整补跑通过。

未连接真实乐播／AirPin／云视听接收端，未构建、安装或进行设备投屏验收；本机协议回归不等于真实接收端兼容通过。DTD 发现没有运行中的调试应用，热重载工具也确认无可用连接，本轮未完成实际热重载。

## 参考依据

- [PiliPlus issue #2680 的定位评论](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2680#issuecomment-6597938908) 讨论 `dlna_dart` 的 DIDL 转义缺陷；本项目自行实现分层转义，未发现相同缺陷。
- [PiliPlus PR #3507](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3507)，合并提交 `8006ace0a2698cb664e685d7bd6c0ac72988771a`，说明旧乐播控制地址的解析问题与相对路径兼容方式。只参考协议现象和修复条件，按本项目既有 XML／URI 解析和测试边界独立实现；未复制 GPLv3 应用页面或测试源码，未修改相邻仓库或 Pub 缓存。
