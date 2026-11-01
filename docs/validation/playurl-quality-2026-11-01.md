# 1080P60 播放请求与 PiliPlus 对照

日期：2026-11-01。反馈样本为 [BV1VNxr63EZp](https://www.bilibili.com/video/BV1VNxr63EZp)，首 P `cid=43202641987`。用户转述 Android 大会员账号打开时，播放器上方显示“当前内容暂不可用，请稍后重试”。本次没有该账号或连接的 Android 设备。

## 定位与证据边界

这条文案来自 `ApiFailureCategory.unavailable` 的应用映射，播放会话会将解析失败显示在播放器顶部。UGC 播放接口的未知业务错误、缺少 DASH 视频或伴随音轨都可能进入这个分支；单凭文案无法反推出原始业务码。

公开详情确认样本为普通视频，没有充电／付费标记；播放响应声明 `accept_quality=[116,80,64,32,16]`。本机游客和已有普通账号均未复现原文案：游客实际只返回 32／16 档，普通账号返回 80／64／32／16 档及三条 AAC 音轨。`accept_quality` 包含 116 不表示当前账号已经取得 116 轨道。

已确认并修正下列请求差异。这属于针对反馈的兼容性修复；由于没有大会员会话，**尚未证明这些差异是原反馈的唯一根因，也未完成真实 1080P60 音画验收**。不能把普通账号自动降档或合成响应测试算作大会员 60 帧播放通过。

## 源码对照和改动

只读参考相邻 PiliPlus 提交 `265f879fa85973b4bf885bde2562f1007f1013b8`：`lib/http/video.dart` 的 `videoUrl`、`lib/pages/video/controller.dart` 的 `_queryVideoUrl`／`_supplementVideoQualities`，以及 `lib/models/video/play/url.dart` 的 DASH 解析。PiliPlus 应用为 GPLv3；本次只核对协议字段和请求／选择职责，独立实现，不复制应用源码或资源、不修改相邻仓库、不新增依赖。

| 项目 | 原 BiliSail | PiliPlus 参考及本次处理 |
| --- | --- | --- |
| UGC 地址接口 | Web Cookie + WBI GET `/x/player/wbi/playurl` | 相同，继续沿用 |
| 格式参数 | 主播放没有 `fnver`；`fnval=4048`、`fourk=1` | 补充 `fnver=0`，保留全格式 DASH |
| Web 播放上下文 | 主播放缺失 | 增加 `gaia_source=pre-load`、`isGaiaAvoided=true`、`web_location=1315873` 和 `dm_img_*` 占位参数，在 WBI 签名前加入 |
| 占位数据 | 无 | 每次生成随机 Base64 噪声；图像列表和尺寸／偏移为空值，不采集真实设备指纹，不持久化 |
| 首次清晰度请求 | 将用户偏好直接作为 `qn` | UGC 主播放先请求 `qn=129`，在实际 DASH 轨道上应用用户画质／编码偏好 |
| 缺失的较低档位 | 没有补取 | 若偏好低于已返回最高档、服务端声明该档但缺少实际轨道，最多补取该档一次，按画质／编码去重合并视频轨 |
| 补取失败 | 无此步骤 | 保留首次成功取得的完整媒体；取消和认证失效继续抛出；语言／制作类型不同的补取结果不与原音轨混合 |
| 轨道解析 | 支持 camelCase／snake_case URL；保留 AVC／HEVC／AV1；合并普通／FLAC／Dolby 音轨 | 这些部分已一致，继续沿用；菜单仍只展示真实支持的 DASH 视频轨 |

保留本项目已验证的 `voice_balance`、`cur_language`、`cur_production_type`、`client_attr` 语音／音量能力参数；没有移植 PiliPlus 的游客 `try_look`、PGC App 通道或单文件播放分支。悬停预览继续使用原 `fnval=2000` 浏览器 profile。下载仍按指定档位调用 API；共享 API 会补齐 Web 上下文，但最高档发现／补取属于主播放仓储。

所有 API 调用继续使用原 Cookie 域规则、WBI 单飞和重签、每次读取的有界重试。首次解析和补取共用 `ApiRequests` 的 25 秒总 deadline、取消信号与账号 epoch。只有低档补取符合条件时才增加请求，不重放账户写操作。

## 验证

- [API 回归测试](../../packages/bili_api/test/play_info_codecs_test.dart)：116 档 AVC／HEVC／AV1 与 AAC、完整 Web 参数参与 WBI 签名、随机占位更新、预览 profile 隔离。
- [仓储回归测试](../../test/features/playback/api_playback_quality_test.dart)：最高档发现、三种编码下保留 116、缺档补取与菜单合并、非会员不暴露 116、补取失败保留可播源、取消／认证失效传播、跨语音防混合。
- [只读在线探针](../../tool/validation/playurl_quality_probe.dart)：默认游客；显式启用安全存储的已有会话时，只在内存恢复 Cookie，不写回会话或数据库。仅输出登录／VIP 状态、业务码、清晰度和轨道元数据，不输出凭据、URL 或响应正文。

```powershell
# 在 Windows 上使用已有普通／大会员会话读取同一视频
flutter run -d windows --target tool/validation/playurl_quality_probe.dart --dart-define=BILI_PLAYURL_USE_SESSION=true
# 替换样本可追加 --dart-define=BILI_PLAYURL_BVID=BVxxxxxxxxxx
```

Windows Debug 探针已构建并热重启，修改前后该样本的游客／普通账号均取得有效分轨；普通账号实际最高档为 80。它只验证接口及映射，未创建原生播放会话，不是解码／音画验证。

`tool/check.ps1 -SkipPub` 通过：格式、静态分析、打包边界检查，以及根应用 3949／bili_api 541／bili_player 131／bili_danmaku 153／bili_mux 5 项测试。根应用跳过 13 项；未配置 `BILI_MUX_LIBRARY`，mux 原生 10 项跳过，不计为原生集成通过。另对在线探针执行 `dart analyze` 和格式检查，新增文档相对链接及 `git diff --check` 通过。

修改后的 Windows 普通账号探针实际输出 `repositoryQuality=80 qualities=[16,32,64,80] audio=true`；请求 116 不会将未授权的 116 加入菜单。

Android arm64 mux 已按固定源码重新准备，随后 `tool/build-android-development.ps1 -Mode Release -SkipMuxBuild` 通过。普通 `lib/main.dart` 的 Release/AOT 测试 APK 为 `build/development/android-arm64/BiliSail-test-arm64-release.apk`（版本 `1.2.6+3`，versionCode `12603`），包名 `dev.bilisail.bilisail.test`、名称“BiliSail 测试版”。构建入口已校验实际身份、原有开发签名、arm64 ABI 和不可调试属性；未连接设备，未执行安装。

APK SHA-256：`1d5a1bf74be1ee733d0aa6148676d92e488fc7ff308cf42bab80251879922007`。SHA 和公开构建元信息与 APK 同目录保留，二进制不提交 Git。

Android 大会员实际 116 档、Windows 大会员实际 116 档、macOS／iOS／Linux 和长期播放待验证。

## 默认清晰度补充检查

同日继续核对设置页、播放器设置、新视频／影视 owner、DASH 选轨及 SQLite 保存恢复。与上述 PiliPlus 快照的 `video_quality.dart` 对照，现有档位的协议 ID 正确，但发现并修正：

- 默认设置漏掉 720P60（74），且 `AppSettings.normalized()` 会将已保存的 74 重置成 80；现在设置与播放器设置均可选择并保留 74。
- 播放控件缺少 HDR（125）、杜比视界（126）、8K（127）的标签，会直接显示数字。现在设置选项、有效 ID 和播放标签共享纯 Dart 的 `video_quality.dart`，避免三份列表独立维护。
- SQLite 读取默认画质时会将 `116.5` 等异常小数截断成有效 ID。现在只接受整数 ID，其余非法值沿用 80 的回退，与直播默认画质的读取约束一致。

检查后的默认选项为：16=360P、32=480P、64=720P、74=720P60、80=1080P、112=1080P+、116=1080P60、120=4K、125=HDR、126=杜比视界、127=8K。产品默认仍为 80；保留其余有效旧值，无数据库表或 JSON 字段变更，无需升级 schema。视频默认值不提供 0 自动档；直播 0 自动档仍独立保存和应用。

默认画质用于新的点播／影视 owner，已有播放页保留当前选择；选轨继续使用真实 DASH，优先所选档位，再选择编码，缺档时选择不高于目标的最高可用档（全部更高时取最低档）。HDR／杜比／8K 的实际权限、片源及解码仍由接口轨道与平台能力决定，不将设置选项等同于播放验收。

新增／扩展测试覆盖全部 11 档的归一化、保存恢复、新视频和影视默认值传递、精确选轨及缺档回退，并实际操作设置页与播放器设置中的 720P60。标签回归覆盖 HDR／杜比／8K。定向设置与标签／选轨测试 130 项通过；`tool/check.ps1 -SkipPub` 全量通过，mux 原生 10 项因未配置 `BILI_MUX_LIBRARY` 跳过。Windows 只读探针重新构建及热重启通过。

本轮为 Dart 设置与标签修正，未更新前述 `0e962d9` 对应的 Android APK；Android 安装操作及大会员高画质原生实播仍未验证。
