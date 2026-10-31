const { createHash } = require('node:crypto');
const { createReadStream } = require('node:fs');
const { readdir, readFile } = require('node:fs/promises');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const path = require('node:path');

const packageSuffixes = {
  'android-arm64': ['.apk'],
  'windows-x64': ['.msix', '.msi', '.exe', '.cer'],
  'macos-arm64': ['.dmg'],
  'macos-x64': ['.dmg'],
  'ios-arm64': ['-unsigned.ipa'],
  'linux-x64': ['.AppImage', '.flatpak'],
};

function validateSelection(version, targets) {
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+(0|[1-9]\d*)$/.test(version) ||
      !Array.isArray(targets) || !targets.length ||
      new Set(targets).size !== targets.length ||
      targets.some((target) => !Object.hasOwn(packageSuffixes, target))) {
    throw new Error('Expected a valid release version and distinct supported targets.');
  }
}

async function planReleaseBuilds({ github, context, version, targets,
  reuseCiBuild, now = Date.now() }) {
  validateSelection(version, targets);
  if (!reuseCiBuild) return { reused: [], buildTargets: targets };
  let reused = [];
  const repository = `${context.repo.owner}/${context.repo.repo}`.toLowerCase();
  const pages = github.paginate.iterator(github.rest.actions.listWorkflowRuns, {
    ...context.repo, workflow_id: 'ci.yml', head_sha: context.sha,
    status: 'completed', per_page: 100,
  });
  for await (const page of pages) {
    // paginate.iterator unwraps the REST workflow_runs envelope into page.data.
    for (const run of page.data) {
      // A PR can have temporary signing keys even when its source matches.
      if (run.status !== 'completed' ||
          run.head_sha !== context.sha || !['push', 'workflow_dispatch'].includes(run.event) ||
          run.head_repository?.full_name?.toLowerCase() !== repository) continue;
      const artifacts = await github.paginate(github.rest.actions.listWorkflowRunArtifacts, {
        ...context.repo, run_id: run.id, per_page: 100,
      });
      const candidates = targets.filter((target) => !reused.some((item) => item.target === target))
        .filter((target) => artifacts.filter((artifact) =>
          artifact.name === `BiliSail-${target}-${version}-packages` &&
          artifact.expired === false && artifact.size_in_bytes > 0 &&
          Date.parse(artifact.expires_at) > now).length === 1);
      if (!candidates.length) continue;
      const jobs = await github.paginate(github.rest.actions.listJobsForWorkflowRun, {
        ...context.repo, run_id: run.id, filter: 'latest', per_page: 100,
      });
      const passed = (name) => jobs.some((job) => job.name === name &&
        job.status === 'completed' && job.conclusion === 'success');
      // Other platform failures do not invalidate this platform's completed build.
      if (!passed('Analyze and test')) continue;
      reused = [...reused, ...candidates.filter((target) => passed(`Build ${target}`))
        .map((target) => ({ target, runId: run.id, runUrl: run.html_url,
          artifactName: `BiliSail-${target}-${version}-packages` }))];
      if (reused.length === targets.length) break;
    }
    if (reused.length === targets.length) break;
  }
  return {
    reused: targets.flatMap((target) => reused.filter((item) => item.target === target)),
    buildTargets: targets.filter((target) => !reused.some((item) => item.target === target)),
  };
}

async function downloadReusedArtifacts({ reused, repository, directory,
  execute = promisify(execFile) }) {
  for (const source of reused) {
    await execute('gh', ['run', 'download', String(source.runId),
      '--repo', repository, '--name', source.artifactName, '--dir', directory]);
  }
}

async function hashFile(file) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}

async function verifyReleaseAssets({ directory, version, targets, sourceRevision,
  flutterVersion, pubspecLockSha256s }) {
  validateSelection(version, targets);
  const expectedFiles = targets.flatMap((target) => {
    const prefix = `BiliSail-${version}-${target}`;
    return [...packageSuffixes[target], '.build-info.json', '.mux-source.zip']
      .flatMap((suffix) => [prefix + suffix, prefix + suffix + '.sha256']);
  }).sort();
  const entries = await readdir(directory, { withFileTypes: true });
  const actualFiles = entries.map((entry) => entry.name).sort();
  if (entries.some((entry) => !entry.isFile()) ||
      JSON.stringify(actualFiles) !== JSON.stringify(expectedFiles)) {
    throw new Error('Release assets must contain exactly the selected packages, metadata, sources and checksums.');
  }
  for (const name of actualFiles.filter((file) => !file.endsWith('.sha256'))) {
    const checksum = await readFile(path.join(directory, name + '.sha256'), 'utf8');
    const hash = await hashFile(path.join(directory, name));
    if (checksum.trimEnd() !== `${hash}  ${name}`) {
      throw new Error(`SHA-256 mismatch for ${name}.`);
    }
  }
  for (const target of targets) {
    const name = `BiliSail-${version}-${target}.build-info.json`;
    const metadata = JSON.parse((await readFile(path.join(directory, name), 'utf8'))
      .replace(/^\uFEFF/, ''));
    if (metadata.version !== version || metadata.target !== target ||
        metadata.sourceRevision !== sourceRevision || metadata.sourceDirty !== false ||
        metadata.flutterVersion !== flutterVersion ||
        !pubspecLockSha256s.includes(metadata.pubspecLockSha256)) {
      throw new Error(`Build provenance does not match this release for ${target}.`);
    }
    if (target === 'android-arm64' && metadata.signing !== 'configured-keystore') {
      throw new Error('Android release requires the configured release keystore.');
    }
  }
}

module.exports = { planReleaseBuilds, downloadReusedArtifacts, verifyReleaseAssets };
