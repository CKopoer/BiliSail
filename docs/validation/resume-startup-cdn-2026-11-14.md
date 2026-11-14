# 历史续播与默认 CDN

日期：2026-11-14（Asia/Shanghai）。

## 现场原因

用户提供 Windows Release 登录账号和视频 `BV1ERWq6eEG7`。在普通 `lib/main.dart` Release 入口复现：从 70.533 秒续播，首轮 native open 于 `04:25:10.453Z` 开始，`04:25:16.468Z` 超时；当时已有视频参数和输出，音轨尚未解码。换到接口返回的备用地址后，`04:25:17.864Z` 在相同位置完成双轨准备。原始脱敏记录在应用日志 `playback-1794629703625228-15432.log`，没有记录媒体 URL／Cookie。

进一步在独立本机探针中，用相同账号在内存解析媒体、直接调用 media_kit，原 PCDN `q6ux09t.edge.mountaintoys.cn` 在 70.533 秒处仍长期 `seeking=yes`，缓存为零且没有音频参数；启动播放也未解除。生产 engine 随后在 tracks 阶段收到原生加载失败。说明不是仅由应用的暂停准备屏障或新预读恢复探针造成；后者在 opening 阶段不会启动。日志在忽略目录 `build/validation/resume-online-before.log`，探针不写账号设置／历史，不输出凭据或签名地址。

重新解析后另一个 PCDN 节点 `t6ur09t.edge.mountaintoys.cn` 曾在约 1.06 秒就绪，常规 CDN 在约 1.53 秒就绪。网络节点和签名响应会变化，不能据此宣称常规 CDN 在所有场景下更快，也不能将所有续播等待归咎于同一节点。这里修复的是默认选线先尝试不稳定 PCDN、失败后才使用已返回普通镜像的行为。

受控 HTTP 分轨从 0／400 秒打开时，播放器均先读取 MP4 头，续播直接请求视频偏移 5099241 和音频偏移 3355169，无需读取从零到历史位置的全部媒体。保留原生 `Media(start: ...)`、位置确认、双轨解码和输出屏障，没有通过跳过就绪检查或放宽截止时间掩盖网络停滞。

## PiliPlus 对照与修改

只读核对相邻 PiliPlus `cab0114a21ce7fad5b90b9a4d788d35d313d25f9`：

- `lib/utils/storage_pref.dart:279` 的默认值为 `CDNService.backupUrl`。
- `lib/utils/video_utils.dart:27` 的 `getCdnUrl` 默认优先接口返回的普通镜像，`os=mcdn` 和 302 节点不进入普通镜像优先分支。
- `lib/plugin/pl_player/controller.dart` 使用 EDL 分轨和 `Media(start: seekTo)`，与本项目由原生执行初始续播的方向一致。

参考核心／库插件锁定 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`，视频锁定 `bggRGjQaUbCoE/media-kit` 的 `85f0a69ea66b100882b27a3375c72e5155375343`。仅借鉴默认选线行为，独立实现排序，没有复制 GPLv3 应用源码／资源或修改参考仓库、Pub 缓存、媒体依赖。详见[采用边界](../references.md)。

按用户要求，[自动模式](../../lib/domain/media_cdn.dart) 从第一次打开起就优先返回的普通 UPOS／proxy-tf 镜像和海外 Akamai 地址，排除 `os=mcdn`／302 节点；视频和每个音轨分别按同一规则排序。候选分组内保留接口顺序，去重后返回不可变列表。没有普通镜像时保持原返回地址和顺序。

自动模式仅重排已返回的 URI，保留对象身份、完整签名、编码 path、重复 query 和所有原始回退，不采用参考项目自动构造代理或改写 host 的后备逻辑。具体节点和运营商选择仍优先已有配置；`automatic` 序列化值、缺失／非法值回退、设置持久化和数据库版本不变。共享规则用于视频／影视、预览及下载选源，直播策略不变。

## 验证

使用 Flutter 3.47.6／Dart 3.13.5，媒体依赖仍为本项目原固定 `302d60eedc55ca677e911e529569b1e14d8c2e7e`。

- 更新前的自动选线行为测试失败，修复后 CDN／DASH 映射与播放会话的定向测试通过；新增用例覆盖普通镜像优先、无普通镜像、伪装 UPOS PCDN、302、海外签名、稳定顺序、去重／幂等、显式偏好和音视频独立排序。
- [Windows HTTP 续播测试](../../integration_test/windows_resume_startup_test.dart) 两项通过：0／400 秒打开均在 5 秒预算内完成，后者直接对两轨发送非零 Range，并确认播放前后视频／音频解码。已加入 `tool/test-windows-buffer.ps1`。本机 Debug 记录约 418／221 毫秒包含随后播放、暂停的耗时，仅用于本机受控行为观察，不作为线上性能结论。
- `windows_prefetch_recovery_test.dart` 两种断流场景再次通过；恢复时仍剩约 110 秒缓存，恢复后缓冲终点继续增长，保留前一项预读恢复修复。
- `tool/check.ps1 -SkipPub` 全阶段通过：根应用 5359 通过／13 跳过，API 920、播放器 256、弹幕 161、mux 5 通过；播放器 3 项显式原生测试因未配置环境跳过。`BILI_MUX_LIBRARY` 未配置，mux 10 项原生测试跳过，不计为原生通过。最终改动文件的静态分析再次通过。
- Windows x64 普通 `lib/main.dart` Release 构建通过，保留现有登录账号和设置；实际从搜索结果进入指定视频，关闭播放后再次打开。第二次从 51.500 秒历史位置开始，`04:42:36.721Z` 到 `04:42:37.214Z` 约 493 毫秒完成原生打开，视频／音频均有解码及视频输出证据，没有超时、切备用或重新从零加载。桌面实际观察到恢复后的画面和弹幕。此时间仅衡量该次 native open，不含页面解析／请求／导航，也不是同节点、同历史位置的性能基准。
- 首轮 Release 构建曾因另一个本机 Release 进程占用 `WebView2Loader.dll` 而失败；进程退出后重建成功，没有通过修改构建产物或忽略错误交付。
- 对受控 HTTP 续播入口另通过 DTD 完成热重载，未发现运行时错误；测试入口和本轮启动的 Release 已退出，没有留下后台播放。
- 受影响文档 698 个相对链接、缓冲脚本 PowerShell 语法及 `git diff --check` 通过。

本轮检查日志为忽略目录 `build/validation/resume-check.log`、`resume-analysis-final.log`、`resume-native-after.log`、`resume-prefetch-after.log`、`resume-release-final.log`；Release 脱敏播放记录为应用日志 `playback-1794631180177875-11016.log`。

此前已有 `windows_buffer_ahead_test.dart` 的短片暂停重开缓存断言在原始基线也失败，见[既有记录](prefetch-network-recovery-2026-11-14.md)。本轮没有改动该断言或扩大此问题的范围。Android、macOS、iOS、Linux 没有本轮设备验证；真实 CDN 的长期弱网、全码率组合及人工听音画同步仍需专项验收。
