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

  final mirrorSource = Uri.parse(
    'https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/00/01/v%2F1.m4s?token=fixture%2Bkey&x=1&x=2',
  );
  for (final option in MediaCdnPreference.values.where(
    (item) => item.host != null,
  )) {
    test('${option.name} selects a mirror and keeps the original fallback', () {
      final ordered = orderMediaCdnUrls([pcdn, mirrorSource], option);
      expect(ordered.first.host, option.host);
      expect(ordered.first.scheme, mirrorSource.scheme);
      expect(ordered.first.path, mirrorSource.path);
      expect(ordered.first.query, mirrorSource.query);
      expect(ordered, containsAll([pcdn, mirrorSource]));
      expect(orderMediaCdnUrls(ordered, option), ordered);
      final backup = backupMediaCdnUrl(ordered, option);
      expect(backup, isNot(ordered.first));
      expect(backup, isIn([pcdn, mirrorSource]));
      expect(mediaCdnProbeUrl([mirrorSource], option)?.host, option.host);
    });
  }

  test('specific mirrors do not rewrite unsupported sources or credentials', () {
    for (final source in [
      pcdn,
      Uri.parse('https://upos-sz-mirrorhw.bilivideo.com/video.m4s'),
      Uri.parse('https://upos-sz-mirrorhw.bilivideo.com:4483/upgcxcode/v.m4s'),
      Uri.parse(
        'https://user:password@upos-sz-mirrorhw.bilivideo.com/upgcxcode/v.m4s',
      ),
      Uri.parse(
        'https://upos-sz-mirrorhw.bilivideo.com.example.org/upgcxcode/v.m4s',
      ),
      Uri.parse('file:///upgcxcode/v.m4s'),
    ]) {
      expect(orderMediaCdnUrls([source], MediaCdnPreference.ali), [source]);
      expect(mediaCdnProbeUrl([source], MediaCdnPreference.ali), isNull);
    }
  });

  test(
    'a returned concrete host wins without replacing its path or signature',
    () {
      final existing = Uri.parse(
        'https://${MediaCdnPreference.ali.host}/video.m4s?key=original',
      );
      final ordered = orderMediaCdnUrls([
        mirrorSource,
        existing,
      ], MediaCdnPreference.ali);
      expect(identical(ordered.first, existing), isTrue);
      expect(ordered, [existing, mirrorSource]);
    },
  );

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

  test('automatic recovery skips another PCDN for a returned regular CDN', () {
    final edge = Uri.parse('https://node.edge.mountaintoys.cn/v.m4s?k=test');
    final backup = backupMediaCdnUrl([
      pcdn,
      pcdn,
      edge,
      tencent,
    ], MediaCdnPreference.automatic);
    expect(identical(backup, tencent), true);
    expect(backupMediaCdnUrl([pcdn, edge], MediaCdnPreference.automatic), edge);
    expect(
      backupMediaCdnUrl([pcdn, pcdn], MediaCdnPreference.automatic),
      isNull,
    );
    expect(backupMediaCdnUrl([], MediaCdnPreference.automatic), isNull);
  });

  test('explicit CDN recovery preserves vendor preference and full URI', () {
    final backup = backupMediaCdnUrl([
      alibaba,
      tencent,
      huawei,
    ], MediaCdnPreference.huawei);
    expect(identical(backup, huawei), true);
    expect(backup?.toString(), huawei.toString());
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
