# MDK 0.39 C API headers

Unmodified `include/mdk/c/{Player.h,global.h,RenderAPI.h}` from the official
[MDK v0.39.0 Windows x64 SDK](https://github.com/wang-bin/mdk-sdk/releases/tag/v0.39.0).
Archive: `mdk-sdk-windows-x64-vs2026.7z`; SHA-256:
`e492fd45f3a6828e44f75ce665708c9040abaa60602605437b71c95c714808e3`.
The same MDK 0.39 ABI is pinned for every runtime in the root
`native/fvp/assets.lock.json`.

The files retain their original copyright and permission notices. They are
covered by MDK's own SDK terms, not fvp's BSD license. The application continues
to initialize the SDK through the licensed fvp Flutter integration. The helper
uses only the public `mdkPlayerAPI::onAudio` callback and owns no MDK runtime.

Header SHA-256:

- `Player.h`: `2b24b9d3b1451090b34287f0fb338ca91fb85b01e9698706234aa65a4be1ff13`
- `global.h`: `d74e9043e49161b84e09b493aec5d2d5bf911fdc7e79be0bde68d74fcad64f16`
- `RenderAPI.h`: `05a4a9836e536a2d400e772dbeda0ba3baa6628a653c1cd0f51f5f05207b2e03`

The three-symbol Dart interface is generated from the project's own
`src/fvp_audio_activity.h` with ffigen 23.0.0:

```powershell
# Set LIBCLANG_PATH to libclang.dll if LLVM is outside its default locations.
dart run tool/ffigen.dart
```

The package build hook compiles the small C++17 helper with native_toolchain_c
0.19.5. It neither links another MDK/FFmpeg nor reads audio samples, URLs, or
headers. Decoder callbacks increment an atomic counter; Dart samples it every
250ms. Counter memory is retained until MDK's native destruction completes.
