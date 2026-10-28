const startMarker = '<!-- release-downloads:start -->';
const endMarker = '<!-- release-downloads:end -->';
const downloadGroups = [
  ['Windows x64', [
    ['EXE', 'windows-x64.exe'], ['MSI', 'windows-x64.msi'],
    ['MSIX', 'windows-x64.msix'], ['证书 CER', 'windows-x64.cer'],
  ]],
  ['Android arm64', [['APK', 'android-arm64.apk']]],
  ['macOS arm64 / Intel x64', [
    ['Apple Silicon DMG', 'macos-arm64.dmg'], ['Intel x64 DMG', 'macos-x64.dmg'],
  ]],
  ['iOS arm64', [['未签名 IPA', 'ios-arm64-unsigned.ipa']]],
  ['Linux x64', [['Flatpak', 'linux-x64.flatpak'], ['AppImage', 'linux-x64.AppImage']]],
];

function updateReadmeDownloads(readme, release) {
  const version = /^v?(\d+\.\d+\.\d+\+\d+)$/.exec(release.tag_name)?.[1];
  if (!version || release.draft || release.prerelease) {
    throw new Error('Expected a published stable release with an x.y.z+N version.');
  }
  const releaseUrl = new URL(release.html_url);
  if (releaseUrl.protocol !== 'https:' || releaseUrl.hostname !== 'github.com' ||
      !releaseUrl.pathname.endsWith(`/releases/tag/${encodeURIComponent(release.tag_name)}`)) {
    throw new Error('Invalid GitHub release URL.');
  }
  const assets = new Map(release.assets
    .filter((asset) => asset.state === 'uploaded')
    .map((asset) => [asset.name, asset]));
  const start = readme.indexOf(startMarker);
  const end = readme.indexOf(endMarker);
  if (start < 0 || end < start || readme.indexOf(startMarker, start + 1) >= 0 ||
      readme.indexOf(endMarker, end + 1) >= 0) {
    throw new Error('Expected one ordered pair of README download markers.');
  }
  const section = readme.slice(start, end);
  const newline = section.includes('\r\n') ? '\r\n' : '\n';
  const lines = section.split(/\r?\n/);
  if (lines.filter((line) => line.startsWith('下载版本：')).length !== 1) {
    throw new Error('Expected one download version line.');
  }
  const replacements = downloadGroups.map(([platform, downloads]) => {
    if (lines.filter((line) => line.startsWith(`| ${platform} |`)).length !== 1) {
      throw new Error(`Expected one download row for ${platform}.`);
    }
    const links = downloads.map(([label, suffix]) => {
      const name = `BiliSail-${version}-${suffix}`;
      const asset = assets.get(name);
      if (!asset) return `${label}：暂未提供`;
      const url = new URL(asset.browser_download_url);
      const expectedPath = releaseUrl.pathname.replace('/releases/tag/', '/releases/download/') +
        `/${encodeURIComponent(name)}`;
      if (url.origin !== releaseUrl.origin || url.pathname !== expectedPath || url.search || url.hash) {
        throw new Error(`Invalid download URL for ${name}.`);
      }
      return `[${label}](${url.href})`;
    });
    return [platform, links.join(' / ')];
  });
  const updated = lines.map((line) => {
    if (line.startsWith('下载版本：')) {
      return `下载版本：[${release.tag_name}](${releaseUrl.href})。`;
    }
    const replacement = replacements.find(([platform]) => line.startsWith(`| ${platform} |`));
    if (!replacement) return line;
    // Keep the platform label, installation instructions and all other columns.
    return line.replace(/^(\| [^|]+ \| )[^|]*( \|.*)$/, (_, prefix, suffix) =>
      prefix + replacement[1] + suffix);
  }).join(newline);
  return readme.slice(0, start) + updated + readme.slice(end);
}

async function syncReadmeDownloads({ github, context, core }) {
  const branch = context.payload.repository.default_branch;
  for (let attempt = 0; attempt < 3; attempt++) {
    const [{ data: release }, { data: file }] = await Promise.all([
      github.rest.repos.getLatestRelease(context.repo),
      github.rest.repos.getContent({ ...context.repo, path: 'README.md', ref: branch }),
    ]);
    if (file.type !== 'file' || file.encoding !== 'base64') {
      throw new Error('Expected README.md as a base64-encoded file.');
    }
    const current = Buffer.from(file.content, 'base64').toString('utf8');
    const updated = updateReadmeDownloads(current, release);
    if (updated === current) {
      core.info('README download links already match the latest stable release.');
      return;
    }
    try {
      await github.rest.repos.createOrUpdateFileContents({
        ...context.repo, branch, path: 'README.md', sha: file.sha,
        message: `docs: update download links for ${release.tag_name}`,
        content: Buffer.from(updated).toString('base64'),
      });
      core.info(`Updated README download links for ${release.tag_name}.`);
      return;
    } catch (error) {
      // Re-read the current README to preserve a concurrent edit; keep a bound
      // on retries and never bypass branch protection or force a stale write.
      if (error.status !== 409 || attempt === 2) throw error;
    }
  }
}

module.exports = { updateReadmeDownloads, syncReadmeDownloads };
