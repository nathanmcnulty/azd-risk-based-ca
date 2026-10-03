import test from 'node:test';
import assert from 'node:assert/strict';
import { pollRiskDetections } from '../src/index.js';

const originalFetch = globalThis.fetch;
const names = [
  'IDENTITY_ENDPOINT', 'IDENTITY_HEADER', 'AZD_POLLER_STORAGE_ACCOUNT_NAME',
  'AZD_POLLER_STATE_CONTAINER', 'AZD_CA_ADMIN_TEAMS_WORKFLOW_URL',
  'AZD_CA_USER_TEAMS_WORKFLOW_URL',
];
const originalSettings = Object.fromEntries(names.map((name) => [name, process.env[name]]));

test.afterEach(() => {
  globalThis.fetch = originalFetch;
  for (const [name, value] of Object.entries(originalSettings)) {
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
});

async function runWithCheckpoint(daysAgo) {
  Object.assign(process.env, {
    IDENTITY_ENDPOINT: 'http://identity.example.test/token',
    IDENTITY_HEADER: 'test-header',
    AZD_POLLER_STORAGE_ACCOUNT_NAME: 'stateaccount',
    AZD_POLLER_STATE_CONTAINER: 'risk-state',
    AZD_CA_ADMIN_TEAMS_WORKFLOW_URL: 'https://workflow.example.test/admin',
    AZD_CA_USER_TEAMS_WORKFLOW_URL: '',
  });
  const checkpoint = new Date(Date.now() - daysAgo * 24 * 60 * 60 * 1000);
  const requested = [];
  const written = [];
  const warnings = [];
  globalThis.fetch = async (url, init = {}) => {
    const target = String(url);
    if (target.startsWith('http://identity.example.test/token')) {
      return Response.json({ access_token: 'test-token' });
    }
    if (target.startsWith('https://stateaccount.blob.core.windows.net/risk-state/')) {
      if (init.method === 'PUT') {
        written.push(JSON.parse(init.body));
        return new Response(null, { status: 201 });
      }
      return Response.json({ schemaVersion: '1.0', seededAt: checkpoint.toISOString(), lastSuccessfulQueryAt: checkpoint.toISOString(), deliveries: {} }, { headers: { etag: 'etag-1' } });
    }
    if (target.startsWith('https://graph.microsoft.com/v1.0/identityProtection/riskDetections?')) {
      requested.push(target);
      return Response.json({ value: [] });
    }
    throw new Error('Unexpected offline request');
  };
  await pollRiskDetections(null, { log() {}, warn(message) { warnings.push(message); } });
  return { checkpoint, requested, written, warnings };
}

test('the actual poller replays a three-day outage and commits the new query watermark', async () => {
  const result = await runWithCheckpoint(3);
  assert.equal(result.requested.length, 1);
  const filter = new URL(result.requested[0]).searchParams.get('$filter');
  const since = Date.parse(filter.replace('detectedDateTime ge ', ''));
  assert.ok(Math.abs(since - (result.checkpoint.getTime() - 10 * 60_000)) < 5_000);
  assert.equal(result.written.length, 1);
  assert.ok(Date.parse(result.written[0].lastSuccessfulQueryAt) >= result.checkpoint.getTime());
  assert.equal(result.written[0].recoveryGap, null);
  assert.deepEqual(result.warnings, []);
});

test('the actual poller persists and warns about an unfillable recovery gap', async () => {
  const result = await runWithCheckpoint(10);
  assert.equal(result.requested.length, 1);
  assert.equal(result.written.length, 1);
  assert.equal(result.written[0].recoveryGap.reason, 'recoveryLimitExceeded');
  assert.equal(result.warnings.length, 1);
  assert.match(result.warnings[0], /^AZD_POLLER_RECOVERY_GAP /);
});
