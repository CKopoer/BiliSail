const assert = require('node:assert/strict');
const { test } = require('node:test');
const { updateReadmeDownloads, syncReadmeDownloads } = require('./update-readme-downloads.cjs');

const platforms = ['Windows x64', 'Android arm64', 'macOS arm64 / Intel x64', 'iOS arm64', 'Linux x64'];
const suffixes = [
  'windows-x64.exe', 'windows-x64.msi', 'windows-x64.msix', 'windows-x64.cer',
  'android-arm64.apk', 'macos-arm64.dmg', 'macos-x64.dmg', 'ios-arm64-unsigned.ipa',
  'linux-x64.flatpak', 'linux-x64.AppImage',
];
const readme = [
  'Content before the table.', '<!-- release-downloads:start -->', '下载版本：old',
  '| 平台 | 下载 | 安装说明 |', '| --- | --- | --- |',
  ...platforms.map((platform) => `| ${platform} | old download | Keep ${platform} instructions. |`),
  '<!-- release-downloads:end -->', 'Content after the table.', '',
].join('\n');

function makeRelease(version = '1.2.3+1', selected = suffixes) {
  const tag = `v${version}`;
  const base = 'https://github.com/CKopoer/BiliSail/releases';
  return {
    tag_name: tag, html_url: `${base}/tag/${encodeURIComponent(tag)}`, draft: false, prerelease: false,
    assets: selected.map((suffix) => {
      const name = `BiliSail-${version}-${suffix}`;
      return { name, state: 'uploaded',
        browser_download_url: `${base}/download/${encodeURIComponent(tag)}/${encodeURIComponent(name)}` };
    }),
  };
}

test('matches every package format while preserving instructions and surrounding content', () => {
  const release = makeRelease();
  const updated = updateReadmeDownloads(readme, release);
  for (const asset of release.assets) assert.ok(updated.includes(asset.browser_download_url));
  for (const platform of platforms) assert.ok(updated.includes(`Keep ${platform} instructions.`));
  assert.ok(updated.startsWith('Content before the table.\n'));
  assert.ok(updated.endsWith('Content after the table.\n'));
  assert.ok(updated.includes(`[v1.2.3+1](${release.html_url})`));
  assert.equal(updateReadmeDownloads(updated, release), updated);
});

test('partial releases clear obsolete links and do not infer unavailable platforms', () => {
  const previous = updateReadmeDownloads(readme, makeRelease());
  const release = makeRelease('1.3.0+2', ['android-arm64.apk', 'android-arm64.apk.sha256']);
  const updated = updateReadmeDownloads(previous, release);
  assert.ok(updated.includes(release.assets[0].browser_download_url));
  assert.ok(!updated.includes('.sha256'));
  assert.ok(!updated.includes('1.2.3'));
  assert.equal((updated.match(/暂未提供/g) ?? []).length, 9);
});

test('ignores attachments from another version and incomplete uploads', () => {
  const release = { ...makeRelease('1.3.0+1', []), assets: [
    ...makeRelease().assets,
    ...makeRelease('1.3.0+1', ['android-arm64.apk']).assets.map((asset) => ({ ...asset, state: 'starter' })),
  ] };
  const updated = updateReadmeDownloads(readme, release);
  assert.equal((updated.match(/暂未提供/g) ?? []).length, 10);
  assert.ok(!updated.includes('/download/'));
});

test('retains CRLF line endings', () => {
  const updated = updateReadmeDownloads(readme.replaceAll('\n', '\r\n'), makeRelease());
  assert.ok(!updated.replaceAll('\r\n', '').includes('\n'));
});

test('rejects drafts, previews, malformed versions, markers and missing rows', () => {
  for (const invalid of [
    { ...makeRelease(), draft: true }, { ...makeRelease(), prerelease: true },
    { ...makeRelease(), tag_name: 'v1.2.3' },
  ]) assert.throws(() => updateReadmeDownloads(readme, invalid));
  for (const invalid of [
    readme.replace('release-downloads:start', 'missing'),
    readme + '<!-- release-downloads:start -->',
    readme.replace('| Windows x64 |', '| Unknown platform |'),
    readme.replace('下载版本：old', 'Version: old'),
  ]) assert.throws(() => updateReadmeDownloads(invalid, makeRelease()));
});

test('rejects download URLs that do not belong to the exact release asset', () => {
  const release = makeRelease();
  for (const url of ['https://example.com/package.exe', release.assets[1].browser_download_url]) {
    const invalid = { ...release, assets: [{ ...release.assets[0], browser_download_url: url }] };
    assert.throws(() => updateReadmeDownloads(readme, invalid));
  }
});

function makeClient({ current = readme, conflict = false, failure = null } = {}) {
  let writes = [];
  let reads = 0;
  const client = {
    context: { repo: { owner: 'CKopoer', repo: 'BiliSail' }, payload: { repository: { default_branch: 'master' } } },
    core: { info() {} },
    github: { rest: { repos: {
      async getLatestRelease() { return { data: makeRelease() }; },
      async getContent(args) {
        assert.equal(args.ref, 'master');
        reads++;
        const content = conflict && reads > 1 ? `Concurrent edit.\n${current}` : current;
        return { data: { type: 'file', encoding: 'base64', sha: `sha-${reads}`,
          content: Buffer.from(content).toString('base64') } };
      },
      async createOrUpdateFileContents(args) {
        writes = [...writes, args];
        if (failure) throw Object.assign(new Error('Write rejected.'), { status: failure });
        if (conflict && writes.length === 1) throw Object.assign(new Error('Conflict.'), { status: 409 });
      },
    } } },
  };
  return { client, getWrites: () => writes };
}

test('writes the default branch using its current blob SHA', async () => {
  const { client, getWrites } = makeClient();
  await syncReadmeDownloads(client);
  const writes = getWrites();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].sha, 'sha-1');
  assert.equal(writes[0].branch, 'master');
  assert.equal(Buffer.from(writes[0].content, 'base64').toString(), updateReadmeDownloads(readme, makeRelease()));
});

test('skips a commit when the download links already match', async () => {
  const { client, getWrites } = makeClient({ current: updateReadmeDownloads(readme, makeRelease()) });
  await syncReadmeDownloads(client);
  assert.equal(getWrites().length, 0);
});

test('re-reads and preserves a concurrent README edit after a conflict', async () => {
  const { client, getWrites } = makeClient({ conflict: true });
  await syncReadmeDownloads(client);
  const writes = getWrites();
  assert.equal(writes.length, 2);
  assert.equal(writes[1].sha, 'sha-2');
  assert.ok(Buffer.from(writes[1].content, 'base64').toString().startsWith('Concurrent edit.\n'));
});

test('bounds conflict retries and surfaces permission failures', async () => {
  for (const [failure, expectedAttempts] of [[409, 3], [403, 1]]) {
    const { client, getWrites } = makeClient({ failure });
    await assert.rejects(syncReadmeDownloads(client), { status: failure });
    assert.equal(getWrites().length, expectedAttempts);
  }
});
