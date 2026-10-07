# BiliSail（哔帆）应用图标

设计日期：2026-10-07。用户要求结合 BiliSail 名称与 B 站图标，重新设计原先复用的 UWP 启动图标。

## 设计与文件

当前采用第二轮 C「船帆角标」。以 B 站小电视为主体，保留粉色圆角外框、双天线、斜眼与嘴形，右下角加入小型蓝色船帆。屏幕内部为白色，外围透明；小电视在小尺寸下保持主要辨识度。2026-10-07 按用户选择设为应用图标，同日按要求在原画布中心等比放大主体 10%，保留造型和全部平台输出尺寸；根 README 顶部继续以 144 × 144 展示当前图稿。

- [app_icon.png](app_icon.png)：主体放大 10% 后的图稿，仍为 1254 × 1254，RGBA；透明边角与内部空隙。
- [icon_preview.png](icon_preview.png)：16、24、32、48、64、128 px 在浅色、深色背景上的预览。
- [icon_scale_comparison.png](icon_scale_comparison.png)：24、30、36、48、64 px 的放大前后对比，上行原图、下行放大 10%；浅色／深色背景上的图标按实际像素尺寸展示。
- [第二轮三个方案](candidates-v2/README.md)：A、B、C 原图及并排预览全部保留；放大前图稿保存在 [C 原图](candidates-v2/c-sail-corner.png)，原多尺寸预览保存在 [icon_preview_v2.png](icon_preview_v2.png)。
- [app_icon_v1.png](app_icon_v1.png) 与 [icon_preview_v1.png](icon_preview_v1.png)：保留第一版帆船图标与预览，生成提示词见下文历史记录。
- [生成脚本](../../tool/generate_app_icons.py)：Android 五种密度、Windows 七种 ICO 尺寸、macOS 七种 AppIcon 尺寸。
- [主体缩放脚本](../../tool/scale_app_icon.ps1)：从保留的 C 原图重建当前图稿，固定 1.10 倍，不会重复放大当前文件。

当前图稿 SHA-256：`8bfa0684f99c9a530abf155f480e4ca1ef1c7a57b7c7c463f602980397b5d3e9`。

放大前 C 原图 SHA-256：`9afcde924a2464fbfe0664b4a5d3e6d9eb32d98447da562c59d94a2239d39df8`。

第一版保留原图 SHA-256：`92011d5873166eb9e8eca38d032ff162ba95f05a103f293701e3ad8273f73df6`。

当前设计的完整提示词与编辑输入 URL 见 [第二轮 prompts.json](candidates-v2/prompts.json)中的 C 条目，使用内置 `image_gen`，透明背景参数为 `true`。主体放大时先用内置 `image_gen` 生成预览；测量结果约为 11%，且有细微重绘，因此没有采用生成预览。最终资源直接从保留的 C 原图进行几何缩放，参数、预览提示词与结果说明见 [放大记录](scale-10-percent.json)。

重建主体放大的图稿（Windows）：

```text
pwsh -NoProfile -File tool/scale_app_icon.ps1
```

画布中心为 `(627, 627)`，像素坐标按 `p' = center + 1.10 × (p - center)` 变换，使用 System.Drawing HighQualityBicubic 插值。可见轮廓按 alpha 大于 128 测量，从 1073 × 971 增至 1180 × 1068 px；边界取整产生的比例差异不足一个像素。天线、小船帆和脚部完整保留。

生成平台资源的命令：

```text
uv run --with pillow==12.3.0 python tool/generate_app_icons.py
```

该命令从保存的 PNG 等比缩放，保留 alpha；不重新调用生成服务。生成服务具有随机性，提示词用于追踪设计，不能保证重生成相同像素。没有新增应用运行依赖。

MSIX 的 `tool/build-release.ps1` 同样读取 `app_icon.png`，继续生成 targetsize、unplated、lightunplated 与 PRI。替换资源不等于系统已安装应用的图标缓存立即更新，也不代表 Android/macOS 设备显示已验收。

## 当前版验证

- 画布保持 1254 × 1254，RGBA 与透明边角保留；最终图稿通过固定 1.10 倍几何缩放生成，A、B、C 原图及第一版原图都保留在项目内。
- Android 5 个、macOS 7 个 PNG 和 Windows 7 个 ICO 尺寸已从同一原图重新生成，保留透明边角；MSIX 继续从同一路径生成普通、targetsize 和两种主题 unplated 资源。
- 根 README 顶部使用本地相对路径 `assets/branding/app_icon.png` 展示图标。
- 浅色／深色放大前后对比已生成，Windows 24 px ICO 的可见轮廓约为 23 × 20 px，放大前约为 21 × 18 px。
- 资源检查通过：1254 px 画布、1.10 倍缩放轮廓、透明边角、保留候选、12 个平台 PNG 与 7 个 ICO 尺寸及像素、资源说明中的本地链接；`tool/check.ps1 -SkipPub` 全部通过，`git diff --check` 通过。
- 系统已安装版本的图标缓存、Windows Shell、Android 真机和 macOS Dock 实际显示尚未实测；MSIX 需重新打包后安装才能检查任务栏。

## C 版放大前验证（历史记录）

- 资源检查通过：12 个平台 PNG 的像素与原图缩放一致，7 个 ICO 尺寸保留透明度；12 个原 UWP 业务资源哈希不变，264 条本地文档路径和 README 图片引用通过检查。
- `tool/check.ps1 -SkipPub` 通过：根应用 881、`bili_api` 269、`bili_player` 22、`bili_danmaku` 32 项测试全部通过，各自格式与静态分析通过；`git diff --check` 通过。
- 本轮未构建或安装应用；系统已安装版本的图标缓存、Windows Shell、Android 真机和 macOS Dock 实际显示尚未实测。

## 第一版验证（历史记录）

- Android 5 个、macOS 7 个 PNG 的尺寸与 RGBA 格式通过检查，像素与原图的 Lanczos 缩放结果一致，四角透明。
- Windows ICO 包含 16、24、32、48、64、128、256 共 7 个尺寸，保留透明度；Windows RC、Android manifest、macOS Contents.json 和 MSIX 脚本的引用已核对。
- 浅色／深色多尺寸预览已查看；12 个原 UWP 业务资源的哈希保持不变，本轮资源说明的本地链接与 `git diff --check` 通过。
- 已执行 `tool/check.ps1 -SkipPub`，在根应用格式检查阶段被其他进行中改动阻塞：`playback_session.dart`、`watch_later_queue_panel.dart` 不符合格式；未改动这些文件，后续分析／测试阶段未由该命令执行。
- 本轮未构建或安装应用；Windows Shell 的实际显示与缓存刷新、Android 真机和 macOS Dock 显示尚未实测。

## 参考来源与采用范围

以下公开素材于 2026-10-07 从官网页面定位和查看，仅作设计参考，未作为应用资源分发：

| 页面 | 素材 | 用途 |
| --- | --- | --- |
| [Bilibili 官网](https://www.bilibili.com/) | [首页 apple-touch-icon](https://i0.hdslb.com/bfs/static/jinkela/long/images/512.png) | 粉色、小电视轮廓的视觉参考 |
| [官方下载中心](https://app.bilibili.com/) | [页面小电视图标](https://i0.hdslb.com/bfs/activity-plat/static/20220518/49ddaeaba3a23f61a6d2695de40d45f0/2nqyzFm9He.jpeg) | 蓝色、倾斜双眼和圆角比例的视觉参考 |

第一版图稿使用内置 `image_gen` 生成并精修；第二轮以官方下载中心小电视为编辑输入，保留主要造型并加入航行元素，当前采用其中的 C 版。官网输入原图未直接打包到应用。Bilibili 标识的权利归其权利人，本记录不声明品牌授权。项目是独立第三方客户端，项目整体许可证状态见 [第三方来源说明](../../THIRD_PARTY_NOTICES.md)。

## 第一版初稿提示词

```text
Use case: logo-brand.
Asset type: production application launcher icon for BiliSail (Chinese name 哔帆), a Bilibili third-party video client for Windows, Android and macOS.
Primary request: create one distinctive original sailboat emblem that combines Sail with the friendly small-TV personality of Bilibili. The official download-center mascot was inspected: a chunky rounded television body, two short tilted rectangular eyes, and antenna-like strokes. Use these only as visual inspiration, and reinterpret them as a sailboat rather than copying the official logo.
Subject and composition: a compact cheerful sailboat, upright and optically centered. A large vivid Bilibili-style pink curved triangular mainsail and a smaller cyan-blue triangular jib create a strong simple sail silhouette. Below them, the boat hull itself is a thick rounded pink trapezoid / compact TV-like hull with two bold small white tilted rectangular eyes. The hull must read as both boat and friendly video mascot, not a television pasted on a boat. A single restrained cyan-blue curved wave under the hull completes the sailing idea. Integrate the mast cleanly. Use few bold shapes and purposeful negative-space gaps that remain legible at 24 to 48 pixels. The icon occupies about 82% of the square canvas, with balanced clear margins on all four sides.
Style: premium clean flat vector-style logo, smooth precise edges, gently rounded corners, playful but polished, confident graphic silhouette. Flat solid colors: main pink #FB7299 and cyan #00AEEC, white eyes only. No gradients, no textures, no 3D, no drop shadow, no sparkle, no extra nautical decoration.
Background: genuinely transparent RGBA, no white or colored tile, no rounded-square background, no mockup, no checkerboard drawn into the picture.
Text: none. No letters, no BiliSail wordmark, no Chinese, no bilibili lettering, no watermark.
Output: one single finished icon only, square high-resolution image, no multiple variants, no presentation board.
```

## 第一版精修提示词

输入为初稿图片，保留图形身份；背景透明参数在两次调用中均为 `true`。提示词中的颜色、边距是生成目标，实际像素以保存原图为准。

```text
Use case: precise-object-edit / logo-brand. Edit target: the supplied BiliSail sailboat application icon. Keep exactly the same design identity: pink curved mainsail to the right, cyan triangular jib to the left, pink friendly boat/TV hull with two white tilted rectangular eyes, and one cyan wave underneath. Keep the same color placement and cheerful simple personality. Refine it into a crisp production flat logo.
Change only these production refinements: (1) Absolutely uniform solid pink #FB7299 and uniform solid cyan #00AEEC, pure white eyes; remove ALL shading, gradients and textures from each shape. (2) Clean the entire transparent alpha silhouette and every negative-space gap. Remove stray magenta, cyan or white specks, wisps and halos around the mast, between the sails, between the hull and the wave, and along all boundaries. Clean smooth antialiased outlines only. (3) Make the mark more compact and balanced for a square application icon: slightly shorten the upper mast/sail so the full emblem occupies roughly 80% canvas width and 80% canvas height, centered with about 10% margins. Preserve the sailboat silhouette and gently rounded thick shapes. (4) Maintain generous crisp open gaps, especially between mast and blue jib and between hull and wave; no skinny hairlines. The two white eyes should remain large and recognizable at small sizes.
Background must be truly transparent RGBA everywhere outside the solid emblem, including all negative-space holes. No tile or backdrop, no shadow, no text, no checkerboard baked into image, no additional elements. One finished square icon only.
```
