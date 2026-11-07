import 'dart:convert';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/fsplayer_input_lease.dart';
import 'package:bili_player/src/fsplayer_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'network broker preserves Range, response bounds and per-source headers',
    () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <String?>[];
      final listening = origin.listen((request) async {
        seen.add(request.headers.value('referer'));
        expect(request.headers.value('range'), 'bytes=2-4');
        request.response.statusCode = 206;
        request.response.headers.set('Content-Range', 'bytes 2-4/6');
        request.response.contentLength = 3;
        request.response.add([2, 3, 4]);
        await request.response.close();
      });
      final uri = Uri.parse(
        'http://127.0.0.1:${origin.port}/video?token=private',
      );
      final input = fsPlayerInput(
        ProgressiveSource(
          MediaTrack(
            uri: uri,
            requestPolicy: MediaRequestPolicy(
              headers: {'Referer': 'https://example.test'},
            ),
          ),
        ),
        const OpenOptions(),
      );
      final lease = await FsPlayerInputLease.open(input);
      final client = HttpClient();
      try {
        expect(lease.url, isNot(contains('private')));
        final request = await client.getUrl(Uri.parse(lease.url));
        request.headers.set('range', 'bytes=2-4');
        final response = await request.close();
        expect(response.statusCode, 206);
        expect(response.headers.value('content-range'), 'bytes 2-4/6');
        expect(await response.expand((chunk) => chunk).toList(), [2, 3, 4]);
        expect(seen, ['https://example.test']);
      } finally {
        client.close(force: true);
        await lease.close();
        await listening.cancel();
        await origin.close(force: true);
      }
    },
  );

  test(
    'HLS children and encryption-key URIs stay on opaque broker routes',
    () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final listening = origin.listen((request) async {
        if (request.uri.path == '/live/index.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          request.response.write(
            '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key?token=private"\n#EXTINF:2,\nsegment.ts?token=private\n',
          );
        } else {
          request.response.add([1, 2, 3]);
        }
        await request.response.close();
      });
      final input = fsPlayerInput(
        ManifestSource(
          MediaTrack(
            uri: Uri.parse('http://127.0.0.1:${origin.port}/live/index.m3u8'),
            requestPolicy: MediaRequestPolicy(),
          ),
        ),
        const OpenOptions(),
      );
      final lease = await FsPlayerInputLease.open(input);
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(Uri.parse(lease.url)))
            .close();
        final manifest = await utf8.decoder.bind(response).join();
        expect(manifest, isNot(contains('private')));
        expect(manifest, isNot(contains('${origin.port}')));
        final segment = manifest
            .split('\n')
            .firstWhere((line) => line.startsWith('http'));
        final media = await (await client.getUrl(Uri.parse(segment))).close();
        expect(await media.expand((chunk) => chunk).toList(), [1, 2, 3]);
      } finally {
        client.close(force: true);
        await lease.close();
        await listening.cancel();
        await origin.close(force: true);
      }
    },
  );

  test(
    'an untrusted TLS origin is rejected before any media request',
    () async {
      final temp = await Directory.systemTemp.createTemp('fsplayer-tls-test-');
      HttpServer? origin;
      FsPlayerInputLease? lease;
      final client = HttpClient();
      try {
        ProcessResult generated;
        try {
          generated = await Process.run('openssl', [
            'req',
            '-x509',
            '-newkey',
            'rsa:2048',
            '-nodes',
            '-keyout',
            '${temp.path}/key.pem',
            '-out',
            '${temp.path}/cert.pem',
            '-days',
            '1',
            '-subj',
            '/CN=127.0.0.1',
            '-addext',
            'subjectAltName=IP:127.0.0.1',
          ]);
        } on ProcessException {
          markTestSkipped('OpenSSL is unavailable for synthetic TLS test');
          return;
        }
        expect(generated.exitCode, 0);
        final context = SecurityContext()
          ..useCertificateChain('${temp.path}/cert.pem')
          ..usePrivateKey('${temp.path}/key.pem');
        origin = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          context,
        );
        var requests = 0;
        origin.listen((request) {
          requests++;
          request.response.close();
        }, onError: (Object _) {});
        lease = await FsPlayerInputLease.open(
          fsPlayerInput(
            ProgressiveSource(
              MediaTrack(
                uri: Uri.parse('https://127.0.0.1:${origin.port}/video'),
                requestPolicy: MediaRequestPolicy(),
              ),
            ),
            const OpenOptions(),
          ),
        );
        final response = await (await client.getUrl(Uri.parse(lease.url)))
            .close();
        expect(response.statusCode, 502);
        await response.drain<void>();
        expect(requests, 0);
      } finally {
        client.close(force: true);
        await lease?.close();
        await origin?.close(force: true);
        await temp.delete(recursive: true);
      }
    },
  );
}
