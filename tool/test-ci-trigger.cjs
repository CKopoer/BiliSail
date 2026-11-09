const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { shouldRunCi } = require('./ci-trigger.cjs');

const context = { repo: { owner: 'CKopoer', repo: 'BiliSail' }, eventName: 'push',
  ref: 'refs/heads/codex/example', payload: { repository: { default_branch: 'master' } } };

function fixture(pulls = []) {
  const requests = [];
  const warnings = [];
  const list = () => {};
  return { requests, warnings,
    core: { warning: (message) => warnings.push(message) },
    github: { rest: { pulls: { list } }, paginate: async (method, parameters) => {
      assert.equal(method, list);
      requests.push(parameters);
      return pulls;
    } } };
}

test('branch pushes run until an open PR covers the same repository head', async () => {
  const options = fixture();
  assert.equal(await shouldRunCi({ ...options, context }), true);
  assert.equal(options.requests[0].head, 'CKopoer:codex/example');
  assert.equal(options.requests[0].state, 'open');
  const covered = fixture([{ head: { repo: { full_name: 'ckopoer/bilisail' } } }]);
  assert.equal(await shouldRunCi({ ...covered, context }), false);
});

test('PR, dispatch and default-branch pushes never depend on the PR lookup', async () => {
  for (const change of [{ eventName: 'pull_request' }, { eventName: 'workflow_dispatch' },
    { ref: 'refs/heads/master' }]) {
    const options = fixture([{ head: { repo: { full_name: 'CKopoer/BiliSail' } } }]);
    assert.equal(await shouldRunCi({ ...options, context: { ...context, ...change } }), true);
    assert.equal(options.requests.length, 0);
  }
});

test('deleted fork heads and other repositories cannot suppress branch CI', async () => {
  const options = fixture([{ head: { repo: null } }, { head: { repo: { full_name: 'someone/BiliSail' } } }]);
  assert.equal(await shouldRunCi({ ...options, context }), true);
});

test('PR API failure runs CI and records why deduplication was unavailable', async () => {
  const options = fixture();
  options.github.paginate = async () => { throw new Error('API unavailable'); };
  assert.equal(await shouldRunCi({ ...options, context }), true);
  assert.match(options.warnings[0], /running push CI/);
});

test('required check fails when prepare fails, and only skips deliberate duplicates', () => {
  const workflow = readFileSync('.github/workflows/ci.yml', 'utf8');
  const condition = /  check:\r?\n[\s\S]*?    if: \$\{\{ (.+) \}\}/.exec(workflow)?.[1];
  assert.ok(condition);
  const evaluate = new Function('needs', 'always',
    `return ${condition.replace('outputs.run-ci', 'outputs["run-ci"]')};`);
  for (const run of [undefined, 'true', 'false']) {
    assert.equal(evaluate({ prepare: { outputs: { 'run-ci': run } } }, () => true), run !== 'false');
  }
  assert.match(workflow, /if \[\[ "\$PREPARE_RESULT" != success/);
});

test('automatic cancellation keeps manual and reusable release dispatches independent', () => {
  const workflow = readFileSync('.github/workflows/ci.yml', 'utf8');
  const condition = /cancel-in-progress: \$\{\{ (.+) \}\}/.exec(workflow)?.[1];
  const evaluate = new Function('github', `return ${condition};`);
  for (const event of ['push', 'pull_request', 'workflow_dispatch', 'workflow_call']) {
    assert.equal(evaluate({ event_name: event }), ['push', 'pull_request'].includes(event));
  }
  assert.match(workflow, /group: ci-\$\{\{ github.workflow \}\}/);
  assert.match(workflow, /github.event_name == 'workflow_dispatch' && github.run_id/);
  const release = readFileSync('.github/workflows/release.yml', 'utf8');
  assert.match(release, /reuse_ci_build:\r?\n[\s\S]*?default: true/);
});

test('root test matrix covers every shard exactly once with the same total', () => {
  const workflow = readFileSync('.github/workflows/ci.yml', 'utf8');
  const rootJob = /  root-tests:\r?\n([\s\S]*?)\r?\n  package-tests:/.exec(workflow)?.[1];
  assert.ok(rootJob);
  const shards = /shard: \[([\d, ]+)\]/.exec(rootJob)?.[1].split(',').map(Number);
  const total = Number(/-TotalShards (\d+)/.exec(rootJob)?.[1]);
  assert.ok(total > 1);
  assert.deepEqual(shards, Array.from({ length: total }, (_, index) => index));
  assert.match(rootJob, /-ShardIndex \$\{\{ matrix.shard \}\}/);
});

test('platform builds overlap root tests while the required quality gate still waits for them', () => {
  const workflow = readFileSync('.github/workflows/ci.yml', 'utf8');
  const needs = (job) => new RegExp(`^  ${job}:\\r?\\n[\\s\\S]*?^    needs: \\[([^\\]]+)\\]`, 'm')
    .exec(workflow)?.[1].split(',').map((name) => name.trim());
  assert.deepEqual(needs('build'), ['prepare', 'lint', 'package-tests', 'native-mux']);
  assert.ok(needs('check').includes('root-tests'));
  assert.ok(needs('check').includes('native-mux'));
  const mux = readFileSync('.github/actions/restore-mux/action.yml', 'utf8');
  assert.doesNotMatch(mux, /restore-keys:/);
});

test('Windows compiler installation follows validated mux restore and skips warm builds', () => {
  const workflow = readFileSync('.github/workflows/ci.yml', 'utf8');
  const compiler = /- name: Set up the Windows mux compiler on cache miss\r?\n([\s\S]*?)- name: Retry Windows mux/.exec(workflow)?.[1];
  assert.ok(compiler);
  assert.ok(workflow.indexOf('id: mux-cache') < workflow.indexOf('id: windows-mux'));
  const condition = /if: (.+)/.exec(compiler)?.[1];
  const evaluate = new Function('matrix', 'steps', 'startsWith',
    `return ${condition.replace('steps.mux-cache', 'steps["mux-cache"]')};`);
  for (const target of ['windows-x64', 'windows-arm64', 'linux-x64']) {
    for (const valid of ['true', 'false', undefined]) {
      assert.equal(evaluate({ target }, { 'mux-cache': { outputs: { valid } } },
        (value, prefix) => value.startsWith(prefix)), target.startsWith('windows-') && valid !== 'true');
    }
  }
  const lock = JSON.parse(readFileSync('tool/windows-mux-toolchains.json', 'utf8'));
  assert.equal(workflow.split(`uses: msys2/setup-msys2@${lock.setupAction}`).length - 1, 2);
  assert.match(compiler, /install: \$\{\{ steps.mux-cache.outputs.install \}\}/);
  assert.doesNotMatch(workflow, /libarchive|setup-windows-native-tar/);
  assert.match(workflow, /-MsysRoot \$absentCompiler/);
});
