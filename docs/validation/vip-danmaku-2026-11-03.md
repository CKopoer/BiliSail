# 会员彩色弹幕显示与发送（#35）

日期：2026-11-03。对应 [Issue #35](https://github.com/CKopoer/BiliSail/issues/35)。

## 来源与边界

只读核对相邻 PiliPlus 提交 `265f879fa85973b4bf885bde2562f1007f1013b8` 的发送面板、`http/danmaku.dart`、弹幕视图及 `showVipDanmaku` 设置；其 GPLv3 应用代码仅作为交互和协议参考，本次按 BiliSail 的 Repository、会话、设置及渲染边界独立实现，没有复制应用代码或修改相邻仓库。

两项目均锁定 `bggRGjQaUbCoE/canvas_danmaku@275046d8647a6a26cba1d0dadb9e28688cb3dbf1`。渐变外观依据该 MIT 依赖的 [recordDanmakuImage](https://github.com/bggRGjQaUbCoE/canvas_danmaku/blob/275046d8647a6a26cba1d0dadb9e28688cb3dbf1/lib/utils/utils.dart)：白色字面、粉色 `F2509E` 到蓝色 `308BCD` 的描边。没有新增或更新依赖；保留依赖原有许可。普通单色发送仍支持完整 24 位 RGB。

## 实现

- 解码 `DanmakuElem` 的字段 24 `colorful`，保留未知整数值；当前只把 `60001` 映射为会员渐变。缺失或未知效果按普通 RGB 显示，不丢弃正文。
- `ApiDanmakuItem → TimedComment → DanmakuEvent` 保留样式，覆盖 UGC／PGC、滚动／顶部／底部、普通／全屏及成功发送回显。下载 extras 保存布尔标记；旧 extras 缺失时默认普通样式，无需清空或重下已有媒体。
- 继续使用单一弹幕时钟和有界文字／图像缓存。缓存键、可见图像保护键、活动事件比较和固定层重绘版本均包含渐变标记。描边 shader 随文字布局创建，图像只在首次绘制或 DPR／样式变化时重建；直接文字降级也保留效果，没有增加逐帧 Widget 或动画时钟。
- 渐变描边在阴影／描边／无效果三种全局文字样式下均可见；普通 RGB 的既有表现保持不变。共享设置新增默认开启的“显示会员彩色弹幕”，关闭时按底色显示；既有“屏蔽彩色弹幕”也会过滤底色为白色的会员弹幕。开关立即作用于当前窗口。
- 共享发送面板新增会员色块、预览及选中标记。普通账号的入口禁用；从已保存会员样式切回普通颜色后清除会员标记。账号失去权益时保留全局偏好，但阻止会员发送并保留草稿。
- `/x/web-interface/nav` 的 `vipStatus`（缺失时兼容 `vip.status`）映射为会话内已验证会员状态。离线恢复不假定会员权益，退出清除状态；没有把会员身份存入普通设置。显示他人会员弹幕不要求观看者拥有会员。
- 发送前重新检查当前账号权益，再沿用既有账号 epoch／源 generation／取消隔离和单次写路径。`/x/v2/dm/post` 的会员请求带 `color=16777215`、`colorful=60001`；普通请求不带 `colorful`。最终授权和可见性由服务端决定，失败／未知结果不回显、不自动重发。
- 全局发送样式在原 `mode/color` 上增加 `colorful`，与原 RGB 一次保存；偏好快照版本 35 → 36，新增 `danmakuSendColorful=false` 和 `danmakuShowVip=true`，保留已有合法模式、色值及其他设置。SQLite 表结构仍为版本 3。

## 验证

离线协议测试覆盖字段 24 的缺失／会员／未知值、三种模式的发送表单以及会员状态解析。像素回归覆盖三种文字效果、DPR 1／2、缓存图像／直接文字降级，确认同时存在粉蓝描边和白色字面；重复绘制不重复生成图像，普通／会员相同文本使用独立缓存。

应用回归覆盖共享面板选择／重开／回到 RGB、普通账号拦截、UGC／PGC 参数及成功回显、权益变化期间的旧响应隔离、即时显示开关／彩色过滤、旧设置迁移／重载／恢复默认和离线 extras 读写。检查与 Windows 合成预览日志保存在 `build/issue35/`。

- 最终应用定向回归：461 项通过、12 项既有条件跳过，日志 `final-targeted.log`。根应用 `flutter analyze --no-pub` 无问题；本任务涉及的 45 个 Dart 文件格式检查通过。文档相对链接和 `git diff --check` 通过。
- `tool/check.ps1 -SkipPub -Stage PackageTests`：API 547、播放器 142、弹幕 161、mux 5 项通过。未配置 `BILI_MUX_LIBRARY`，10 项 mux 原生测试跳过，不能算原生封装验收。
- Windows Debug 合成预览实际检查深浅背景、会员描边与发送样式预览；热重载成功，无运行时错误，截图 `vip-preview.png`。预览退出后恢复普通 `lib/main.dart` 入口，Debug 构建通过，日志 `windows-main-build-verbose.log`。
- 全仓检查受同期其他修改影响，没有宣称全绿。`tool/check.ps1 -SkipPub` 已通过打包边界脚本，但在 `window_service.dart`、`video_card.dart`、`video_card_menu_test.dart` 的格式检查停止；未为此修改这些文件。另跑全仓 RootTests 的记录为 4074 项通过、13 项跳过、5 项失败：独立播放窗口四项生命周期测试，以及 `workspace visibility updates player navigation inline and fullscreen without reopening` 的返回按钮断言。它们对应同期窗口／导航改动；完整现场保留在 `check.log` 和 `root-check.log`。

未用真实账号发送弹幕；服务端大会员权益校验、审核后的公开可见性，以及 Android／Apple／Linux 原生设备效果仍待实际账号与设备验收。离线测试与合成预览不作为这些验收的替代。
