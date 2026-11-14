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
    'automatic prefers returned regular CDNs without rewriting signed URLs',
    () {
      final ordered = orderMediaCdnUrls([
        ...urls,
        tencent,
      ], MediaCdnPreference.automatic);
      expect(ordered, [tencent, huawei, alibaba, baidu, pcdn]);
      expect(identical(ordered.first, tencent), true);
      expect(ordered.first.toString(), tencent.toString());
      expect(orderMediaCdnUrls(ordered, MediaCdnPreference.automatic), ordered);
      expect(() => ordered.clear(), throwsUnsupportedError);
    },
  );

  test('automatic keeps provided fallbacks when no regular CDN exists', () {
    final edge = Uri.parse('https://node.edge.mountaintoys.cn/v.m4s?k=test');
    final lookalike = Uri.parse(
      'https://upos-sz-mirrorcos.bilivideo.com.example.org/v.m4s',
    );
    expect(
      orderMediaCdnUrls([pcdn, edge, lookalike], MediaCdnPreference.automatic),
      [pcdn, edge, lookalike],
    );
    expect(orderMediaCdnUrls([], MediaCdnPreference.automatic), isEmpty);
  });

  test('automatic distinguishes UPOS PCDN from provided regular mirrors', () {
    final disguisedPcdn = Uri.parse(
      'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/v.m4s?os=mcdn&k=a%2Bb',
    );
    final redirectedPcdn = Uri.parse(
      'https://upos-sz-302.test.bilivideo.com/upgcxcode/v.m4s?k=302',
    );
    final overseas = Uri.parse(
      'https://upos-hz-mirrorakam.akamaized.net/upgcxcode/v.m4s?hdnts=fixture%2Bsignature',
    );
    final proxy = Uri.parse(
      'https://proxy-tf-all-ws.bilivideo.com/upgcxcode/v.m4s?k=fixture',
    );
    final ordered = orderMediaCdnUrls([
      disguisedPcdn,
      redirectedPcdn,
      overseas,
      tencent,
      proxy,
    ], MediaCdnPreference.automatic);
    expect(ordered, [overseas, tencent, proxy, disguisedPcdn, redirectedPcdn]);
    expect(ordered.first, same(overseas));
    expect(ordered.first.query, overseas.query);
    expect(backupMediaCdnUrl(ordered, MediaCdnPreference.automatic), tencent);
  });

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
