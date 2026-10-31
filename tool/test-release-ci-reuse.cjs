const assert = require('node:assert/strict');
const { execFile } = require('node:child_process');
const { createHash } = require('node:crypto');
const { cp, mkdir, mkdtemp, writeFile, readFile, rm } = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const { promisify } = require('node:util');
const { planReleaseBuilds, downloadReusedArtifacts, verifyReleaseAssets } = require('./release-ci-reuse.cjs');

const version = '1.2.5+0';
const context = { repo: { owner: 'CKopoer', repo: 'BiliSail' }, sha: 'a'.repeat(40) };
const now = Date.parse('2026-10-31T00:00:00Z');
const allTargets = ['android-arm64', 'windows-x64', 'macos-arm64', 'macos-x64', 'ios-arm64', 'linux-x64'];

function makeRun(id, overrides = {}) {
  return { id, status: 'completed', conclusion: 'success', event: 'push',
    head_sha: context.sha, head_repository: { full_name: 'CKopoer/BiliSail' },
    html_url: `https://github.com/CKopoer/BiliSail/actions/runs/${id}`, ...overrides };
}

function makeArtifacts(targets = allTargets, buildVersion = version) {
  return targets.map((target, index) => ({ id: 100 + index,
    name: `BiliSail-${target}-${buildVersion}-packages`, expired: false,
    expires_at: '2026-11-07T00:00:00Z', size_in_bytes: 1024 }));
}

function makeJobs(overrides = {}) {
  return ['Analyze and test', ...allTargets.map((target) => `Build ${target}`)]
    .map((name) => ({ name, status: 'completed', conclusion: 'success', ...overrides[name] }));
}

function plan(options) {
  return planReleaseBuilds({ context, version, targets: allTargets, reuseCiBuild: true, now, ...options });
}

function fakeGitHub(pages, artifactsByRun, jobsByRun = {}) {
  const listWorkflowRuns = () => {};
  const listWorkflowRunArtifacts = () => {};
  const listJobsForWorkflowRun = () => {};
  const artifactRequests = [];
  const paginate = async (method, parameters) => {
    if (method === listWorkflowRunArtifacts) {
      artifactRequests.push(parameters.run_id);
      return artifactsByRun[parameters.run_id];
    }
    assert.equal(method, listJobsForWorkflowRun);
    assert.equal(parameters.filter, 'latest');
    return jobsByRun[parameters.run_id] ?? makeJobs();
  };
  paginate.iterator = async function* (method, parameters) {
    assert.equal(method, listWorkflowRuns);
    assert.equal(parameters.workflow_id, 'ci.yml');
    assert.equal(parameters.head_sha, context.sha);
    assert.equal(parameters.status, 'completed');
    // Octokit normalizes REST collection envelopes before yielding each page.
    for (const runs of pages) yield { data: runs };
  };
  return { github: { rest: { actions: { listWorkflowRuns, listWorkflowRunArtifacts, listJobsForWorkflowRun } }, paginate },
    artifactRequests };
}

test('reuses only selected platform packages from a CI superset', async () => {
  const { github } = fakeGitHub([[makeRun(10)]], { 10: makeArtifacts() });
  const selected = await plan({ github, targets: ['macos-arm64', 'macos-x64'] });
  assert.deepEqual(selected.buildTargets, []);
  assert.deepEqual(selected.reused.map(({ target }) => target), ['macos-arm64', 'macos-x64']);
  for (const source of selected.reused) {
    assert.equal(source.runId, 10);
    assert.equal(source.artifactName, `BiliSail-${source.target}-${version}-packages`);
  }
});

test('continues through paginated runs to find a matching manually versioned CI build', async () => {
  const { github, artifactRequests } = fakeGitHub([[makeRun(20)], [makeRun(10, { event: 'workflow_dispatch' })]],
    { 20: makeArtifacts(allTargets, '1.2.4+0'), 10: makeArtifacts() });
  const selected = await plan({ github });
  assert.ok(selected.reused.every(({ runId }) => runId === 10));
  assert.deepEqual(selected.buildTargets, []);
  assert.deepEqual(artifactRequests, [20, 10]);
});

test('rebuilds selected targets when the normalized workflow runs page is empty', async () => {
  const { github, artifactRequests } = fakeGitHub([[]], {});
  assert.deepEqual(await plan({ github }), { reused: [], buildTargets: allTargets });
  assert.deepEqual(artifactRequests, []);
});

test('stops requesting workflow pages once all selected targets have reusable builds', async () => {
  const { github } = fakeGitHub([], { 10: makeArtifacts() });
  github.paginate.iterator = async function* () {
    yield { data: [makeRun(10)] };
    throw new Error('The planner must not request another page after matching all targets.');
  };
  const selected = await plan({ github });
  assert.deepEqual(selected.buildTargets, []);
  assert.equal(selected.reused.length, allTargets.length);
});

test('propagates workflow pagination errors even after matching some targets', async (t) => {
  for (const partialMatch of [false, true]) {
    await t.test(partialMatch ? 'after partial reuse' : 'before the first page', async () => {
      const { github } = fakeGitHub([], { 10: makeArtifacts(['android-arm64']) });
      github.paginate.iterator = async function* () {
        if (partialMatch) yield { data: [makeRun(10)] };
        throw new Error('Workflow pagination failed.');
      };
      await assert.rejects(plan({ github }), /Workflow pagination failed/);
    });
  }
});

test('does not reuse untrusted or incomplete runs', async (t) => {
  for (const overrides of [
    { event: 'pull_request' }, { event: 'pull_request_target' }, { event: 'workflow_run' },
    { status: 'in_progress' },
    { head_sha: 'b'.repeat(40) }, { head_repository: { full_name: 'fork/BiliSail' } },
    { head_repository: null },
  ]) {
    await t.test(JSON.stringify(overrides), async () => {
      const { github, artifactRequests } = fakeGitHub([[makeRun(10, overrides)]], { 10: makeArtifacts() });
      assert.deepEqual(await plan({ github }), { reused: [], buildTargets: allTargets });
      assert.deepEqual(artifactRequests, []);
    });
  }
});

test('rebuilds only targets with unavailable, expired or ambiguous packages', async (t) => {
  const valid = makeArtifacts();
  const cases = [
    ['missing Intel macOS', valid.filter((artifact) => !artifact.name.includes('macos-x64')), ['macos-x64']],
    ['wrong version', makeArtifacts(allTargets, '1.2.5+1'), allTargets],
    ['expired flag', valid.map((artifact, index) => index ? artifact : { ...artifact, expired: true }), ['android-arm64']],
    ['expired time', valid.map((artifact, index) => index ? artifact : { ...artifact, expires_at: '2026-10-30' }), ['android-arm64']],
    ['empty archive', valid.map((artifact, index) => index ? artifact : { ...artifact, size_in_bytes: 0 }), ['android-arm64']],
    ['duplicate artifact', [...valid, valid[0]], ['android-arm64']],
    ['legacy names', valid.map((artifact) => ({ ...artifact, name: artifact.name.replace(`-${version}`, '') })), allTargets],
  ];
  for (const [name, artifacts, missing] of cases) {
    await t.test(name, async () => {
      const { github } = fakeGitHub([[makeRun(10)]], { 10: artifacts });
      const selected = await plan({ github });
      assert.deepEqual(selected.buildTargets, missing);
      assert.deepEqual(selected.reused.map(({ target }) => target), allTargets.filter((target) => !missing.includes(target)));
    });
  }
});

test('combines targets from multiple CI runs and builds only missing targets', async () => {
  const { github } = fakeGitHub([[makeRun(20), makeRun(10)]], {
    20: makeArtifacts(['macos-arm64']), 10: makeArtifacts(['macos-x64']),
  });
  const selected = await plan({ github });
  assert.deepEqual(selected.reused.map(({ target, runId }) => [target, runId]), [['macos-arm64', 20], ['macos-x64', 10]]);
  assert.deepEqual(selected.buildTargets, ['android-arm64', 'windows-x64', 'ios-arm64', 'linux-x64']);
  const empty = fakeGitHub([], {});
  assert.deepEqual(await plan({ github: empty.github }), { reused: [], buildTargets: allTargets });
});

test('keeps an already matched target while searching older runs for missing targets', async () => {
  const { github } = fakeGitHub([[makeRun(20)], [makeRun(10)]], {
    20: makeArtifacts(['android-arm64']), 10: makeArtifacts(),
  });
  const selected = await plan({ github });
  assert.equal(selected.reused[0].runId, 20);
  assert.ok(selected.reused.slice(1).every(({ runId }) => runId === 10));
  assert.deepEqual(selected.buildTargets, []);
});

test('partitions all 64 reuse combinations without omitting or rebuilding a reusable target', async () => {
  for (let mask = 0; mask < 64; mask++) {
    const available = allTargets.filter((_, index) => mask & (1 << index));
    const { github } = fakeGitHub([[makeRun(10)]], { 10: makeArtifacts(available) });
    const selected = await plan({ github });
    assert.deepEqual(selected.reused.map(({ target }) => target), available);
    assert.deepEqual(selected.buildTargets, allTargets.filter((target) => !available.includes(target)));
  }
});

test('disabled reuse builds every selected target without querying GitHub', async () => {
  assert.deepEqual(await plan({ github: {}, reuseCiBuild: false }), { reused: [], buildTargets: allTargets });
});

test('reuses successful platform jobs even when another platform failed or was cancelled', async (t) => {
  for (const conclusion of ['failure', 'cancelled']) {
    await t.test(conclusion, async () => {
      const { github } = fakeGitHub([[makeRun(10, { conclusion })]], { 10: makeArtifacts() },
        { 10: makeJobs({ 'Build windows-x64': { conclusion } }) });
      const selected = await plan({ github });
      assert.deepEqual(selected.buildTargets, ['windows-x64']);
      assert.equal(selected.reused.length, 5);
    });
  }
});

test('never reuses builds when checks failed or the selected job did not succeed', async (t) => {
  for (const overrides of [
    { 'Analyze and test': { conclusion: 'failure' } },
    { 'Analyze and test': { status: 'in_progress' } },
    { 'Analyze and test': { conclusion: 'skipped' } },
    { 'Build android-arm64': { conclusion: 'failure' } },
    { 'Build android-arm64': { status: 'in_progress' } },
  ]) {
    await t.test(JSON.stringify(overrides), async () => {
      const { github } = fakeGitHub([[makeRun(10)]], { 10: makeArtifacts() }, { 10: makeJobs(overrides) });
      const selected = await plan({ github, targets: ['android-arm64'] });
      assert.deepEqual(selected, { reused: [], buildTargets: ['android-arm64'] });
    });
  }
  const { github } = fakeGitHub([[makeRun(10)]], { 10: makeArtifacts() }, { 10: [] });
  assert.deepEqual(await plan({ github }), { reused: [], buildTargets: allTargets });
});

test('propagates API errors instead of treating permission failures as cache misses', async () => {
  const { github } = fakeGitHub([[makeRun(10)]], {});
  github.paginate = async () => { throw new Error('403 Actions read denied'); };
  github.paginate.iterator = async function* () { yield { data: [makeRun(10)] }; };
  await assert.rejects(plan({ github }), /403/);
});

test('rejects empty, duplicate or unsupported selections before querying CI', async () => {
  for (const targets of [[], ['macos-arm64', 'macos-arm64'], ['unknown'], ['toString']]) {
    await assert.rejects(plan({ github: {}, targets }), /supported targets/);
  }
});

test('downloads each selected artifact from its own CI run without a shell', async () => {
  const { github } = fakeGitHub([[makeRun(20)], [makeRun(10)]], {
    20: makeArtifacts(['android-arm64']), 10: makeArtifacts(['windows-x64']),
  });
  const selected = await plan({ github, targets: ['android-arm64', 'windows-x64'] });
  const calls = [];
  await downloadReusedArtifacts({ reused: selected.reused, repository: 'CKopoer/BiliSail', directory: 'release-assets',
    execute: async (...args) => { calls.push(args); } });
  assert.deepEqual(calls, [20, 10].map((runId, index) => ['gh', ['run', 'download', String(runId),
    '--repo', 'CKopoer/BiliSail', '--name', `BiliSail-${allTargets[index]}-${version}-packages`, '--dir', 'release-assets']]));
});

test('download failure stops the release without silently dropping a reused target', async () => {
  let calls = 0;
  await assert.rejects(downloadReusedArtifacts({ reused: [{ runId: 10, artifactName: 'one' },
    { runId: 20, artifactName: 'two' }], repository: 'CKopoer/BiliSail', directory: 'release-assets',
    execute: async () => { calls++; throw new Error('Artifact expired'); } }), /Artifact expired/);
  assert.equal(calls, 1);
});

async function writeChecksummed(directory, name, value) {
  await writeFile(path.join(directory, name), value);
  const hash = createHash('sha256').update(value).digest('hex');
  await writeFile(path.join(directory, name + '.sha256'), `${hash}  ${name}\r\n`);
}

async function makeAssets(t, targets = allTargets) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'bilisail-release-reuse-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const expected = { directory, version, targets, sourceRevision: context.sha,
    flutterVersion: '3.47.6', pubspecLockSha256s: ['c'.repeat(64), 'f'.repeat(64)] };
  const suffixes = [['.apk'], ['.msix', '.msi', '.exe', '.cer'], ['.dmg'], ['.dmg'],
    ['-unsigned.ipa'], ['.AppImage', '.flatpak']];
  for (const target of targets) {
    const prefix = `BiliSail-${version}-${target}`;
    const metadata = { version, target, sourceRevision: context.sha, sourceDirty: false,
      flutterVersion: expected.flutterVersion, pubspecLockSha256: expected.pubspecLockSha256s[0],
      signing: target === 'android-arm64' ? 'configured-keystore' : 'ad-hoc-not-notarized' };
    await writeChecksummed(directory, prefix + '.build-info.json', '\uFEFF' + JSON.stringify(metadata));
    for (const suffix of [...suffixes[allTargets.indexOf(target)], '.mux-source.zip']) {
      await writeChecksummed(directory, prefix + suffix, `fixture ${target}${suffix}`);
    }
  }
  return expected;
}

test('accepts complete packages for all six targets including BOM metadata and CRLF checksums', async (t) => {
  await verifyReleaseAssets(await makeAssets(t));
});

test('reports installer build directories and missing files without weakening asset verification', async (t) => {
  const expected = await makeAssets(t);
  for (const directory of ['installer-native', 'installer-artwork']) {
    await mkdir(path.join(expected.directory, directory));
    await writeFile(path.join(expected.directory, directory, 'build-only.txt'), 'not a release asset');
  }
  const missing = `BiliSail-${version}-windows-x64.msi.sha256`;
  await rm(path.join(expected.directory, missing));
  await assert.rejects(verifyReleaseAssets(expected), (error) => {
    assert.ok(error.message.includes(`Missing: ["${missing}"]`));
    assert.ok(error.message.includes('Unexpected: ["installer-artwork/","installer-native/"]'));
    return true;
  });
  await writeFile(path.join(expected.directory, missing), 'checksum');
  await assert.rejects(verifyReleaseAssets(expected), /Missing: \[\]\. Unexpected: \["installer-artwork\/","installer-native\/"\]/);
});

test('draft uploads packages and their checksums while keeping build metadata and mux sources in Actions', async (t) => {
  const expected = await makeAssets(t);
  const directory = await mkdtemp(path.join(os.tmpdir(), 'bilisail-release-draft-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const assetsDirectory = path.join(directory, 'release-assets');
  await cp(expected.directory, assetsDirectory, { recursive: true });
  await verifyReleaseAssets({ ...expected, directory: assetsDirectory });

  const workflow = await readFile(path.join(__dirname, '../.github/workflows/release.yml'), 'utf8');
  const script = /      - name: Create preview draft with all selected packages[\s\S]*?        run: \|\r?\n([\s\S]*?)      - name: Keep the latest 15 releases/.exec(workflow)?.[1];
  assert.ok(script, 'Expected the production draft creation step.');
  const scriptPath = path.join(directory, 'create-draft.ps1');
  await writeFile(scriptPath, `
function gh {
  $global:LASTEXITCODE = 0
  if ($args[0] -eq 'api') { return '[]' }
  if ($args[0] -ne 'release' -or $args[1] -ne 'create') { throw 'Unexpected gh command.' }
  ConvertTo-Json -InputObject @($args) | Set-Content -LiteralPath gh-arguments.json -Encoding utf8
}
${script.replace(/^          /gm, '')}`);
  await promisify(execFile)('pwsh', ['-NoProfile', '-File', scriptPath], {
    cwd: directory,
    env: { ...process.env, RELEASE_VERSION: version, GITHUB_SHA: context.sha,
      GITHUB_SERVER_URL: 'https://github.com', GITHUB_REPOSITORY: 'CKopoer/BiliSail', GITHUB_RUN_ID: '1234' },
  });

  const args = JSON.parse((await readFile(path.join(directory, 'gh-arguments.json'), 'utf8')).replace(/^\uFEFF/, ''));
  assert.deepEqual(args.slice(0, 3), ['release', 'create', `v${version}`]);
  const packages = ['android-arm64.apk', 'windows-x64.msix', 'windows-x64.msi', 'windows-x64.exe',
    'windows-x64.cer', 'macos-arm64.dmg', 'macos-x64.dmg', 'ios-arm64-unsigned.ipa',
    'linux-x64.AppImage', 'linux-x64.flatpak'].map((suffix) => `BiliSail-${version}-${suffix}`);
  const attachments = [...packages.flatMap((name) => [name, name + '.sha256']), 'THIRD_PARTY_NOTICES.md'];
  assert.deepEqual(args.slice(3, args.indexOf('--repo')).map((file) => path.basename(file)).sort(), attachments.sort());
  assert.ok(args.includes('--draft'));
  assert.ok(args.includes('--prerelease'));
  const notes = await readFile(path.join(directory, 'release-notes.md'), 'utf8');
  assert.ok(notes.includes('[Actions 构建记录](https://github.com/CKopoer/BiliSail/actions/runs/1234)'));
  assert.ok(!notes.includes('见 build-info.json'));
  await verifyReleaseAssets({ ...expected, directory: assetsDirectory });
});

test('accepts the same source lockfile checked out with Windows line endings', async (t) => {
  const expected = await makeAssets(t, ['windows-x64']);
  const name = `BiliSail-${version}-windows-x64.build-info.json`;
  const metadata = JSON.parse((await readFile(path.join(expected.directory, name), 'utf8')).replace(/^\uFEFF/, ''));
  await writeChecksummed(expected.directory, name,
    JSON.stringify({ ...metadata, pubspecLockSha256: expected.pubspecLockSha256s[1] }));
  await verifyReleaseAssets(expected);
});

test('draft job runs after a cache hit or successful fresh build and blocks failed or cancelled releases', async () => {
  const workflow = await readFile(path.join(__dirname, '../.github/workflows/release.yml'), 'utf8');
  const expression = /  draft:\r?\n[\s\S]*?    if: >-\r?\n([\s\S]*?)    runs-on:/.exec(workflow)?.[1];
  assert.ok(expression, 'Expected the production draft job condition.');
  const shouldDraft = new Function('needs', 'cancelled',
    `return (${expression.replace('${{', '').replace('}}', '')});`);
  for (const prepare of ['success', 'failure', 'cancelled', 'skipped']) {
    for (const build of ['success', 'failure', 'cancelled', 'skipped']) {
      for (const buildRequired of [true, false]) {
        for (const cancelled of [true, false]) {
          const needs = { prepare: { result: prepare, outputs: { build_required: String(buildRequired) } },
            build: { result: build } };
          const expected = !cancelled && prepare === 'success' &&
            (buildRequired ? build === 'success' : build === 'skipped');
          assert.equal(shouldDraft(needs, () => cancelled), expected, JSON.stringify(needs));
        }
      }
    }
  }
});

test('rejects missing files, unexpected platforms and tampered archives before drafting', async (t) => {
  for (const kind of ['installer', 'checksum', 'sources', 'extra platform', 'tampered bytes', 'checksum filename']) {
    await t.test(kind, async (t) => {
      const expected = await makeAssets(t, ['android-arm64']);
      const name = `BiliSail-${version}-android-arm64.apk`;
      if (kind === 'installer') await rm(path.join(expected.directory, name));
      if (kind === 'checksum') await rm(path.join(expected.directory, name + '.sha256'));
      if (kind === 'sources') await rm(path.join(expected.directory, `BiliSail-${version}-android-arm64.mux-source.zip`));
      if (kind === 'extra platform') await writeChecksummed(expected.directory, 'BiliSail-other-windows-x64.exe', 'extra');
      if (kind === 'tampered bytes') await writeFile(path.join(expected.directory, name), 'changed');
      if (kind === 'checksum filename') {
        const checksum = await readFile(path.join(expected.directory, name + '.sha256'), 'utf8');
        await writeFile(path.join(expected.directory, name + '.sha256'), checksum.replace(name, 'another.apk'));
      }
      await assert.rejects(verifyReleaseAssets(expected), /Release assets|SHA-256/);
    });
  }
});

test('rejects mismatched provenance even when the metadata checksum is valid', async (t) => {
  for (const change of [
    { version: '1.2.5+1' }, { target: 'ios-arm64' }, { sourceRevision: 'b'.repeat(40) },
    { sourceDirty: true }, { flutterVersion: '3.0.0' }, { pubspecLockSha256: 'd'.repeat(64) },
    { signing: 'temporary-debug-key' },
  ]) {
    await t.test(JSON.stringify(change), async (t) => {
      const expected = await makeAssets(t, ['android-arm64']);
      const name = `BiliSail-${version}-android-arm64.build-info.json`;
      const original = JSON.parse((await readFile(path.join(expected.directory, name), 'utf8')).replace(/^\uFEFF/, ''));
      await writeChecksummed(expected.directory, name, JSON.stringify({ ...original, ...change }));
      await assert.rejects(verifyReleaseAssets(expected), /provenance|release keystore/);
    });
  }
});
