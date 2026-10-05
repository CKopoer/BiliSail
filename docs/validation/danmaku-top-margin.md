# 弹幕顶部距离

日期：2026-10-06。在现有工程上增量增加配置，保留已有修改。

## 行为与存储

- 应用设置的“弹幕”和播放器“弹幕配置”均提供“顶部距离”滑条，默认 0，范围 0–200，步长 4；单位为 Flutter 逻辑像素。两个入口保存同一个 `danmakuTopMargin` 偏好。
- 普通视频、影视和直播共用这个配置。滚动和顶部固定弹幕从配置距离开始分配轨道；底部固定弹幕按剩余绘制区域的下沿定位。先扣除顶部距离和底部避让，再应用显示区域比例；距离大于当前可用高度时限制到有效高度，无可用轨道则跳过弹幕，恢复大窗口后使用保存的距离。
- 设置快照版本由 7 升为 8，旧快照缺少新字段时使用 0，原有设置保留；负值、超范围和非有限值经过归一化。没有 SQLite 表结构变化，不改变数据库版本或清空用户数据。
- 顶部距离设置更新沿用现有弹幕配置重布局流程；不重开媒体源、不创建第二个视频 surface。默认 0 保持原有弹幕区域计算。

## 来源与采用边界

只读参考相邻 `biliuwp-lite` 提交 `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0` 中的 [全局弹幕设置](../../../biliuwp-lite/src/BiliLite.UWP/Controls/Settings/VideoDanmakuSettingsControl.xaml)、[播放器滑条](../../../biliuwp-lite/src/BiliLite.UWP/Controls/PlayerControl.xaml)、[NS 弹幕适配器](../../../biliuwp-lite/src/BiliLite.UWP/Services/NsDanmakuController.cs) 和 [寒霜弹幕适配器](../../../biliuwp-lite/src/BiliLite.UWP/Services/FrostMasterDanmakuController.cs)。参考默认值、播放器的 0–200／步长 4，以及顶部边距缩小画布的交互语义；独立编写 Dart／Flutter，没有复制 C#／XAML 源码、schema 或资源，不增加相邻仓库运行时依赖。采用限制沿用 [参考文档](../references.md)。

## 验证

- 离线用例覆盖默认值／复制／非法值、版本 7 快照兼容与保存后重载、两个入口的真实滑条拖动和播放器弹窗重开、点播／直播配置更新，以及滚动／顶部／底部弹幕坐标、短视口无可用轨道和视口恢复。
- `tool/check.ps1 -SkipPub` 通过：根应用 543、`bili_api` 183、`bili_player` 16、`bili_danmaku` 14 项，共 756 项；四处格式检查与静态分析通过。日志：`artifacts/danmaku-top-margin-check.log`。
- 新增文档及索引／参考文档的相对链接检查、`git diff --check` 通过。
- 本轮未修改原生播放器后端；未重新构建安装包或进行 Windows／Android／macOS 实机界面验证，没有测量性能。
