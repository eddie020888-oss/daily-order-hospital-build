// DRAFT, NOT EXECUTED. Only GET requests to Apple's fixed API host.
// No P8/JWT/private-key bytes, certificate bodies or other-app names enter logs.
import { createPrivateKey, sign, X509Certificate } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const ORIGIN = 'https://api.appstoreconnect.apple.com';
const allowedPaths = new Set(['/v1/apps', '/v1/bundleIds', '/v1/certificates', '/v1/profiles']);

export function decodeP8(value) {
  const text = String(value || '').trim();
  const pem = text.startsWith('-----BEGIN PRIVATE KEY-----') ? text : Buffer.from(text, 'base64').toString('utf8');
  if (!pem.startsWith('-----BEGIN PRIVATE KEY-----')) throw new Error('ASC_KEY_FORMAT');
  return pem;
}

export function makeToken(env, now = Math.floor(Date.now() / 1000)) {
  if (!/^[A-Za-z0-9]{8,20}$/.test(env.ASC_KEY_ID || '')) throw new Error('ASC_KEY_ID_MISSING');
  if (!/^[a-fA-F0-9-]{36}$/.test(env.ASC_ISSUER_ID || '')) throw new Error('ASC_ISSUER_ID_MISSING');
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: env.ASC_KEY_ID, typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ iss: env.ASC_ISSUER_ID, iat: now - 10, exp: now + 600, aud: 'appstoreconnect-v1' })).toString('base64url');
  const key = createPrivateKey(decodeP8(env.ASC_KEY_P8));
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') throw new Error('ASC_KEY_MUST_BE_P256');
  const body = `${header}.${payload}`;
  const signature = sign('sha256', Buffer.from(body), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  return `${body}.${signature}`;
}

export async function getApple(token, pathOrUrl) {
  const url = new URL(pathOrUrl, ORIGIN);
  if (url.origin !== ORIGIN || !allowedPaths.has(url.pathname)) throw new Error('API_PATH_NOT_ALLOWED');
  const response = await fetch(url, { method: 'GET', redirect: 'error', headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' }, signal: AbortSignal.timeout(30000) });
  if (!response.ok) return { ok: false, status: response.status, data: [], included: [] };
  const document = await response.json();
  return { ok: true, status: response.status, data: document.data || [], included: document.included || [], next: document.links?.next || null };
}

async function pages(token, path) {
  let next = path;
  const result = { ok: true, status: 200, data: [], included: [], truncated: false };
  for (let page = 0; next && page < 10; page++) {
    const part = await getApple(token, next);
    if (!part.ok) return { ...result, ok: false, status: part.status };
    result.data.push(...part.data);
    result.included.push(...part.included);
    next = part.next;
  }
  result.truncated = Boolean(next);
  return result;
}

function isHospital(app, expectedBundle) {
  const a = app.attributes || {};
  if (expectedBundle) return a.bundleId === expectedBundle || a.identifier === expectedBundle;
  return /日常秩序|医院|hospital/i.test(`${a.name || ''} ${a.bundleId || ''} ${a.identifier || ''}`);
}

function privateEvent() {
  try { return JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8')).repository?.private === true; }
  catch { return false; }
}

export async function probe(env = process.env) {
  const token = makeToken(env);
  const expectedBundle = env.HOSPITAL_BUNDLE_ID?.trim() || '';
  const apps = await pages(token, '/v1/apps?limit=200&fields[apps]=name,bundleId');
  const bundles = await pages(token, '/v1/bundleIds?limit=200&fields[bundleIds]=identifier,name,platform,seedId');
  // certificateContent is a PUBLIC X.509 certificate, never a private key.
  // It is parsed only in memory to obtain subject OU Team-ID candidates.
  const certs = await pages(token, '/v1/certificates?limit=200&fields[certificates]=name,displayName,certificateType,serialNumber,expirationDate,certificateContent');
  const profiles = await pages(token, '/v1/profiles?limit=200&include=bundleId&fields[profiles]=name,uuid,profileState,profileType,expirationDate,bundleId&fields[bundleIds]=identifier');
  const teamCandidates = new Set();
  const distribution = certs.data.filter(c => /DISTRIBUTION/.test(c.attributes?.certificateType || '')).map(c => {
    const a = c.attributes || {};
    if (a.certificateContent) {
      try {
        const x509 = new X509Certificate(Buffer.from(a.certificateContent, 'base64'));
        const match = x509.subject.match(/(?:^|\n)OU=([A-Z0-9]{10})(?:\n|$)/);
        if (match) teamCandidates.add(match[1]);
      } catch { /* Certificate parsing failure is reported only as missing candidates. */ }
    }
    return { id: c.id, type: a.certificateType, serial: a.serialNumber, expires: a.expirationDate };
  });
  const hospitalApps = apps.data.filter(a => isHospital(a, expectedBundle)).map(a => ({ id: a.id, name: a.attributes.name, bundleId: a.attributes.bundleId }));
  const hospitalBundles = bundles.data.filter(a => isHospital(a, expectedBundle)).map(a => ({ id: a.id, identifier: a.attributes.identifier, name: a.attributes.name, bundleSeedId: a.attributes.seedId }));
  const bundleLookup = new Map(profiles.included.filter(a => a.type === 'bundleIds').map(a => [a.id, a.attributes?.identifier]));
  const matchingProfiles = profiles.data.filter(p => {
    const identifier = bundleLookup.get(p.relationships?.bundleId?.data?.id);
    return expectedBundle ? identifier === expectedBundle : hospitalBundles.some(b => b.identifier === identifier);
  }).map(p => ({ id: p.id, name: p.attributes?.name, uuid: p.attributes?.uuid,
    state: p.attributes?.profileState, type: p.attributes?.profileType,
    expires: p.attributes?.expirationDate, bundleId: bundleLookup.get(p.relationships?.bundleId?.data?.id) }));
  const detail = {
    mode: 'GET_METADATA_ONLY', generatedAt: new Date().toISOString(),
    resources: Object.fromEntries(Object.entries({ apps, bundles, certificates: certs, profiles }).map(([key, value]) => [key, { httpStatus: value.status, ok: value.ok, visibleCount: value.data.length, truncated: value.truncated }])),
    hospitalApps, hospitalBundles, matchingProfiles, distributionCertificates: distribution,
    teamIdCandidatesFromPublicCertificateOU: [...teamCandidates].sort(),
    limitations: 'Team-ID candidates need membership confirmation. Issuer ID and bundle seed ID are not assumed to equal Team ID. No app/certificate/profile was created, changed or revoked.'
  };
  // On a PUBLIC repo only counts, HTTP statuses and non-secret Team-ID candidates
  // are printed. No artifacts, report files, app names, bundle IDs or source URLs.
  const summary = {
    mode: detail.mode, resources: detail.resources,
    matchingHospitalAppCount: hospitalApps.length, matchingHospitalBundleCount: hospitalBundles.length,
    matchingHospitalProfileCount: matchingProfiles.length, distributionCertificateCount: distribution.length,
    teamIdCandidatesFromPublicCertificateOU: detail.teamIdCandidatesFromPublicCertificateOU,
    detailedReportSuppressed: !privateEvent()
  };
  console.log(JSON.stringify(summary, null, 2));
  const outputIndex = process.argv.indexOf('--output');
  if (outputIndex >= 0) {
    if (!privateEvent()) throw new Error('DETAILED_REPORT_REQUIRES_PRIVATE_REPOSITORY');
    const path = resolve(process.argv[outputIndex + 1] || '');
    const workspace = resolve(env.GITHUB_WORKSPACE || '.');
    if (!path.startsWith(workspace + '/')) throw new Error('OUTPUT_MUST_STAY_IN_PRIVATE_WORKSPACE');
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, JSON.stringify(detail, null, 2), { mode: 0o600 });
  }
  if (!apps.ok) process.exitCode = 1;
  return detail;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  probe().catch(() => { console.error('ASC_METADATA_PROBE_FAILED: no credential or raw API error was logged.'); process.exitCode = 1; });
}
