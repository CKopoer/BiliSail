# Android fvp 点击进度条的音频定位阻塞

## 复现与定位

2026-11-08 在连接的 Xiaomi 13（2211133C／Android 16）上检查普通入口开发 Release，包名 `dev.bilisail.bilisail.test`，版本 1.2.8+5／12805。兼容画面输出、fvp、公开视频播放后点击进度条，目标画面先变化，进度仍保持旧值，随后出现播放失败。

同机本地 HTTP Range 分轨回归复现：原实现的 playing、immediatePause、pauseRequested 三项约 15 秒后失败；从未播放的 paused 场景以及取消后重新准备的场景通过。临时阶段记录显示：9375ms 的视频 seek 已回调 9375ms，接下来的纯音频 seek 一直不回调，直到总 deadline 取消。不是等待视频数据，也不是 UI 遮罩本身导致卡顿。

改用非缓存音频 seek、更换 Android 音频输出、使用音频快速定位标志均没有消除问题，这些试验已撤回。固定 MDK 0.39.0 的同条件对照仍复现。可确认的边界是：MDK 纯音频管线播放后再暂停时，暂停中的 seek 完成回调可能被留住；本记录不把它进一步归因于未取得原生堆栈证明的内部锁。

另发现独立构建问题：配置声明固定 MDK 0.39.0，原手机 Release 的 `libmdk.so` 实际为 `MDK 0.40.1 (git 1abdbda)`。fvp 的 CMake 固定 URL／SHA-256 参数为空，沿用了上游 nightly 缓存。`afterEvaluate` 修改 DSL 晚于 AGP 对原生选项的取样。修复后实际为 `MDK 0.39.0 (git eed59da)`；没有将版本偏差误认为已单独解决音频阻塞。

用户报告的偶发回到开头没有在旧版单独稳定复现。回归同时验证确认后的目标位置、恢复推进和 generation，防止把收到 seek 请求或短暂显示目标帧当作成功。

## 实现边界

- 继续使用共同的 `SharedPlayerEngine`、`PlaybackSession`、有界最新目标队列和播放意图；media_kit 与 fvp 共享进度／缓存管理策略，没有页面或共享层按后端分支。
- Android fvp 在视频确认目标后，对真实音频管线执行静音、原生 Playing 确认、目标 seek、原生 Paused 确认，然后恢复最新音量。动作仍在本次 seek 的既有 deadline 和取消代次内。普通继续播放不走这段流程，不增加定时重试、代理缓存、额外源打开或第二路音频。
- 视频继续通过既有原生 `onSync` 跟随音频呈现时钟。音频短暂驱动期间 Worker 屏蔽未确认时间线事件；确认后共享层只恢复最新用户意图，暂停中的跳转仍保持暂停。
- 取消与重建也使用本次 seek 内部的原生暂停确认，不能用普通操作的 `_repreparing` 拒绝条件否决刚完成的目标。旧操作不能恢复音量；静音期间音量设置仍更新用户值，待当前目标暂停确认后应用。
- Windows／Apple／Linux fvp 路径仍使用原来的暂停定位。D77 的“不用静音预跑”增加 Android 纯音频 seek 的受控例外，初次起播和共享会话职责不变。
- Android 固定参数改在 `androidComponents.finalizeDsl` 设置。开发构建和 Android seek fixture 在安装前校验 SDK 归档摘要、解压记录及 APK 的 ELF 加载段；允许 AGP 去除不参与加载的调试节，拒绝不同代码或旧库。没有修改 Pub 缓存源码、依赖 ref、SDK 版本或相邻仓库。

## 参考与许可

只读参考 PiliPlus `265f879fa85973b4bf885bde2562f1007f1013b8` 的 `lib/plugin/pl_player/controller.dart`：同一原生播放器管理 DASH 双轨，控制器只提交目标并消费原生位置／缓冲。本项目继续把 SDK 的音频定位限制收在 fvp 适配器，不向页面增加同步或缓存状态机。

未复制 GPLv3 应用源码、资源或 schema；实现独立编写。API 语义核对 [MDK Player APIs](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)，实际固定资产和摘要以 `native/fvp/assets.lock.json` 为准。PiliPlus 所用 media-kit MIT 分支与应用 GPLv3 许可分别处理。

## 回归入口

```powershell
.\tool\test-android-seek.ps1 -DeviceId <adb-id> -Backend all -Output all
.\tool\test-android-seek.ps1 -DeviceId <adb-id> -Suite cache -Backend all -Output all
```

同步组覆盖播放、暂停、跳转后立即暂停、阻塞时暂停、停止、目标替换与多次替换；缓存组使用 720 秒分轨，断开后续网络验证缓冲内跳转，再覆盖前进、后退、缓存外和播放／暂停中的连续目标。两组都在 finally 覆盖恢复普通入口开发 Release，不卸载、不清数据，恢复原屏幕常亮设置。

日志和原版 APK 保存在忽略目录 `build/validation/android-fvp-seek-20261108/`。阶段诊断仅包含阶段、毫秒位置和结果，未记录播放 URL、headers 或凭据；最终源码已移除临时打印。

## 结果与 Windows 对照

| 验证 | 本轮结果 |
| --- | --- |
| 根检查 `tool/check.ps1 -SkipPub` | 根应用 4733、bili_api 719、bili_player 360、bili_danmaku 161、bili_mux 5 项通过；根应用 13 项条件跳过，10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过 |
| Android 分轨同步 | media_kit 两输出 18 项通过；fvp 两输出最终 18 项通过，包括取消后多次替换、暂停和停止 |
| Android 缓存／连续定位 | 两后端 × 两输出共 4 项、60 次定位通过；120 秒缓存端点保留，前后跳转与暂停／播放意图正确 |
| Windows 同条件对照 | fvp 暂停目标确认原流程 9 项通过；双后端长素材缓存组 2 项、30 次定位通过 |
| SDK 安装门槛 | 8 项离线用例通过；原版 APK 被判定为不同原生加载代码，新 APK 与固定 SDK 匹配 |
| 最终 Debug 验证 | 双后端受控入口热重载成功，无运行时错误，确认两个引擎释放后退出 |

Android 缓存内本地 Range fixture 的 fvp seek 为 132–181ms，media_kit 为 82–107ms。这是本机受控媒体结果，不能推导真实 CDN 延迟或长期性能。

Windows 与 Android 使用同一共享层和相同 MDK 0.39.0 对照后，差异仍在 MDK 的平台音频管线：Windows 暂停定位可以回调，Android 的已播放音频管线需要在静音驱动中完成定位。Android IPC 内的阶段记录已将阻塞定位在原生音频 seek 内部；Worker 屏蔽未确认事件解释了 UI 保留旧进度。更换 OpenSL 也未消除原问题，因此不能仅归因于 AAudio，更没有 Windows 播放器状态机需要同步增加此例外的证据。

普通入口 Release 上另做公开 CDN 视频烟测：10 分 12 秒的视频在播放中点击到约 7:28，1 秒后的截图已在目标位置推进；暂停后点击回约 1:45，0.8 秒后的截图确认目标与暂停。连续点按保留最后约 3:43 的目标，随后播放继续推进，没有回零或播放失败。最终系统媒体会话确认为 PAUSED。没有将这些截图当作精确时延、主观听音画同步或性能测量。

手机最终覆盖恢复普通 `lib/main.dart` 开发 Release，仍是 `.test` 身份、1.2.8+5／12805、原开发证书，未卸载或清数据。APK 位于 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，SHA-256 为 `f285ab0ff7dd2b7f90195e09b558a461f4152926a90f50919cac766d55cf788d`；APK 内 MDK 为 0.39.0。原屏幕常亮值 2 已恢复，临时手机 fixture 已清理。

本轮没有删除已有故障测试。中途新音频门槛曾错误复用普通操作的恢复态拒绝条件，导致取消后定位失败；改为复用 seek 自身的原生暂停确认后，两输出全部通过。macOS／iOS／Linux 本轮未构建或设备验证；蓝牙／音频路由变化、后台／PiP、长时间播放和人工听音画同步仍未专项验收。
