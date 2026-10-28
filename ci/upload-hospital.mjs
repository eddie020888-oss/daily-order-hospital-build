// Direct TestFlight upload in the same owner-dispatched public build job.
// No artifact download, app creation, certificate mutation or review submission.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, unlinkSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { decodeP8, makeToken, getApple } from './asc-metadata-probe.mjs';

async function main() {
  const env = process.env;
  const event = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, 'utf8'));
  const repository = 'eddie020888-oss/daily-order-hospital-build';
  if (event.repository?.private !== false || env.GITHUB_REPOSITORY !== repository ||
      env.HOSPITAL_EXPECTED_REPOSITORY !== repository || env.GITHUB_ACTOR !== env.GITHUB_REPOSITORY_OWNER ||
      env.GITHUB_EVENT_NAME !== 'workflow_dispatch' || env.GITHUB_REF !== 'refs/heads/main' ||
      env.HOSPITAL_UPLOAD_CONFIRMATION !== 'UPLOAD_HOSPITAL_BETA' || event.inputs?.mode !== 'testflight')
    throw new Error('PUBLIC_HOSPITAL_UPLOAD_GUARD');
  const bundle = env.HOSPITAL_BUNDLE_ID || '';
  const appId = env.HOSPITAL_ASC_APP_ID || '';
  if (!/^[0-9]+$/.test(appId) || bundle !== 'com.eddie.dailyorderhospital')
    throw new Error('HOSPITAL_APP_RECORD_NOT_CONFIGURED');
  const out = join(env.GITHUB_WORKSPACE, 'out/hospital-ios');
  const identity = JSON.parse(readFileSync(join(out, 'build-identity.json'), 'utf8'));
  const manifestBytes = readFileSync(join(out, 'source-manifest.json'));
  if (identity.bundleId !== bundle || identity.teamId !== env.HOSPITAL_TEAM_ID ||
      identity.sourceCommit !== env.GITHUB_SHA || identity.build !== env.HOSPITAL_BUILD_NUMBER ||
      identity.version !== env.HOSPITAL_VERSION || identity.signatureVerified !== true ||
      identity.entitlementsVerified !== true || identity.actualIpaIdentityVerified !== true ||
      identity.sourceManifestSha256 !== createHash('sha256').update(manifestBytes).digest('hex') ||
      JSON.parse(manifestBytes).commit !== env.GITHUB_SHA)
    throw new Error('SIGNED_BUILD_IDENTITY_MISMATCH');
  if (!/^[A-Za-z0-9_.-]+\.ipa$/.test(identity.ipa)) throw new Error('INVALID_IPA_FILENAME');
  const ipa = join(out, 'ipa', identity.ipa);
  if (createHash('sha256').update(readFileSync(ipa)).digest('hex') !== identity.ipaSha256)
    throw new Error('IPA_SHA_MISMATCH');
  const apps = await getApple(makeToken(env), '/v1/apps?filter[bundleId]=' + encodeURIComponent(bundle) + '&fields[apps]=bundleId,name&limit=200');
  if (!apps.ok || apps.data.length !== 1 || apps.data[0].id !== appId || apps.data[0].attributes?.bundleId !== bundle)
    throw new Error('EXISTING_HOSPITAL_ASC_APP_NOT_MATCHED');
  const scratch = resolve(env.RUNNER_TEMP, 'hospital-altool');
  const keyDir = join(scratch, 'private_keys');
  mkdirSync(keyDir, { recursive: true, mode: 0o700 });
  const p8 = decodeP8(env.ASC_KEY_P8);
  const keyPath = join(keyDir, `AuthKey_${env.ASC_KEY_ID}.p8`);
  writeFileSync(keyPath, p8, { mode: 0o600, flag: 'wx' });
  const redact = value => value.replaceAll(p8, '[PRIVATE KEY REDACTED]').replaceAll(env.ASC_KEY_P8, '[SECRET REDACTED]')
    .replace(/[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/g, '[JWT REDACTED]');
  try {
    for (const [operation, name] of [['--validate-app', 'validate'], ['--upload-app', 'upload']]) {
      const result = spawnSync('xcrun', ['altool', operation, '-f', ipa, '-t', 'ios', '--apiKey', env.ASC_KEY_ID, '--apiIssuer', env.ASC_ISSUER_ID],
        { cwd: scratch, env: { ...env, API_PRIVATE_KEYS_DIR: keyDir }, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
      writeFileSync(join(out, `altool-${name}.log`), redact((result.stdout || '') + (result.stderr || '')), { mode: 0o600 });
      if (result.error || result.status !== 0) throw new Error(`ALTOOL_${name.toUpperCase()}_FAILED`);
      console.log(`Hospital ${name} accepted by tool; package and raw logs are not published.`);
    }
    writeFileSync(join(out, 'upload-receipt.json'), JSON.stringify({ appId, bundleId: bundle,
      build: identity.build, version: identity.version, ipaSha256: identity.ipaSha256,
      sourceCommit: env.GITHUB_SHA, sourceRunId: env.GITHUB_RUN_ID, uploadedAt: new Date().toISOString(),
      note: 'Tool accepted upload. Apple processing and tester availability must still be verified.' }, null, 2));
  } finally {
    unlinkSync(keyPath);
  }
}

main().catch(error => {
  console.error('HOSPITAL_UPLOAD_FAILED: ' + (/^[A-Z0-9_]+$/.test(error.message) ? error.message : 'RAW_ERROR_SUPPRESSED'));
  process.exitCode = 1;
});
