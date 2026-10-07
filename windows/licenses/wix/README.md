# WiX 安装器许可来源

固定版本：WiX Toolset / BootstrapperApplications 6.0.2，源码提交 `b3f340393117094a75ea8ced77f2357e4aa095e7`。这里只保留上游未修改的许可文件；打包脚本将本目录复制到 Windows 应用的 `data/licenses/wix`。

| 文件 | 上游来源 | SHA-256 |
| --- | --- | --- |
| [LICENSE.TXT](LICENSE.TXT) | [MS-RL 与版权通知](https://github.com/wixtoolset/wix/blob/b3f340393117094a75ea8ced77f2357e4aa095e7/LICENSE.TXT) | `dfdf2048787635215a6baf3b9d461dee89a2904d246787258a44f072a98d4786` |
| [OSMFEULA.txt](OSMFEULA.txt) | [二进制 Maintenance Fee 条款](https://github.com/wixtoolset/wix/blob/b3f340393117094a75ea8ced77f2357e4aa095e7/OSMFEULA.txt) | `a992056365937ddea181a39c8204dfdc0ae664be356a00a0746df79d7b64283e` |

CLI 由 NuGet 官方源的 `wix 6.0.2` 安装，原生 Burn UI 由同版本 `WixToolset.BootstrapperApplications.wixext` 提供。没有修改或复制上游安装器源码，没有使用商业扩展；完整使用与发行边界见 [第三方说明](../../../THIRD_PARTY_NOTICES.md) 和 [CI/CD 记录](../../../docs/validation/ci-cd.md#windows-msi-与-exe)。
