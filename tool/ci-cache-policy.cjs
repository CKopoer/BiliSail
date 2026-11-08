const { readFileSync } = require('node:fs');

// Decimal bytes leave headroom beneath GitHub's default repository limit.
const cacheBudgetBytes = 9_000_000_000;

function canWriteCaches(context) {
  return ['push', 'workflow_dispatch'].includes(context.eventName) &&
    context.ref === `refs/heads/${context.payload.repository.default_branch}`;
}

function cacheFamily(key, flutterVersion) {
  const mux = /^bilisail-mux-v1-(windows-(?:x64|arm64)|macos-(?:x64|arm64)|android-arm64|ios-arm64|linux-x64)-[a-f0-9]{64}$/.exec(key);
  if (mux) return { name: `mux-${mux[1]}` };
  const sdk = /^flutter-(linux|macos|windows)-stable-([\d.]+)-(x64|arm64)(?:-|$)/i.exec(key);
  if (sdk) {
    const [, os, version, architecture] = sdk;
    const enabled = `${os}-${architecture}`.toLowerCase();
    return { name: `sdk-${enabled}`, retired: version !== flutterVersion ||
      !['linux-x64', 'macos-arm64'].includes(enabled) };
  }
  const pub = /^(bilisail-pub-v2|flutter-pub)-(linux|macos|windows)-(.+)$/i.exec(key);
  if (pub) {
    const architecture = /(?:^|-)(x64|arm64)(?:-|$)/i.exec(pub[3])?.[1]?.toLowerCase();
    const version = /\d+\.\d+\.\d+/.exec(pub[3])?.[0];
    if (!architecture || !version) return null;
    return { name: `pub-${pub[2].toLowerCase()}-${architecture}`,
      retired: version !== flutterVersion || (pub[2].toLowerCase() === 'macos' && architecture === 'x64'),
      legacy: pub[1] === 'flutter-pub' };
  }
  if (key.startsWith('linux-downloads-v1-ubuntu24.04-x64-')) {
    return { name: 'linux-downloads', legacy: true };
  }
  if (key.startsWith('linux-apt-v2-ubuntu24.04-x64-')) return { name: 'linux-apt' };
  if (key.startsWith('linux-tools-v2-ubuntu24.04-x64-')) return { name: 'linux-tools' };
  if (key.startsWith('linux-flatpak-v1-ubuntu24.04-x64-')) return { name: 'linux-flatpak' };
  if (key.startsWith('bilisail-gradle-wrapper-v1-linux-x64-')) return { name: 'gradle-wrapper' };
  if (key.startsWith('bilisail-gradle-v1-linux-x64-')) return { name: 'gradle' };
  if (key.startsWith('setup-java-Linux-x64-gradle-wrapper-')) return { name: 'gradle-wrapper', legacy: true };
  if (key.startsWith('setup-java-Linux-x64-gradle-')) return { name: 'gradle', legacy: true };
  const msys = /^msys2-pkgs-upd:(true|false)-conf:([^-]+)-files:/.exec(key);
  if (msys) return { name: `msys2-${msys[1]}-${msys[2]}` };
  return null;
}

function planCleanup(caches, { ref, flutterVersion, preferredKey = '' }) {
  const owned = caches.filter((cache) => cache.ref === ref)
    .map((cache) => ({ cache, family: cacheFamily(cache.key, flutterVersion) }))
    .filter(({ family }) => family);
  const groups = Map.groupBy(owned, ({ family }) => family.name);
  return owned.filter(({ cache, family }) => {
    if (cache.key === preferredKey) return false;
    if (family.retired) return true;
    // Keep the last legacy download bundle until BOTH replacements exist.
    if (family.name === 'linux-downloads' && groups.has('linux-apt') && groups.has('linux-tools')) return true;
    const ranked = groups.get(family.name).filter(({ family: candidate }) => !candidate.retired).sort((a, b) =>
      Number(b.cache.key === preferredKey) - Number(a.cache.key === preferredKey) ||
      Number(Boolean(a.family.legacy)) - Number(Boolean(b.family.legacy)) ||
      Date.parse(b.cache.created_at) - Date.parse(a.cache.created_at) || b.cache.id - a.cache.id);
    return cache.id !== ranked[0].cache.id;
  }).map(({ cache }) => cache);
}

async function cleanupCaches({ github, context, core, preferredKey = '' }) {
  if (!canWriteCaches(context)) return [];
  const caches = await github.paginate(github.rest.actions.getActionsCacheList, {
    ...context.repo, per_page: 100,
  });
  const flutterVersion = readFileSync('.flutter-version', 'utf8').trim();
  const obsolete = planCleanup(caches, { ref: context.ref, flutterVersion, preferredKey });
  await deleteCaches({ github, context, core, caches: obsolete });
  const removed = new Set(obsolete.map(({ id }) => id));
  return caches.filter(({ id }) => !removed.has(id));
}

async function deleteCaches({ github, context, core, caches }) {
  for (const cache of caches) {
    try {
      await github.rest.actions.deleteActionsCacheById({ ...context.repo, cache_id: cache.id });
      core.info(`Removed obsolete cache ${cache.key} (${cache.size_in_bytes} bytes).`);
    } catch (error) {
      if (error.status !== 404) throw error;
      // Another writer or GitHub's eviction may have removed it already.
    }
  }
}

async function prepareCacheSave({ github, context, core, key, reserveBytes }) {
  if (!canWriteCaches(context)) return false;
  if (!key || !Number.isSafeInteger(reserveBytes) || reserveBytes <= 0) {
    throw new Error('Cache saves require a key and a positive byte reservation.');
  }
  try {
    const caches = await cleanupCaches({ github, context, core });
    if (caches.some((cache) => cache.key === key && cache.ref === context.ref)) return false;
    let usedBytes = caches.reduce((total, cache) => total + cache.size_in_bytes, 0);
    if (usedBytes + reserveBytes > cacheBudgetBytes) {
      // The replacement is already prepared locally. If necessary, rotate its
      // own previous snapshot before upload rather than evicting another family.
      const flutterVersion = readFileSync('.flutter-version', 'utf8').trim();
      const family = cacheFamily(key, flutterVersion);
      const replaced = caches.filter((cache) => cache.ref === context.ref &&
        family && cacheFamily(cache.key, flutterVersion)?.name === family.name);
      const replacedBytes = replaced.reduce((total, cache) => total + cache.size_in_bytes, 0);
      if (usedBytes - replacedBytes + reserveBytes <= cacheBudgetBytes) {
        await deleteCaches({ github, context, core, caches: replaced });
        usedBytes -= replacedBytes;
      }
    }
    if (usedBytes + reserveBytes > cacheBudgetBytes) {
      core.warning(`Skipping cache save: ${usedBytes} used + ${reserveBytes} reserved exceeds ${cacheBudgetBytes} bytes. Existing useful caches are retained.`);
      return false;
    }
    return true;
  } catch (error) {
    // Cache maintenance must not turn a valid build into a failure, or write
    // without knowing whether there is room beneath the repository budget.
    core.warning(`Skipping cache save because maintenance failed: ${error.message}`);
    return false;
  }
}

module.exports = { canWriteCaches, cacheFamily, planCleanup, cleanupCaches, prepareCacheSave };
