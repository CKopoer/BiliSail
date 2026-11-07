// Copyright (c) 2026 BiliSail contributors. All rights reserved.
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    await CBuilder.library(
      name: 'bili_fvp_audio_activity',
      assetName: 'src/third_party/fvp_audio_activity.g.dart',
      sources: ['src/fvp_audio_activity.cpp'],
      includes: ['src', 'third_party/mdk'],
      language: Language.cpp,
      std: 'c++17',
    ).run(input: input, output: output);
  });
}
