import 'package:flutter/services.dart';

Future<void> loadDouyinSansTestFont() =>
    (FontLoader('Douyin Sans')..addFont(
          rootBundle.load('assets/fonts/douyin_sans/DouyinSansBold.ttf'),
        ))
        .load();
