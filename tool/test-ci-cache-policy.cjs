const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { canWriteCaches, planCleanup, cleanupCaches, prepareCacheSave } = require('./ci-cache-policy.cjs');

const flutterVersion = readFileSync('.flutter-version', 'utf8').trim();
const context = { repo: { owner: 'CKopoer', repo: 'BiliSail' }, eventName: 'push',
  ref: 'refs/heads/master', payload: { repository: { default_branch: 'master' } } };
const options = { ref: context.ref, flutterVersion };
const pubPrefix = `bilisail-pub-v2-linux-X64-${flutterVersion}-`;
const cache = (id, key, overrides = {}) => ({ id, key, ref: context.ref,
  size_in_bytes: 100_000_000, created_at: `2026-11-0${id}T00:00:00Z`, ...overrides });

function fixture(caches) {
  const deleted = [];
  const warnings = [];
  const getActionsCacheList = () => {};
  return { deleted, warnings, context,
    core: { info: () => {}, warning: (message) => warnings.push(message) },
    github: { rest: { actions: { getActionsCacheList,
      deleteActionsCacheById: async ({ cache_id }) => { deleted.push(cache_id); } } },
    paginate: async (method, parameters) => {
      assert.equal(method, getActionsCacheList);
      assert.equal(parameters.per_page, 100);
      return caches;
    } } };
}

test('only trusted default-branch pushes and dispatches write or delete caches', async () => {
  for (const change of [{ eventName: 'pull_request' }, { eventName: 'pull_request_target' },
    { eventName: 'workflow_run' }, { ref: 'refs/heads/feature' }]) {
    const suppliedContext = { ...context, ...change };
    assert.equal(canWriteCaches(suppliedContext), false);
    const supplied = fixture([]);
    supplied.github.paginate = () => { throw new Error('Must not access the API'); };
    assert.deepEqual(await cleanupCaches({ ...supplied, context: suppliedContext }), []);
    assert.equal(await prepareCacheSave({ ...supplied, context: suppliedContext, key: pubPrefix + 'new', reserveBytes: 1 }), false);
  }
  assert.equal(canWriteCaches(context), true);
  assert.equal(canWriteCaches({ ...context, eventName: 'workflow_dispatch' }), true);
});

test('cleanup preserves other refs, unknown caches and current useful large SDKs', () => {
  const caches = [cache(1, `flutter-linux-stable-${flutterVersion}-x64-sdk`),
    cache(2, `flutter-macos-stable-${flutterVersion}-arm64-sdk`),
    cache(3, `flutter-macos-stable-${flutterVersion}-x64-sdk`),
    cache(4, `flutter-windows-stable-${flutterVersion}-x64-sdk`),
    cache(5, 'flutter-linux-stable-1.0.0-x64-sdk'),
    cache(6, 'unknown-large-cache'),
    cache(7, `flutter-windows-stable-${flutterVersion}-x64-sdk`, { ref: 'refs/heads/active' }),
    cache(8, pubPrefix + 'old', { ref: 'refs/pull/42/merge' })];
  assert.deepEqual(planCleanup(caches, options).map(({ id }) => id), [3, 4, 5]);
});

test('new complete Pub replaces legacy partial snapshots; last access cannot keep an old generation', () => {
  const caches = [cache(1, `flutter-pub-linux-x64-${flutterVersion}-legacy`),
    cache(2, pubPrefix + 'old', { last_accessed_at: '2026-12-01T00:00:00Z' }),
    cache(3, pubPrefix + 'current')];
  assert.deepEqual(planCleanup(caches, options).map(({ id }) => id), [1, 2]);
  assert.deepEqual(planCleanup(caches, { ...options, preferredKey: caches[1].key }).map(({ id }) => id), [1, 3]);
});

test('legacy Pub stays available until its OS/ABI has a new complete replacement', () => {
  const caches = [cache(1, `flutter-pub-macos-stable-${flutterVersion}-arm64-sdk-lock`),
    cache(2, pubPrefix + 'current'), cache(3, `bilisail-pub-v2-windows-ARM64-${flutterVersion}-current`)];
  assert.deepEqual(planCleanup(caches, options), []);
});

test('cross-building Intel on ARM64 retires the unused Intel host Pub cache only on the default ref', () => {
  const caches = [cache(1, `bilisail-pub-v2-macos-X64-${flutterVersion}-old`),
    cache(2, `bilisail-pub-v2-macos-ARM64-${flutterVersion}-current`),
    cache(3, `bilisail-pub-v2-macos-X64-${flutterVersion}-branch`, { ref: 'refs/heads/active' })];
  assert.deepEqual(planCleanup(caches, options).map(({ id }) => id), [1]);
});

test('APT and Flatpak rotate weekly while fixed tools stay independent', () => {
  const caches = [cache(1, 'linux-downloads-v1-ubuntu24.04-x64-old'),
    cache(2, 'linux-apt-v2-ubuntu24.04-x64-configuration-week1'),
    cache(3, 'linux-apt-v2-ubuntu24.04-x64-configuration-week2'),
    cache(4, 'linux-flatpak-v1-ubuntu24.04-x64-configuration-week1'),
    cache(5, 'linux-flatpak-v1-ubuntu24.04-x64-configuration-week2')];
  assert.deepEqual(planCleanup(caches, options).map(({ id }) => id), [2, 4]);
  assert.deepEqual(planCleanup([...caches, cache(6, 'linux-tools-v2-ubuntu24.04-x64-sha')], options)
    .map(({ id }) => id), [1, 2, 4]);
});

test('Gradle and wrapper have independent generations and retire old setup-java copies', () => {
  const caches = [cache(1, 'setup-java-Linux-x64-gradle-old'),
    cache(2, 'bilisail-gradle-v1-linux-x64-new'),
    cache(3, 'bilisail-gradle-wrapper-v1-linux-x64-wrapper')];
  assert.deepEqual(planCleanup(caches, options).map(({ id }) => id), [1]);
});

test('MSYS2 keeps one package snapshot per compiler configuration', () => {
  const caches = [cache(1, 'msys2-pkgs-upd:false-conf:x64config-files:old'),
    cache(2, 'msys2-pkgs-upd:false-conf:x64config-files:new'),
    cache(3, 'msys2-pkgs-upd:false-conf:arm64config-files:current')];
  assert.deepEqual(planCleanup(caches, options).map(({ id }) => id), [1]);
});

test('native mux rotates only its own target and does not evict a useful SDK', () => {
  const prefix = 'bilisail-mux-v1-windows-arm64-';
  const caches = [cache(1, `flutter-linux-stable-${flutterVersion}-x64-sdk`),
    cache(2, prefix + 'a'.repeat(64)), cache(3, prefix + 'b'.repeat(64)),
    cache(4, 'bilisail-mux-v1-macos-x64-' + 'c'.repeat(64))];
  assert.deepEqual(planCleanup(caches, options).map(({ id }) => id), [2]);
});

test('space reservations skip low-priority writes rather than deleting another useful family', async () => {
  const supplied = fixture([cache(1, `flutter-linux-stable-${flutterVersion}-x64-sdk`, { size_in_bytes: 8_500_000_000 })]);
  assert.equal(await prepareCacheSave({ ...supplied, key: pubPrefix + 'new', reserveBytes: 600_000_000 }), false);
  assert.deepEqual(supplied.deleted, []);
  assert.match(supplied.warnings[0], /Skipping cache save/);
});

test('rotation can free only its own previous snapshot before a large replacement upload', async () => {
  const supplied = fixture([cache(1, 'other-owned-by-another-workflow', { size_in_bytes: 7_000_000_000 }),
    cache(2, 'linux-flatpak-v1-ubuntu24.04-x64-old', { size_in_bytes: 940_000_000 })]);
  assert.equal(await prepareCacheSave({ ...supplied, key: 'linux-flatpak-v1-ubuntu24.04-x64-new', reserveBytes: 1_200_000_000 }), true);
  assert.deepEqual(supplied.deleted, [2]);
});

test('repository usage includes protected branch/PR caches in the budget', async () => {
  const supplied = fixture([cache(1, pubPrefix + 'pr', { ref: 'refs/pull/42/merge', size_in_bytes: 8_900_000_000 })]);
  assert.equal(await prepareCacheSave({ ...supplied, key: pubPrefix + 'new', reserveBytes: 600_000_000 }), false);
  assert.deepEqual(supplied.deleted, []);
});

test('an insufficient replacement cannot discard the last usable snapshot', async () => {
  const supplied = fixture([cache(1, 'unknown-large-cache', { size_in_bytes: 8_500_000_000 }),
    cache(2, pubPrefix + 'old', { size_in_bytes: 100_000_000 })]);
  assert.equal(await prepareCacheSave({ ...supplied, key: pubPrefix + 'new', reserveBytes: 600_000_000 }), false);
  assert.deepEqual(supplied.deleted, []);
});

test('existing exact cache needs no new upload', async () => {
  const supplied = fixture([cache(1, pubPrefix + 'current')]);
  assert.equal(await prepareCacheSave({ ...supplied, key: pubPrefix + 'current', reserveBytes: 1 }), false);
  assert.deepEqual(supplied.deleted, []);
});

test('API failure prevents unbudgeted writes and cache deletion races tolerate 404', async () => {
  const supplied = fixture([]);
  supplied.github.paginate = async () => { throw new Error('No Actions permission'); };
  assert.equal(await prepareCacheSave({ ...supplied, key: pubPrefix + 'new', reserveBytes: 1 }), false);
  assert.match(supplied.warnings[0], /maintenance failed/);
  const race = fixture([cache(1, `flutter-windows-stable-${flutterVersion}-x64-sdk`)]);
  race.github.rest.actions.deleteActionsCacheById = async () => { throw Object.assign(new Error('Evicted'), { status: 404 }); };
  assert.deepEqual(await cleanupCaches(race), []);
});

test('restore jobs cannot automatically publish SDK or partial Pub caches', () => {
  const action = readFileSync('.github/actions/restore-flutter/action.yml', 'utf8');
  assert.doesNotMatch(action, /uses: actions\/cache@|uses: actions\/cache\/save@/);
  assert.equal((action.match(/pub-cache: false/g) ?? []).length, 2);
  assert.equal((action.match(/cache: false/g) ?? []).length, 4);
  assert.match(action, /pub-cache-key: 'bilisail-pub-v2-:os:-\$\{\{ runner.arch \}\}-:version:'/);
  assert.match(action, /restore-keys:/);
});

test('composite outputs avoid step-only functions and export the requested key on hits and misses', () => {
  const action = readFileSync('.github/actions/restore-flutter/action.yml', 'utf8');
  const outputs = /^outputs:\r?\n([\s\S]*?)^runs:/m.exec(action)?.[1];
  assert.ok(outputs, 'Expected composite action outputs.');
  // Runner 2.338.2 action_yaml.json permits these functions in steps, but not
  // output-value. Workflow-only actionlint does not validate this boundary.
  assert.doesNotMatch(outputs, /\b(hashFiles|success|failure|cancelled|always)\s*\(/);
  const binding = /^  pub-key:\r?\n    value: \$\{\{ (.+?) \}\}/m.exec(outputs)?.[1];
  assert.ok(binding, 'Expected a Pub cache key output binding.');
  const primaryKey = `${pubPrefix}requested-lock-hash`;
  for (const cacheHit of ['true', 'false', '']) {
    const values = { steps: { pub: { outputs: { 'cache-hit': cacheHit,
      'cache-primary-key': primaryKey, 'cache-matched-key': `${pubPrefix}previous-lock-hash` } } } };
    const exported = binding.split('.').reduce((value, name) => value?.[name], values);
    assert.equal(exported, primaryKey, `Wrong save key for cache-hit=${cacheHit}`);
  }
});

test('formatting diagnostics run only after Flutter setup succeeded', () => {
  const workflow = readFileSync('.github/workflows/ci.yml', 'utf8');
  const condition = /name: Show pinned SDK formatting differences\r?\n\s+if: (.+)/.exec(workflow)?.[1];
  assert.ok(condition);
  const evaluate = new Function('failure', 'steps', `return ${condition};`);
  for (const failure of [true, false]) {
    for (const outcome of ['success', 'failure', 'cancelled', 'skipped']) {
      assert.equal(evaluate(() => failure, { flutter: { outcome } }), failure && outcome === 'success');
    }
  }
});

test('platform Pub caches survive native failures only after strict resolution', () => {
  const workflow = readFileSync('.github/workflows/ci.yml', 'utf8');
  const condition = /name: Save platform Pub dependencies\r?\n\s+if: >-\r?\n([\s\S]*?)\s+uses:/.exec(workflow)?.[1];
  assert.ok(condition);
  const expression = condition.replace(/\.([a-z]+(?:-[a-z]+)+)/g, '["$1"]');
  const evaluate = new Function('cancelled', 'needs', 'matrix', 'steps', `return ${expression};`);
  for (const cancelled of [true, false]) {
    for (const ready of ['true', 'false', '']) {
      for (const hit of ['true', 'false', '']) {
        for (const writer of [true, false]) {
          for (const outcome of ['success', 'failure']) {
            const needs = { prepare: { outputs: { 'cache-write': 'true' } } };
            const steps = { flutter: { outputs: { 'pub-hit': hit } },
              package: { outcome, outputs: { 'pub-resolved': ready } } };
            assert.equal(evaluate(() => cancelled, needs, { cache_writer: writer }, steps),
              !cancelled && writer && ready === 'true' && hit !== 'true');
          }
        }
      }
    }
  }
  const build = readFileSync('tool/build-release.ps1', 'utf8');
  const source = build.indexOf('$sourceDirty = [bool]$sourceChanges');
  const resolve = build.indexOf("Invoke-BuildDependencyCommand flutter @('pub', 'get', '--enforce-lockfile')");
  const ready = build.indexOf("'pub-resolved=true'");
  const native = build.indexOf("Invoke-BuildCommand python @((Join-Path $PSScriptRoot 'prepare-sqlite-assets.py')");
  assert.ok(source >= 0 && source < resolve && resolve < ready && ready < native);
  assert.equal((workflow.match(/name: Save platform Pub dependencies/g) ?? []).length, 1);
});

test('Gradle wrapper caches the pinned binary distribution with a verified checksum', () => {
  const properties = readFileSync('android/gradle/wrapper/gradle-wrapper.properties', 'utf8');
  assert.match(properties, /^distributionUrl=https\\:\/\/services\.gradle\.org\/distributions\/gradle-[\d.]+-bin\.zip\r?$/m);
  assert.match(properties, /^distributionSha256Sum=[a-f0-9]{64}\r?$/m);
  assert.doesNotMatch(properties, /-all\.zip/);
});
