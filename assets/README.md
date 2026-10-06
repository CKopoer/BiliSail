# 本地视觉资源来源

## HarmonyOS Sans

按用户指定，从 `C:\Users\14562\Desktop\HarmonyOS+Sans\HarmonyOS Sans\HarmonyOS_Sans_SC` 采用 `HarmonyOS_Sans_SC_Regular.ttf`、`HarmonyOS_Sans_SC_Medium.ttf`、`HarmonyOS_Sans_SC_Bold.ttf`，版本均为 1.0，分别注册 400、500、700 字重，应用字体族名为 `HarmonyOS Sans`。简体中文版本已核对中英文界面示例字符无缺字；字体文件原样复制，不做裁剪或修改。

文件位于 `fonts/harmonyos_sans/`，SHA-256 见 [字体来源哈希](fonts/harmonyos_sans/source_hashes.json)。同目录的 [原始许可证](fonts/harmonyos_sans/LICENSE.txt) 原样保留并打包，许可证原文件包含尾部 NUL 填充，应用的许可证页仅在展示时移除该填充。设置的“外观”显示字体名称，“关于”不展示字体介绍，其许可证页提供完整协议。来源许可为随资源提供的 HarmonyOS Sans Fonts License Agreement，Copyright 2021 Huawei Device Co., Ltd.；字体不作为独立字体软件分发。

## 阿里巴巴普惠体 3.0

按用户指定，从 `C:\Users\14562\Desktop\AlibabaPuHuiTi-3\AlibabaPuHuiTi-3` 采用 Regular、Medium、SemiBold、Bold 的原始 TTF，分别注册 400、500、600、700 字重。四个文件的内部版本均为 3.01，应用字体族名为 `Alibaba PuHuiTi 3.0`，文件位于 `fonts/alibaba_puhuiti/`，未转换、裁剪或修改；这四份资源共约 32.1 MiB。版本、字重与本轮中英文预览字符 cmap 均已核对。

SHA-256 见 [来源哈希](fonts/alibaba_puhuiti/source_hashes.json)。用户目录未附法律声明，2026-10-06 从 [字体官网](https://www.alibabafonts.com/) 指向的 [普惠体 3.0 官方法律声明](https://www.yuque.com/yiguang-wkqc2/hgpff0/nus9wiinq4aeiegy) 获取，完整保留中英文两个标题和各六条正文，仅去除 HTML 展示标签，存为 [LICENSE.txt](fonts/alibaba_puhuiti/LICENSE.txt)，随应用打包并登记到 Flutter 许可证页。

版权为 Alibaba (China) Co., Ltd.，许可范围遵循该声明的免费商业/非商业使用及限制：不修改字体、不删改法律声明、不将字体单独定价销售、不声称与阿里巴巴存在合作、赞助或背书。字体仅作为应用文字资源使用。本应用是独立第三方客户端，与阿里巴巴无上述关系。

已安装系统字体只保存字体族名称，由系统文字渲染器访问，不复制字体文件、不作为应用资源分发。

## UWP 图标

按用户明确要求从本机 `../biliuwp-lite` 采用视觉资源。来源提交：`baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0`。相邻仓库保持只读，无运行时依赖。

| 本项目路径 | 上游路径（仓库根相对） | 用途 |
| --- | --- | --- |
| `fonts/biliicon.ttf` | `src/BiliLite.UWP/Assets/Fonts/biliicon/iconfont.ttf` | B 站业务图标字体 |
| `fonts/iconfont.json` | `src/BiliLite.UWP/Assets/Fonts/biliicon/iconfont.json` | 原始名称、codepoint 对照，不打包为运行时资源 |
| `icons/lv0.png` 至 `lv6.png` | `src/BiliLite.UWP/Assets/Icon/lv0.png` 至 `lv6.png` | 用户等级 |
| `icons/verify0.png`、`verify1.png`、`up.png` | `src/BiliLite.UWP/Assets/Icon/` 下同名文件 | 认证与 UP 主标记 |
| `branding/app_icon.png` | `src/BiliLite.UWP/Assets/Square44x44Logo.targetsize-256.png` | 启动图标原图 |

上述直接复制文件的 SHA-256 记录在 [source_hashes.json](source_hashes.json)。Windows ICO、Android 各密度 PNG 和 macOS AppIcon PNG 由原图等比缩放生成；复现命令：`uv run --with pillow python tool/generate_uwp_icons.py`。生成工具仅为开发工具，不新增应用运行依赖。

字体的全部 99 个映射已核对 cmap 并渲染检查。应用只命名采用需要的 glyph；字体没有明确对应的通用操作继续使用 Material 图标。

在本地参考仓库未找到明确覆盖这些字体、图片、标识的 LICENSE。用户要求允许本次本机预览采用，但不构成上游授予开源/再分发许可。对外发布前需核实各资源权利及品牌使用范围或替换为已获许可素材；本文件不宣称许可审查已经完成。
