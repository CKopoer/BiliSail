# Optional fvp / MDK playback backend

fvp is copyright Wang Bin, licensed under BSD-3-Clause. Its unmodified license
is included as LICENSE-fvp.txt. Source:
https://github.com/wang-bin/fvp/tree/e81637411c58a9ae28de246ee73ad06e3418f10e

MDK SDK version 0.39.0 is copyright Wang Bin. The upstream author permits free
use, including commercial use, through Flutter's fvp plugin, which installs the
bundled Flutter key. The SDK has its own license; the upstream license text is
preserved in mdk.podspec. Binary sources and archive hashes: assets.lock.json.
https://github.com/wang-bin/mdk-sdk/tree/v0.39.0

The Windows SDK's ffmpeg-9.dll reports LGPL version 2.1 or later and version
git-2026-09-17-590fb40-avbuild. Corresponding FFmpeg source:
https://github.com/wang-bin/FFmpeg/tree/590fb407b09bbf19aac0ea2fbd0ba16f93494601
Build scripts and upstream binary distribution:
https://github.com/wang-bin/avbuild
https://sourceforge.net/projects/avbuild/files/windows-desktop/
The LGPL 2.1 license is included in the application's assets as
packages/bili_mux/LICENSE-FFmpeg.txt, independently of the mux library's source.

libass is copyright the libass contributors, under the ISC license:
https://github.com/libass/libass/blob/master/COPYING
FFmpeg, libass and other bundled dependencies retain their separate licenses.
The fvp plugin's BSD license does not replace those licenses.

The experimental backend retains the original SDK bytes. It does not include
the SDK's optional BRAW, R3D or nvJPEG2000 decoder plugins in Windows/Linux bundles.
