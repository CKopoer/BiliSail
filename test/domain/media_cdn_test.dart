import 'package:bilisail/domain/media_cdn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pcdn = Uri.parse('https://xy1.mcdn.bilivideo.cn:4483/v.m4s?k=test');
  final tencent = Uri.parse(
    'https://upos-sz-mirrorcos.bilivideo.com/v%2F1.m4s?k=test',
  );
  final huawei = Uri.parse(
    'https://upos-sz-mirrorhwb.bilivideo.com/v.m4s?k=test',
  );
  final alibaba = Uri.parse(
    'https://upos-sz-mirrorali.bilivideo.com/v.m4s?k=test',
  );
  final baidu = Uri.parse(
    'https://upos-sz-mirrorbd.bilivideo.com/v.m4s?k=test',
  );
  final urls = [pcdn, tencent, huawei, alibaba, baidu];

  test(
    'automatic retains API order, removes duplicates and never rewrites URLs',
    () {
      final ordered = orderMediaCdnUrls([
        ...urls,
        tencent,
      ], MediaCdnPreference.automatic);
      expect(ordered, urls);
      expect(identical(ordered[1], tencent), true);
      expect(ordered[1].toString(), tencent.toString());
      expect(() => ordered.clear(), throwsUnsupportedError);
    },
  );

  test('regular CDN preference moves PCDN behind unchanged server backups', () {
    expect(orderMediaCdnUrls(urls, MediaCdnPreference.regular), [
      tencent,
      huawei,
      alibaba,
      baidu,
      pcdn,
    ]);
  });

  for (final (preference, preferred) in [
    (MediaCdnPreference.tencent, tencent),
    (MediaCdnPreference.huawei, huawei),
    (MediaCdnPreference.alibaba, alibaba),
    (MediaCdnPreference.baidu, baidu),
  ]) {
    test('$preference prefers only a returned matching host', () {
      expect(orderMediaCdnUrls(urls, preference), [
        preferred,
        ...urls.where((url) => url != preferred),
      ]);
      expect(orderMediaCdnUrls([pcdn], preference), [pcdn]);
      final lookalike = Uri.parse(
        'https://upos-sz-mirrorcos.bilivideo.com.example.org/v.m4s',
      );
      expect(orderMediaCdnUrls([lookalike, preferred], preference), [
        preferred,
        lookalike,
      ]);
    });
  }
}
