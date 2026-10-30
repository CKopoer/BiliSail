# 应用图标切换

日期：2026-10-30。

## 行为与边界

设置外观分类仅提供“哔帆”和“粉红小电视”，默认哔帆，不提供蓝色选项或蓝色素材。小电视使用独立 [SVG](../../assets/branding/bilibili_source.svg) 与 [1254px 渲染图](../../assets/branding/bilibili_pink.png)，来源、摘要和权利边界见[品牌说明](../../assets/branding/README.md#可选图标2026-10-30)。

| 平台 | 生效范围 | 保留的安装资源 |
| --- | --- | --- |
| Android | 两个 activity-alias 的桌面启动图标；API 33 起原子切换，旧系统先启用目标再禁用旧别名，主 Activity 不禁用 | 包管理器中的应用图标、旧手动固定入口可能仍使用安装图标；桌面可能延迟刷新 |
| iOS/iPadOS | 通过 `setAlternateIconName` 切换主屏幕图标，Xcode 为 iPhone/iPad 打包备用图标 | 系统负责提示及刷新 |
| Windows | 运行中的窗口图标，新播放窗口沿用；播放窗返回按钮保留 | EXE、MSIX、安装包、已有快捷方式及固定任务栏图标 |
| macOS | 运行中的 Dock 图标，启动后重新应用 | 应用 bundle、访达、启动台 |
| Linux | GTK 窗口图标与随后新建窗口的默认图标 | 应用菜单与 `.desktop` 图标；Wayland/桌面环境可忽略窗口图标 |

不修改已安装二进制、应用 bundle 或用户快捷方式。沿用根应用 MethodChannel，未增加 Pub 依赖，四个独立包不感知业务图标。

纯 Dart 契约为 `lib/domain/app_icon.dart`，平台适配为 `lib/core/platform/app_icon_service.dart`，由 app 组合根注入设置控制器。`AppSettings.appIcon` 存入 `preferences.v1`，快照 schema 递增到 34，SQLite 表结构及数据库版本保持不变。缺失/非法值回退哔帆，恢复默认也恢复图标。

图标变更串行完成系统应用与设置保存后才发布选中值；失败时尝试恢复原生图标，后续主题等设置写入只合并已提交的图标，避免重新写入失败选择。移动端启动读取操作系统实际保留的选择并同步快照，避免 iOS 重复改图标提示，也修复原生完成而 SQLite 提交中断的状态；桌面启动按保存值重新应用。图标恢复失败保留其他设置并在选项中提示重试。

Android 正式包与 `.test` 开发包使用各自 packageName，别名类名固定在生产 namespace；不访问其他包。首次从旧版本升级时，桌面对旧 MainActivity 固定入口的处理及位置保留需实机验收。

## 验证

- `uv run --with pillow==12.3.0 python tool/check_app_icons.py` 通过：共 70 项资源检查，包含两套 Android 五密度、两套 ICO 的 16/24/32/48/64/128/256px、两套 iPhone/iPad 全部声明尺寸，以及默认 macOS 七尺寸和 Linux 256px；PNG 像素与源图缩放一致，iOS 为白底不透明 RGB。运行时两张原图均为 1254px RGBA。蓝色文件已移除。
- `tool/check.ps1 -SkipPub` 通过：格式、静态分析、打包边界脚本；根应用 3633 项通过、13 项因 Windows 符号链接权限跳过；`bili_api` 496、`bili_player` 99、`bili_danmaku` 118、`bili_mux` 5 项通过。mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。
- 新增 11 项定向测试覆盖旧快照和非法值、系统保留状态恢复、图标初始化失败隔离、原生切换失败、保存失败回退、并发主题保存与恢复默认；原生通道测试覆盖五个平台的方法和图像参数。
- Windows Debug 构建、`flutter test integration_test/desktop_app_icon_test.dart -d windows` 通过：点击粉红小电视、原生调用、数据库持久化、控制器重新加载及恢复默认；测试数据库使用内存，不写用户设置。普通 `lib/main.dart` 入口重新构建启动、热重载成功，未发现运行时错误。
- Android arm64 开发 Release 构建通过，产物为 `build/development/android-arm64/BiliSail-test-arm64-release.apk`（普通 `lib/main.dart`、AOT、`dev.bilisail.bilisail.test`、BiliSail 测试版、不可调试、本机开发签名），脚本已核验包名、版本、签名及 SHA-256，未连接设备、未安装。首次构建期间同时进行 Windows Debug 构建，触发 dev-only `integration_test` 插件注册干扰；随后顺序执行 `tool/build-android-development.ps1 -Mode Release -SkipMuxBuild`，由 Flutter 自身重新生成注册文件后通过，未手改生成物。Android mux 资产已由本轮第一次构建脚本准备。
- 已检查相关文档的 206 个本地链接与 `git diff --check`。
- 对最终开发 Release APK 另用 `aapt dump xmltree/resources` 检查两个别名、默认启用状态和目标 Activity；从 APK 解码两套共 10 张原生图标，48/72/96/144/192px 均保留，alpha 与浅/深背景上的可见像素均与各自源图缩放一致（打包工具会归零少数全透明像素的隐藏 RGB），确认资源压缩没有移除备选尺寸。

未验证：Android 实机桌面切换、旧版覆盖升级后的固定图标和位置；iPhone/iPad、macOS、Linux 的原生构建与设备显示；Windows 固定任务栏/桌面快捷方式缓存和跨 DPI 显示。Windows 集成测试证明原生调用和选择状态闭环，不能代替各系统 Shell 视觉验收。没有修改播放输出或测量播放性能。
