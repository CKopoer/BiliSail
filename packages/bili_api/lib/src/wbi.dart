import 'dart:convert';

import 'package:crypto/crypto.dart';

final class WbiSigner {
  const WbiSigner(this.mixinKey);
  final String mixinKey;

  static const _table = <int>[
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
    37,
    48,
    7,
    16,
    24,
    55,
    40,
    61,
    26,
    17,
    0,
    1,
    60,
    51,
    30,
    4,
    22,
    25,
    54,
    21,
    56,
    59,
    6,
    63,
    57,
    62,
    11,
    36,
    20,
    34,
    44,
    52,
  ];

  static WbiSigner fromUrls(String imgUrl, String subUrl) {
    String stem(String value) {
      final path = Uri.parse(value).pathSegments.last;
      return path.split('.').first;
    }

    final combined = stem(imgUrl) + stem(subUrl);
    if (combined.length < 64) throw const FormatException('Invalid WBI key');
    return WbiSigner(_table.map((i) => combined[i]).join().substring(0, 32));
  }

  Map<String, String> sign(Map<String, String> parameters, DateTime time) {
    final output = <String, String>{
      ...parameters,
      'wts': (time.toUtc().millisecondsSinceEpoch ~/ 1000).toString(),
    };
    final keys = output.keys.toList()..sort();
    final query = keys
        .map((key) {
          final value = output[key]!.replaceAll(RegExp(r"[!'()*]"), '');
          return '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}';
        })
        .join('&');
    output['w_rid'] = md5.convert(utf8.encode(query + mixinKey)).toString();
    return output;
  }
}
