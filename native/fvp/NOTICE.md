# Optional fvp / MDK playback backend

fvp is copyright Wang Bin, licensed under BSD-3-Clause. Its unmodified license
is included as LICENSE-fvp.txt. Source:
https://github.com/wang-bin/fvp/tree/e81637411c58a9ae28de246ee73ad06e3418f10e

The Windows build uses a SHA-256-verified build-tree replacement of TexturePlayer
from windows/patches/fvp. It publishes completed immutable D3D11 snapshots using
the MIT-licensed helper in the pinned CKopoer/media-kit fork. Upstream source and
licenses are preserved; the Pub cache and MDK SDK binaries are not modified.

The CocoaPods build stages a verified copy of the same pinned Apple plugin in
build/apple-plugins and replaces MetalTexture using native/fvp/apple. It publishes
write-once IOSurfaces only after Metal command completion. The original BSD
license, MDK command queue and fixed SDK binaries are preserved.

MDK SDK versions 0.39.0 and 0.40.1 (Windows ARM64) are copyright Wang Bin.
The upstream author permits free
use, including commercial use, through Flutter's fvp plugin, which installs the
bundled Flutter key. The SDK has its own license; the upstream license text is
preserved in mdk.podspec. Binary sources and archive hashes: assets.lock.json.
https://github.com/wang-bin/mdk-sdk/tree/v0.39.0
https://github.com/wang-bin/mdk-sdk/tree/v0.40.1

Windows ARM64 uses the official complete vs2026 SDK from v0.40.1, which includes
bin/arm64 and lib/arm64. Its per-platform version, release URL and archive hash
override the 0.39.0 defaults in assets.lock.json. The refreshed SDK replaces the
expired 0.39.0 build reported in issue #100; the plugin's bundled Flutter key and
SDK license checks are preserved. SDK revisions use separate build directories.

The Windows SDK's ffmpeg-9.dll reports LGPL version 2.1 or later. The x64 SDK
reports version git-2026-09-17-590fb40-avbuild. Corresponding FFmpeg source:
https://github.com/wang-bin/FFmpeg/tree/590fb407b09bbf19aac0ea2fbd0ba16f93494601
The updated ARM64 SDK reports git-2026-10-25-464fc8c-avbuild. Corresponding source:
https://github.com/wang-bin/FFmpeg/tree/464fc8c2ed53648b9ede81555921e3995d32bbe5
Build scripts and upstream binary distribution:
https://github.com/wang-bin/avbuild
https://sourceforge.net/projects/avbuild/files/windows-desktop/
The LGPL 2.1 license is included in the application's assets as
packages/bili_mux/LICENSE-FFmpeg.txt, independently of the mux library's source.

libass is copyright the libass contributors, under the ISC license:
https://github.com/libass/libass/blob/master/COPYING
FFmpeg, libass and other bundled dependencies retain their separate licenses.
The fvp plugin's BSD license does not replace those licenses.

The project's audio activity observer compiles against the unmodified public
MDK 0.39 C headers Player.h, global.h and RenderAPI.h. Source and exact header
hashes are recorded in packages/bili_player/third_party/mdk/SOURCE.md.
The headers carry this notice (Player.h and global.h also state "AI participated"):

Copyright (c) 2019-2026 WangBin <wbsecg1 at gmail.com>
This file is part of MDK
MDK SDK: https://github.com/wang-bin/mdk-sdk
Free for opensource softwares or non-commercial use.

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

The experimental backend retains the original SDK bytes. It does not include
the SDK's optional BRAW, R3D or nvJPEG2000 decoder plugins in Windows/Linux bundles.
