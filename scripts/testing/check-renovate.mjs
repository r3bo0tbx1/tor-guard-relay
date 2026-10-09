#!/usr/bin/env node
// Exercise Renovate itself: rule order and advisory overrides matter as much as schema validity.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

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
console.log(`🧅 ${checks} Renovate behavior checks passed with ${installed.version}`);
