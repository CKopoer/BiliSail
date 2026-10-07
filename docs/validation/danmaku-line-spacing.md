# 弹幕行距设置

日期：2026-10-07。

## 行距语义与默认行为

行距表示上一行文字底部与下一行文字顶部之间的空白，单位为 Flutter 逻辑像素。范围为 0–100，默认 5，步长 1；0 表示两行文字布局紧挨着。设置适用于点播、影视、离线点播和直播的滚动／顶部／底部弹幕。

两处设置入口直接显示“弹幕行距”滑块，不提供单独的默认行距开关。按用户指定，将默认行距设为 5 逻辑像素；轨道高度为 `最大文字布局高度 + 设置行距`，不再强制原实现的 48 像素轨道高度或 4 像素留白。点播取当前有界事件窗口的最大文字高度；直播沿用当前配置期间已接收文字的最大高度。

字号增大时轨道随测量文字高度增大；不同字号共享轨道时，较矮文字保留额外空白，以保证较高文字不重叠。

## 接入与保存

- 全局弹幕设置与播放器弹幕设置复用 [共享控件](../../lib/shared/ui/danmaku_settings_controls.dart)。配置变化更新弹幕布局，不重新打开媒体源。
- [AppSettings](../../lib/features/settings/domain/app_settings.dart) 的 `danmakuLineSpacing` 为非空数值，默认 5；非法范围归一化，非有限值恢复为 5。
- [设置仓储](../../lib/features/settings/data/sqlite_settings_repository.dart) 将 `preferences.v1` JSON 快照版本从 14 升至 15。旧快照缺少字段、值为 `null` 或字段类型错误时使用 5，保留已保存的有效数值（包括 0）及其他偏好；SQLite 表结构和数据库版本不变。
- [点播控制器](../../packages/bili_danmaku/lib/src/danmaku_controller.dart) 与 [直播控制器](../../packages/bili_danmaku/lib/src/live_danmaku_controller.dart) 各自接收配置，时钟、容量限制、顶部距离和底部避让沿用现有规则。

## 验证

行为测试覆盖三种弹幕模式、12／24／54 字号、默认 5、零行距、非零行距、轨道容量及非法值。根应用测试覆盖两处设置入口直接显示默认滑块、滑动保存与重载、旧快照升级、零值与默认值分别落盘，以及点播和直播桥接。

默认值调整后，两处设置入口、设置仓储和点播／直播桥接的 94 项针对性回归通过；本次涉及的 7 组源码与测试路径单独静态分析通过。`bili_danmaku` 的格式、静态分析和 52 项测试通过，`bili_player` 的格式、静态分析和 22 项测试通过；`bili_api` 格式和静态分析通过。相关文档的 98 个相对文件链接与 `git diff --check` 通过，四份 lockfile 未产生差异。

`tool/check.ps1 -SkipPub` 在根静态分析阶段遇到并行新增的 `test/app/home_startup_test.dart:14` 未使用导入警告，因此未全绿，日志位于 `artifacts/danmaku-line-spacing-check.log`。另行执行完整根测试，1117 项通过、1 项失败：`video_grid_test.dart` 的 `card highlights title and author independently and supports keyboard activation`；该用例随后单独复跑通过。完整根测试日志为 `artifacts/danmaku-line-spacing-root-test.log`。独立 API 包测试 297 项通过、1 项失败：`live_connection_info_test.dart` 的 `caller cancelling shared WBI producer permits one current-consumer retry` 出现 `wbi_key` 超时。本轮没有修改这些首页、API 或视频卡片测试及其实现。

提交前再次复核：本次文件的格式检查、7 组路径静态分析、94 项根应用针对性回归及弹幕包静态分析／52 项测试全部通过。重新执行完整脚本时，因并行新增的 `test/app/home_startup_test.dart` 未格式化而在根格式检查阶段中断；该文件不属于本次行距变更，完整检查仍未全绿。日志分别为 `artifacts/danmaku-line-spacing-precommit-check.log`、`artifacts/danmaku-line-spacing-precommit-targeted.log` 和 `artifacts/danmaku-line-spacing-precommit-package.log`。

本轮未修改原生媒体后端，未重新构建安装包；尚未进行 Windows／Android／macOS 实机界面验收或 profile 性能测量。
