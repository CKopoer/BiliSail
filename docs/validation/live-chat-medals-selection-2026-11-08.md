# 直播聊天牌子、等级与内容选择

日期：2026-11-08。

## 行为与边界

- 直播聊天昵称前显示粉丝牌名和牌子等级，采用服务端提供的颜色；消息提供大于零的用户直播等级时显示 `UL` 等级。缺少字段不补造等级或牌子，明确未点亮的牌子不显示。
- 长牌名允许省略，等级单独保留；内联牌子只随正文缩放一次，避免大字体重复缩放造成溢出。
- 实时消息读取 `info[0][15].user.medal`，兼容旧版 `info[3]` 牌子和 `info[4]` 等级。历史读取 `user.medal`，兼容 `medal`／`medal_info` 与 `user_level`。v2 牌子颜色的 RGBA 转为领域使用的 ARGB，非法颜色使用主题后备色。
- 牌子为可选元数据：异常值不会丢掉正常聊天，牌名最多保留 30 个 UTF-16 码元，等级只接受 0–1000 的整数，牌子等级须大于零。
- API 包解析、Repository 映射、纯 Dart 领域模型和页面展示分别负责自己的边界。历史与 WebSocket 重叠时保留已有牌子和等级；仅元数据更新也会更新原消息行，不新增重复行。
- 聊天正文使用 `SelectionArea`，桌面支持鼠标拖选和复制快捷键，移动端支持长按选择与复制菜单；保留内联表情、贴纸和昵称跳转。昵称和牌子不参与正文选择。
- 选择正文后沿用已有有界阅读快照，继续接收实时消息但暂停列表跟随；向下滚回底部后恢复跟随。聊天与快照仍保持原有 500 条容量边界。

## 只读参考与许可

PiliPlus 精确提交 `265f879fa85973b4bf885bde2562f1007f1013b8`，核对时工作区干净：

- `lib/pages/live_room/controller.dart`：实时消息的 `user.medal` 入口。
- `lib/models_new/live/live_danmaku/danmaku_msg.dart`：预取消息的 `user.medal` 入口。
- `lib/models_new/live/live_medal_wall/uinfo_medal.dart`：牌名、等级、点亮标记与 v2 颜色字段。
- `lib/pages/live_room/widgets/chat_panel.dart`、`lib/pages/member/widget/medal_widget.dart`：昵称前展示牌名和等级的职责。
- `lib/utils/color_utils.dart`：v2 牌子背景颜色的 RGBA 语义。

旧版数组字段另外核对 biliuwp-lite 提交 `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0` 的 `src/BiliLite.UWP/Modules/Live/LiveMessage.cs`。仅采用协议字段和交互职责，独立编写本项目实现；没有复制 PiliPlus 的 GPLv3 应用源码、控件或资源，没有修改相邻仓库或新增运行时依赖。

## 验证

- `flutter test --no-pub test/features/live`：122 项通过，覆盖桌面选择复制、移动长按复制、窄屏大字体、昵称跳转、元数据合并与变化通知、选择期间 500 条新消息到达后的快照保留及恢复跟随。
- `dart test test/live_packet_codec_test.dart test/content_clients_test.dart`（`packages/bili_api`）：23 项通过，覆盖新版／旧版牌子、未点亮与异常元数据、颜色转换及历史字段。
- `tool/check.ps1 -SkipPub -Stage PackageTests`：`bili_api` 718、`bili_player` 292、`bili_danmaku` 161、`bili_mux` 5 项离线测试通过；未配置 `BILI_MUX_LIBRARY`，10 项 mux 原生测试跳过，不能算作原生集成通过。
- `tool/check.ps1 -SkipPub -Stage RootTests`：4692 项通过、13 项环境条件用例跳过。最终牌子布局调整后重跑直播模块，122 项全部通过。
- `tool/check.ps1 -SkipPub -Stage Lint`：打包边界脚本、根应用和四包格式检查、全仓分析及 Linux 适配器分析通过；文档新增链接目标存在，`git diff --check` 通过。
- 按用户要求未构建应用、未安装或进行实机测试。没有正在运行的 Dart/Flutter 调试进程或 DTD，未执行热重载。在线协议及 Android／Windows／macOS 实际选择手感和展示由后续构建验收。
