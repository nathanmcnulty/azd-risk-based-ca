import test from 'node:test';
import assert from 'node:assert/strict';
import { pollRiskDetections } from '../src/index.js';

const names = ['IDENTITY_ENDPOINT', 'IDENTITY_HEADER', 'AZD_POLLER_STORAGE_ACCOUNT_NAME',
  'AZD_POLLER_STATE_CONTAINER', 'AZD_CA_ADMIN_TEAMS_WORKFLOW_URL', 'AZD_CA_USER_TEAMS_WORKFLOW_URL'];
const previous = Object.fromEntries(names.map(name => [name, process.env[name]]));
const originalFetch = globalThis.fetch;
test.afterEach(() => {
  globalThis.fetch = originalFetch;
  for (const [name, value] of Object.entries(previous)) {
    if (value === undefined) delete process.env[name]; else process.env[name] = value;
  }
});

function fixture({ readStatus = 200, graphStatus = 200, writeStatus = 201, events = [] } = {}) {
  Object.assign(process.env, {
    IDENTITY_ENDPOINT: 'http://identity.example.test/token', IDENTITY_HEADER: 'fixture-header',
    AZD_POLLER_STORAGE_ACCOUNT_NAME: 'fixtureaccount', AZD_POLLER_STATE_CONTAINER: 'risk-state',
    AZD_CA_ADMIN_TEAMS_WORKFLOW_URL: 'https://receiver.example.test/admin', AZD_CA_USER_TEAMS_WORKFLOW_URL: '',
  });
  const calls = []; const logs = [];
  const state = { schemaVersion: '1.0', seededAt: new Date().toISOString(),
    lastSuccessfulQueryAt: new Date().toISOString(), deliveries: {} };
  globalThis.fetch = async (url, options = {}) => {
    const target = new URL(url); calls.push({ target, options });
    if (target.hostname === 'identity.example.test') {
      assert.ok(['https://graph.microsoft.com', 'https://storage.azure.com/'].includes(target.searchParams.get('resource')));
      return Response.json({ access_token: 'fixture-token' });
    }
    if (target.hostname === 'fixtureaccount.blob.core.windows.net') {
      if (options.method === 'PUT') return new Response(null, { status: writeStatus });
      return readStatus === 200 ? Response.json(state, { headers: { etag: 'fixture-etag' } })
        : new Response(null, { status: readStatus });
    }
    if (target.hostname === 'graph.microsoft.com') {
      return graphStatus === 200 ? Response.json({ value: events }) : new Response(null, { status: graphStatus });
    }
    if (target.hostname === 'receiver.example.test') return new Response(null, { status: 200 });
    throw new Error('Unexpected offline request');
  };
  return { calls, logs, context: { log(message) { logs.push(message); }, warn(message) { logs.push(message); } } };
}

test('state read failure stops before Graph collection, delivery and a new checkpoint', async () => {
  const f = fixture({ readStatus: 403 });
  await assert.rejects(pollRiskDetections(null, f.context), /State read failed \(403\)/);
  assert.equal(f.calls.length, 3);
  assert.ok(f.calls.every(c => c.options.method !== 'PUT'));
  assert.deepEqual(f.logs, []);
});

test('Graph collection failure propagates without recording a successful query', async () => {
  const f = fixture({ graphStatus: 403 });
  await assert.rejects(pollRiskDetections(null, f.context), /risk detection query failed \(403\)/);
  assert.ok(f.calls.every(c => c.options.method !== 'PUT'));
  assert.deepEqual(f.logs, []);
});

for (const status of [403, 412, 500]) {
  test(`checkpoint write ${status} fails the invocation and never emits success`, async () => {
    const f = fixture({ writeStatus: status });
    await assert.rejects(pollRiskDetections(null, f.context), new RegExp(`State write failed \\(${status}\\)`));
    const writes = f.calls.filter(c => c.options.method === 'PUT');
    assert.equal(writes.length, 1);
    assert.equal(writes[0].options.headers['If-Match'], 'fixture-etag');
    assert.deepEqual(f.logs, []);
  });
}

test('an absent optional user destination sends only the admin card and records its exact delivery', async () => {
  const f = fixture({ events: [{ id: 'fixture-event', userPrincipalName: 'fixture@example.test',
    detectedDateTime: new Date().toISOString(), riskLevel: 'high' }] });
  await pollRiskDetections(null, f.context);
  const sends = f.calls.filter(c => c.target.hostname === 'receiver.example.test');
  assert.equal(sends.length, 1); assert.equal(sends[0].target.pathname, '/admin');
  const written = JSON.parse(f.calls.find(c => c.options.method === 'PUT').options.body);
  assert.deepEqual(Object.keys(written.deliveries), ['fixture-event|admin']);
  assert.equal(written.deliveries['fixture-event|admin'].status, 'delivered');
});
