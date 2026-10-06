# 普惠体与已安装字体选择

日期：2026-10-06。本轮在现有工程上增量接入字体，保留其他工作区修改。

## 范围与行为

之前界面和弹幕选项仅包含已打包的 HarmonyOS Sans 与“系统默认”，没有枚举系统字体。“系统默认”一直表示不指定字体族，由平台自行选择。

界面“外观”、设置“弹幕”和播放器“弹幕配置”现均可选择阿里巴巴普惠体 3.0。Regular/Medium/SemiBold/Bold 四个文件随应用打包，字体族 `Alibaba PuHuiTi 3.0`；运行时不依赖用户桌面目录。来源、版本、字重、SHA-256 和完整中英文法律声明见 [资源记录](../../assets/README.md#阿里巴巴普惠体-30)。

Windows/macOS 提供“选择系统字体”：弹窗支持按名称搜索、实际字体预览、当前选择标记和刷新列表。只在打开弹窗时读取列表，缓存至用户刷新；取消不会改变偏好，读取失败可重试。被卸载的已选字体保留名称，系统回退渲染，并在选择弹窗中提示重新选择。字体缺少个别汉字时仍采用平台缺字回退，不承诺所有字体均有完整中文字库。

Windows 的 `bilisail/system_fonts` MethodChannel 使用 [DirectWrite GetSystemFontCollection](https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nf-dwrite-idwritefactory-getsystemfontcollection) 读取已安装字体，优先使用 en-us 家族名；资源由 COM 智能指针管理，channel 随窗口释放。macOS 使用 [NSFontManager.availableFontFamilies](https://developer.apple.com/documentation/appkit/nsfontmanager/availablefontfamilies)。没有新运行时依赖，也不复制或分发系统字体。平台能力与 MethodChannel 位于 `core/platform`，由 `app` 注入纯 Dart 端口，界面只消费应用 Provider；调用设 5 秒超时，异常不伪装为空成功。Android 当前仅显示内置字体和系统默认，明确提示暂不提供已安装字体列表。

界面与弹幕选择独立；界面字体更新浅/深色主题，点播/影视与直播弹幕共用字体族解析。弹幕配置变化沿用原有文字布局缓存释放和会话，不重开媒体。

## 持久化

既有 `preferences.v1` 快照版本从 9 升为 10，保留 `font` / `danmakuFont` 枚举字段，增加 `systemFontFamily` / `danmakuSystemFontFamily`。旧快照缺字段时使用原来的默认值，未知枚举仍安全回退；系统字体名仅保存字符串，边界去除首尾空格，拒绝控制字符和超过 200 字符的名称。无 SQLite 表结构变化，不改变数据库版本或清空数据。

## 验证

离线测试覆盖三处入口的内置/系统字体保存、独立偏好、主题解析、搜索过滤、取消、刷新失败恢复、被卸载字体提示、原生返回值边界、旧快照兼容和 SQLite 重载。Windows 原生集成验证见 `integration_test/windows_fonts_test.dart`；它枚举本机字体并检查内置和系统字体的实际栅格差异，生成本地预览图。

- `tool/check.ps1 -SkipPub` 全部通过：根应用 617、`bili_api` 207、`bili_player` 16、`bili_danmaku` 21 项，共 861 项；四处格式与静态分析通过。日志：`artifacts/font-check.log`。最初系统字体测试使用 `testWidgets` 配合 foundation 平台覆盖，在 tearDown 前触发不变量检查；已改为初始化 binding 的普通异步测试，最终专项六项及完整检查均通过。
- `flutter test --no-pub integration_test/windows_fonts_test.dart -d windows --dart-define=FONT_PREVIEW_OUTPUT=C:/Users/14562/code/bili-lite/artifacts/fonts-preview-windows.png` 通过，原生构建成功；本机 DirectWrite 返回 273 个字体族。检查普惠体与 HarmonyOS Sans / Microsoft YaHei 的实际像素结果不同，预览图已人工检查中英文与 400/500/700 字重。日志：`artifacts/font-native-windows.log`，预览：`artifacts/fonts-preview-windows.png`。
- `flutter build windows --debug --no-pub` 再次成功，恢复普通应用入口；输出包含四个原始 TTF 和许可证，四份 TTF 与用户源文件 SHA-256 一致。日志：`artifacts/font-build-windows.log`。
- 本轮文档相对文件链接 61 项及 `git diff --check` 通过。未修改原生媒体后端；macOS/Android 的构建与实机字体视觉效果尚未验证，没有进行 profile 性能测量。

## 官方桌面客户端字重对齐

2026-10-06 按用户要求，对照本机官方 Windows 哔哩哔哩 1.13.0 的样式与字体缓存调整界面字重。参考的是 `C:\Program Files\bilibili\resources\app.asar` 中的样式，以及 `%APPDATA%\bilibili\fonts\HarmonyOS` 中的 Regular/Medium WOFF2 文件；仅核对规则与字形，没有复制或分发官方资源。两种字重各 28,928 个字符的轮廓和字宽均与项目现有 Version 1.0 TTF 一致，继续使用已有字体文件。

- 共享视频卡片标题改用 Medium 500，沿用原来的 15 逻辑像素、两行与行高；推荐、搜索、视频动态、历史、收藏、稍后再看等公共卡片同步生效。
- 小标题 `titleSmall` 与收藏夹标题统一为 500，覆盖直播卡片、个人主页横向投稿卡、播放侧栏标题等既有使用位置。
- 首页频道、搜索分类、个人主页分类的选中与未选中文字均为 500，继续由颜色和既有选中标记区分状态。
- 普通视频卡片作者、日期和统计沿用 Regular 400。评论组件有网页与客户端两套规则；继续核对客户端渲染模板后，评论用户名采用客户端规则中的 400，未沿用网页规则的 500。

界面/弹幕字体偏好、已注册字重与数据协议不变，评论之外沿用原有字号与布局。本轮为样式调整，沿用已有布局、评论、字体选择和导航测试，不新增仅复述样式实现的测试。以上是样式规则对齐，不代表 Flutter 与 Chromium 已完成像素级渲染一致性验收。

用户后续要求评论区文字一起对齐。按官方 `.reply-item-client`、`.floor-reply-item` 与 `.sub-reply-item-client` 规则，主评论及完整回复正文采用 15 逻辑像素、25 行高；楼中楼预览正文与用户名采用 14/20；主评论用户名采用 13/16.25；时间和回复入口采用 12/15，点赞计数采用 13/16。所有上述评论文字字重为 400，字间距为 0，保留用户选择的界面字体和系统文字缩放。

正文、普通用户名和元数据采用官方浅/深色 `text1`、`text2`、`text3` 色值，仅作用于评论展示；会员名和回复入口沿用应用强调色。主评论、完整楼中楼和预览共用 `CommentTextStyles`；图片预览、选择复制、徽章和用户点击入口继续沿用既有组件与行为。

本轮验证：

- 评论富文本、视频卡片、个人主页、首页布局与搜索的定向回归 52 项通过，包含窄窗口与两倍文字缩放；日志为 `build/font-weight-targeted.log`。
- `tool/check.ps1 -SkipPub` 全部通过：根应用 707、`bili_api` 227、`bili_player` 16、`bili_danmaku` 21 项，共 971 项；四处格式与静态分析通过。日志为 `build/font-weight-check.log`。
- `flutter build windows --debug --no-pub` 成功，输出 `build/windows/x64/runner/Debug/bilisail.exe`；日志为 `build/font-weight-windows-build.log`。`git diff --check` 通过。本轮未更新本机已安装的 MSIX，也未完成 Windows 实机像素对比或 Android/macOS 构建与视觉验收。
