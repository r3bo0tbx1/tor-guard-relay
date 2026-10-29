#!/usr/bin/env node
// Exercise Renovate itself: rule order and advisory overrides matter as much as schema validity.
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';

const renovateRoot = process.argv[2];
assert(renovateRoot, 'Usage: node scripts/testing/check-renovate.mjs /path/to/node_modules/renovate');
const root = process.cwd();
const readJson = async file => JSON.parse(await readFile(file, 'utf8'));
const installed = await readJson(path.join(renovateRoot, 'package.json'));
const tools = await readJson(path.join(root, 'build/security-tools.json'));
assert.equal(installed.version, tools.renovate, 'Use the reviewed Renovate test version');
const load = file => import(pathToFileURL(path.resolve(renovateRoot, 'dist', file)).href);
const { init } = await load('logger/index.js');
await init();
const { getConfig } = await load('config/defaults.js');
const { mergeChildConfig } = await load('config/utils.js');
const { resolveConfigPresets } = await load('config/presets/index.js');
const { applyPackageRules } = await load('util/package-rules/index.js');
const { get } = await load('modules/versioning/index.js');
const { filterVersions } = await load('workers/repository/process/lookup/filter.js');
const { applyVulnerabilityFixFilter } = await load('workers/repository/process/lookup/vulnerability.js');
const { Vulnerabilities } = await load('workers/repository/process/vulnerabilities.js');
const { extractPackageFile } = await load('modules/manager/custom/regex/index.js');
const { matchRegexOrGlobList } = await load('util/string-match.js');
const { doAutoReplace } = await load('workers/repository/update/branch/auto-replace.js');
const { GlobalConfig } = await load('config/global.js');
const { extractPackageFile: extractActions } = await load('modules/manager/github-actions/extract.js');
const { isScheduledNow, hasValidSchedule } = await load('workers/repository/update/branch/schedule.js');
const requireRenovate = createRequire(path.resolve(renovateRoot, 'package.json'));
const semver = requireRenovate('semver');
const luxonPackage = requireRenovate.resolve('luxon/package.json');
const luxon = await readJson(luxonPackage);
// Renovate imports the ESM clock; Luxon's CommonJS clock is a separate instance.
const { Settings } = await import(pathToFileURL(path.resolve(path.dirname(luxonPackage), luxon.exports['.'].import)).href);

const raw = await readJson(path.join(root, '.github/renovate.json'));
const { config: resolved } = await resolveConfigPresets(raw);
const config = mergeChildConfig(getConfig(), resolved);
const versioning = get('gomod');
const lock = await readFile(path.join(root, 'build/lyrebird/go.mod'), 'utf8');
const selected = name => {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return lock.match(new RegExp(`^\\s*${escaped} (v\\S+)`, 'm'))?.[1];
};
const input = (name, current, updateType = 'patch', depType = 'indirect') => ({
  ...config, manager: 'gomod', datasource: 'go', versioning: 'gomod',
  packageFile: 'build/lyrebird/go.mod', depName: name, packageName: name,
  depType, currentValue: current, currentVersion: current, updateType,
});
// Renovate reapplies rules after current-version resolution and update classification.
const evaluate = async (dependency, extraRules = []) => {
  let result = { ...dependency, packageRules: [...config.packageRules, ...extraRules] };
  for (const stage of ['pre-lookup', 'current-version', 'update-type']) {
    result = await applyPackageRules(result, stage);
  }
  return result;
};
const filtered = (dependency, versions) => filterVersions(
  dependency, dependency.currentValue, versions.at(-1),
  versions.map(version => ({ version })), versioning,
).map(release => release.version);

let checks = 0;
function checked(message) { checks++; console.log(`✅ ${message}`); }

GlobalConfig.set({ localDir: root });
const workflow = '.github/workflows/validate.yml';
const extractedActions = await extractActions(await readFile(workflow, 'utf8'), workflow, config);
const nodeDependencies = extractedActions.deps.filter(dep => dep.depName === 'node');
assert.equal(nodeDependencies.length, 1, 'Extract the validator runtime from the actual workflow');
const nodeDependency = await evaluate({ ...config, ...nodeDependencies[0],
  manager: 'github-actions', packageFile: workflow, updateType: 'major' });
assert(semver.satisfies(process.versions.node, installed.engines.node), 'Run with a supported validator runtime');
assert(nodeDependency.allowedVersions, 'Keep a compatibility constraint on the validator runtime');
assert(semver.subset(nodeDependency.allowedVersions, installed.engines.node),
  'Review the Node rule when the pinned validator changes its engines requirement');
const nodeVersions = get(nodeDependencies[0].versioning ?? 'node');
assert(nodeVersions.matches(process.versions.node, nodeDependency.allowedVersions));
assert(!nodeVersions.matches('26.13.0', nodeDependency.allowedVersions),
  'The unsupported Node 26 proposal must not be offered for this validator');
checked('Actual workflow runtime updates stay within the pinned validator engine requirement');
const otherNode = await evaluate({ ...config, ...nodeDependencies[0],
  manager: 'github-actions', packageFile: '.github/workflows/unrelated.yml', updateType: 'major' });
assert.equal(otherNode.allowedVersions, undefined, 'Do not constrain unrelated Node workflows');
checked('Validator runtime restriction does not affect unrelated Node dependencies');

const validatorInput = { ...config, manager: 'custom.regex', datasource: 'npm',
  packageFile: 'build/security-tools.json', depName: 'renovate', packageName: 'renovate',
  currentValue: tools.renovate, currentVersion: tools.renovate };
const validator = await evaluate({ ...validatorInput, updateType: 'patch' });
assert.deepEqual(validator.schedule, ['* 0-3 * * 1']);
assert.equal(hasValidSchedule(validator.schedule)[0], true);
assert.equal(validator.updateNotScheduled, true);
assert.equal(validator.rebaseWhen, 'behind-base-branch');
assert.equal(validator.automerge, false);
assert.equal(validator.groupName, config.groupName, 'Keep the existing per-major PR identity');
assert.equal(validator.groupSlug, config.groupSlug);
const originalNow = Settings.now;
try {
  for (const [timestamp, allowed] of [
    ['2026-11-01T23:59:00Z', false], ['2026-11-02T00:00:00Z', true],
    ['2026-11-02T03:59:00Z', true], ['2026-11-02T04:00:00Z', false],
    ['2026-11-03T01:00:00Z', false],
  ]) {
    Settings.now = () => Date.parse(timestamp);
    assert.equal(isScheduledNow(validator), allowed, timestamp);
  }
} finally {
  Settings.now = originalNow;
}
checked('Validator creation window has correct UTC boundaries; open PR updates and review stay enabled');
const validatorAlert = await evaluate({ ...validatorInput, updateType: 'patch', isVulnerabilityAlert: true });
assert.deepEqual(validatorAlert.schedule, ['at any time']);
assert.equal(validatorAlert.prCreation, 'immediate');
assert.equal(validatorAlert.minimumReleaseAge, '0 days');
assert.equal(validatorAlert.automerge, false);
checked('Received validator security alerts bypass routine scheduling and still require review');
for (const dep of [
  { ...validatorInput, datasource: 'go', depName: 'golang.org/x/vuln', packageName: 'golang.org/x/vuln' },
  { ...config, manager: 'dockerfile', datasource: 'docker', depName: 'alpine', packageName: 'alpine' },
]) {
  const result = await evaluate({ ...dep, updateType: 'patch' });
  assert.deepEqual(result.schedule, ['at any time']);
}
checked('Go security tooling and Alpine updates retain their existing immediate eligibility');

const boundaries = [
  ['github.com/pion/webrtc/v4', 'v4.2.20', 'v4.2.23'],
  ['github.com/pion/ice/v4', 'v4.4.2', 'v4.4.7'],
  ['github.com/pion/turn/v5', 'v5.1.0', 'v5.1.2'],
  ['github.com/pion/mdns/v2', 'v2.2.0', 'v2.2.2'],
  ['github.com/pion/srtp/v3', 'v3.0.13', 'v3.1.3'],
];
for (const [name, current, incompatible] of boundaries) {
  const dependency = await evaluate(input(name, current));
  assert.equal(selected(name), current, `${name}: reassess compatibility rules when the lock changes`);
  assert.notEqual(dependency.enabled, false, `${name}: keep version lookups enabled`);
  assert(versioning.matches(current, dependency.allowedVersions), `${name}: selected version exceeds limit`);
  assert.deepEqual(filtered(dependency, [current, incompatible]), [], name);
  checked(`${name}: reviewed version allowed; migration proposal filtered`);
}

const net = await evaluate(input('golang.org/x/net', 'v0.60.0', 'minor', 'require'));
assert.deepEqual(filtered(net, ['v0.60.0', 'v0.61.0']), ['v0.61.0']);
assert.equal(net.groupSlug, 'lyrebird-go-dependencies');
assert.equal(net.automerge, false);
checked('Compatible direct Go updates remain grouped and eligible');

const rtcp = await evaluate(input('github.com/pion/rtcp', 'v1.2.18'));
assert.equal(rtcp.groupSlug, net.groupSlug);
assert.notEqual(rtcp.enabled, false);
checked('Compatible indirect patch updates share the same group');

const rtp = await evaluate(input('github.com/pion/rtp', 'v1.10.5', 'major'));
assert.equal(rtp.enabled, false);
checked('Ordinary indirect major import-path migration is deferred');
const directMajor = await evaluate(input('example.com/direct', 'v1.0.0', 'major', 'require'));
assert.notEqual(directMajor.enabled, false);
checked('Direct major updates are still available for separate review');

// OSV's real adapter generates its advisory constraint after repository rules.
const osv = new Vulnerabilities(undefined);
for (const [name, current, fixed] of [
  boundaries[0], ['github.com/pion/rtp', 'v1.10.5', 'v2.0.0'],
]) {
  const advisory = osv.vulnerabilityToPackageRules({
    vulnerability: { id: 'TEST-SECURITY-FIX', summary: 'Synthetic policy fixture', severity: [] },
    affected: { package: { ecosystem: 'Go', name }, ranges: [] },
    packageName: name, depType: 'indirect', depVersion: current,
    fixedVersion: `>=${fixed}`, datasource: 'go', packageFileConfig: config,
  });
  assert(advisory);
  const result = await evaluate(input(name, current, 'major'), [advisory]);
  assert.notEqual(result.enabled, false, name);
  assert.deepEqual(filtered(result, [current, fixed]), [fixed], 'Keep OSV fix range; remove routine ceiling');
  assert.equal(result.groupName, null);
  assert.equal(result.groupSlug, null);
  assert.equal(result.prCreation, 'immediate');
  assert.equal(result.automerge, false);
  checked(`${name}: OSV fix crosses routine restrictions and requires review`);
}

// GitHub advisories carry vulnerabilityFixVersion, rather than OSV's allowedVersions.
for (const [name, current, fixed] of [
  boundaries[0], ['github.com/pion/rtp', 'v1.10.5', 'v2.0.0'],
]) {
  const advisory = {
    matchDatasources: ['go'], matchPackageNames: [name], matchCurrentVersion: `<${fixed}`,
    vulnerabilityFixVersion: fixed, isVulnerabilityAlert: true,
    force: { ...config.vulnerabilityAlerts },
  };
  const result = await evaluate(input(name, current, 'major'), [advisory]);
  assert.notEqual(result.enabled, false);
  const releases = filtered(result, [current, fixed]).map(version => ({ version }));
  const security = applyVulnerabilityFixFilter(result, {}, versioning, releases);
  assert.deepEqual(security.releases.map(release => release.version), [fixed]);
  assert.equal(result.prCreation, 'immediate');
  assert.equal(result.groupName, null);
  assert.equal(result.groupSlug, null);
  assert.equal(result.automerge, false);
  checked(`${name}: GitHub fix crosses routine restrictions and retains its fix filter`);
}

const source = await applyPackageRules({ ...config, manager: 'custom.regex', datasource: 'git-refs',
  depName: 'Lyrebird source', packageName: raw.customManagers[0].packageNameTemplate }, 'pre-lookup');
assert.notEqual(source.enabled, false);
assert.equal(source.groupName, '🧅 Lyrebird source pin');
assert.equal(source.automerge, false);
checked('Upstream source monitoring remains independent and enabled');
assert.equal(config.osvVulnerabilityAlerts, true);
assert.equal(config.vulnerabilityAlerts.enabled, true);
assert.equal(config.commitMessageAction, 'update');
assert(!config.postUpdateOptions.includes('gomodTidy'), 'Do not tidy the source-less lock directory');
checked('Security monitoring, lowercase summaries and source-aware lock maintenance retained');

const alpineManagers = raw.customManagers.filter(manager => manager.depNameTemplate === 'alpine');
assert.equal(alpineManagers.length, 2, 'Track current Alpine references and the OCI label separately');
const alpineVersion = (await readFile('Dockerfile', 'utf8')).match(/^FROM alpine:(\d+\.\d+\.\d+)/m)[1];
const nextAlpine = alpineVersion.replace(/\d+$/, patch => Number(patch) + 1);
const trackedFiles = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'],
  { encoding: 'utf8' }).trim().split('\n');
const covered = new Set();
const alpineScratch = await mkdtemp(path.join(tmpdir(), 'relay-renovate-alpine-'));
GlobalConfig.set({ localDir: alpineScratch });
try {
  for (const file of new Set(trackedFiles)) {
    if (!/\.(?:md|sh|ya?ml|json)$/.test(file) && file !== 'Dockerfile') continue;
    const text = await readFile(file, 'utf8');
    const history = file === 'CHANGELOG.md' || file.startsWith('docs/releases/');
    for (const manager of alpineManagers) {
      const matches = matchRegexOrGlobList(file, manager.managerFilePatterns);
      if (history) assert.equal(matches, false, `${file}: historical facts must not be proposed for update`);
      if (!matches) continue;
      const extracted = extractPackageFile(text, file, manager);
      if (!extracted) continue;
      let updated = text;
      for (const [depIndex, dep] of extracted.deps.entries()) {
        assert.equal(dep.currentValue, alpineVersion, `${file}: current Alpine reference drifted`);
        const rule = await applyPackageRules({ ...config, manager: 'custom.regex', ...dep,
          packageName: dep.packageName ?? dep.depName,
          packageFile: file, updateType: 'patch' }, 'update-type');
        assert.equal(rule.groupName, '🐳 Alpine Base Image');
        assert.equal(rule.groupSingleUpdates, true);
        assert.equal(rule.automerge, false);
        updated = await doAutoReplace({ ...config, ...manager, ...extracted, ...dep,
          // Renovate's update worker uses the internal, unprefixed manager name.
          manager: 'regex', packageFile: file, depIndex, newValue: nextAlpine }, updated, false);
        assert.equal(typeof updated, 'string', `${file}: Renovate must produce a real replacement`);
      }
      const after = extractPackageFile(updated, file, manager);
      assert.equal(after.deps.length, extracted.deps.length, `${file}: preserve every reference`);
      assert(after.deps.every(dep => dep.currentValue === nextAlpine), `${file}: update every occurrence`);
      if (file === 'Dockerfile') {
        assert.equal(updated.match(/^FROM alpine:.*$/m)[0], text.match(/^FROM alpine:.*$/m)[0],
          'The custom manager updates only metadata; the Dockerfile manager owns FROM and its digest');
      }
      covered.add(file);
    }
    if (!history && /(?:alpine:|Alpine(?: Linux)? )\d+\.\d+\.\d+/.test(text)) {
      assert(covered.has(file), `${file}: no Renovate manager covers this current Alpine reference`);
    }
  }
} finally {
  await rm(alpineScratch, { recursive: true, force: true });
}
assert(covered.has('README.md') && covered.has('SECURITY.md') && covered.has('Dockerfile'));
checked(`Alpine base metadata and ${covered.size - 1} current files share reviewed, working replacements`);
checked('Alpine automation preserves historical release notes and changelog records');
console.log(`🧅 ${checks} Renovate behavior checks passed with ${installed.version}`);
