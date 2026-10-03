const graphBase = 'https://graph.microsoft.com/v1.0';
const hourMs = 60 * 60 * 1000;

export function planRiskRecoveryWindow(now, state) {
  const latest = now.getTime();
  const normalSince = latest - 24 * hourMs;
  const oldestRecoverable = latest - 7 * 24 * hourMs;
  const checkpoint = state.lastSuccessfulQueryAt ?? state.lastRunAt;
  const last = checkpoint ? Date.parse(checkpoint) : Number.NaN;
  if (!state.seededAt) return { since: new Date(normalSince), gap: null };
  const pendingTimes = Object.values(state.deliveries ?? {})
    .filter((record) => record?.status === 'pending')
    .map((record) => Date.parse(record.eventDetectedAt));
  if (!Number.isFinite(last) || last > latest || pendingTimes.some((time) => !Number.isFinite(time))) {
    return { since: new Date(oldestRecoverable), gap: { reason: 'missingWatermark', detectedAt: now.toISOString() } };
  }
  const replayFrom = pendingTimes.reduce((earliest, time) => Math.min(earliest, time), last);
  const gap = replayFrom < oldestRecoverable
    ? { reason: 'recoveryLimitExceeded', from: new Date(replayFrom).toISOString(), to: new Date(oldestRecoverable).toISOString(), detectedAt: now.toISOString() }
    : null;
  return { since: new Date(Math.max(oldestRecoverable, Math.min(normalSince, replayFrom - 10 * 60_000))), gap };
}

export function retainRiskRecoveryGap(existing, detected) {
  if (existing && existing.reason === 'recoveryLimitExceeded') {
    const from = Date.parse(existing.from);
    const to = Date.parse(existing.to);
    existing = Number.isFinite(from) && Number.isFinite(to) && from <= to
      ? {
        reason: 'recoveryLimitExceeded',
        from: new Date(from).toISOString(),
        to: new Date(to).toISOString(),
        detectedAt: Number.isFinite(Date.parse(existing.detectedAt))
          ? new Date(existing.detectedAt).toISOString() : new Date().toISOString(),
      }
      : { reason: 'missingWatermark', detectedAt: new Date().toISOString() };
  } else if (existing) {
    existing = {
      reason: 'missingWatermark',
      detectedAt: Number.isFinite(Date.parse(existing.detectedAt))
        ? new Date(existing.detectedAt).toISOString() : new Date().toISOString(),
    };
  }
  if (!detected) return existing ?? null;
  if (!existing) return detected;
  if (existing.reason === 'missingWatermark' || detected.reason === 'missingWatermark') {
    return { reason: 'missingWatermark', detectedAt: existing.detectedAt ?? detected.detectedAt };
  }
  return {
    reason: 'recoveryLimitExceeded',
    from: existing.from < detected.from ? existing.from : detected.from,
    to: existing.to > detected.to ? existing.to : detected.to,
    detectedAt: existing.detectedAt ?? detected.detectedAt,
  };
}

export function normalizeRiskDetection(event) {
  return {
    schemaVersion: '1.0',
    eventId: String(event.id),
    detectedAt: event.detectedDateTime ?? event.activityDateTime,
    userId: event.userId ?? '',
    userPrincipalName: event.userPrincipalName ?? '',
    userDisplayName: event.userDisplayName ?? '',
    riskType: event.riskEventType ?? event.riskDetail ?? 'unknown',
    riskLevel: event.riskLevel ?? 'unknown',
    riskState: event.riskState ?? 'unknown',
    source: 'graph',
    investigationUrl: 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/RiskDetectionsBlade',
  };
}

export function adminCard(envelope) {
  return { type: 'message', attachments: [{ contentType: 'application/vnd.microsoft.card.adaptive', contentUrl: null, content: {
    $schema: 'http://adaptivecards.io/schemas/adaptive-card.json', type: 'AdaptiveCard', version: '1.4',
    body: [
      { type: 'TextBlock', text: 'Microsoft Entra risk detected', weight: 'Bolder', size: 'Medium' },
      { type: 'FactSet', facts: [
        { title: 'User', value: envelope.userPrincipalName || envelope.userId || 'Unknown' },
        { title: 'Detected', value: envelope.detectedAt },
        { title: 'Risk', value: `${envelope.riskLevel} ${envelope.riskType}` },
        { title: 'State', value: envelope.riskState },
        { title: 'Event', value: envelope.eventId },
      ] },
      { type: 'TextBlock', text: envelope.investigationUrl, wrap: true },
    ],
  } }] };
}

export function userCard(envelope) {
  return { schemaVersion: '1.0', recipientUpn: envelope.userPrincipalName, card: { type: 'message', attachments: [{ contentType: 'application/vnd.microsoft.card.adaptive', contentUrl: null, content: {
    $schema: 'http://adaptivecards.io/schemas/adaptive-card.json', type: 'AdaptiveCard', version: '1.4',
    body: [
      { type: 'TextBlock', text: 'Review your Microsoft account security', weight: 'Bolder' },
      { type: 'TextBlock', text: 'Microsoft detected account activity that may require your attention. Open My Sign-Ins to review and secure your account.', wrap: true },
      { type: 'TextBlock', text: 'https://mysignins.microsoft.com/security-info', wrap: true },
    ],
  } }] } };
}

export function isInternalUser(envelope) {
  return Boolean(envelope.userPrincipalName) && !envelope.userPrincipalName.toLowerCase().includes('#ext#');
}

export async function fetchWithRetry(url, options, { fetchImpl = fetch, attempts = 5, delay = async (ms) => new Promise((resolve) => setTimeout(resolve, ms)), label = 'request' } = {}) {
  let lastStatus = 0;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    const response = await fetchImpl(url, options);
    if (response.ok) return response;
    lastStatus = response.status;
    if (response.status !== 429 && response.status < 500) throw new Error(`${label} failed (${response.status}).`);
    if (attempt < attempts) {
      const retryAfter = Number.parseInt(response.headers.get('retry-after') ?? '', 10);
      await delay(Number.isFinite(retryAfter) ? retryAfter * 1000 : Math.min(2 ** attempt * 1000, 30_000));
    }
  }
  throw new Error(`${label} failed after ${attempts} attempts (last status ${lastStatus}).`);
}

export async function getRiskDetections(token, since, dependencies = {}) {
  const fetcher = dependencies.fetchWithRetryImpl ?? fetchWithRetry;
  const events = [];
  const expectedOrigin = new URL(graphBase).origin;
  const expectedPath = '/v1.0/identityProtection/riskDetections';
  const seen = new Set();
  const filter = `detectedDateTime ge ${since.toISOString()}`;
  const select = 'id,detectedDateTime,activityDateTime,userId,userPrincipalName,userDisplayName,riskEventType,riskDetail,riskLevel,riskState';
  let url = `${graphBase}/identityProtection/riskDetections?$filter=${encodeURIComponent(filter)}&$select=${select}&$top=500`;
  while (url) {
    if (seen.size >= 1000) throw new Error('Microsoft Graph risk detection pagination exceeded 1000 pages.');
    let parsed;
    try { parsed = new URL(url); } catch { throw new Error('Invalid Microsoft Graph risk detection continuation URL.'); }
    if (parsed.origin !== expectedOrigin || parsed.pathname !== expectedPath || parsed.username || parsed.password || parsed.hash) {
      throw new Error('Microsoft Graph risk detection continuation URL is outside the expected collection.');
    }
    if (seen.has(parsed.href)) throw new Error('Microsoft Graph risk detection continuation URL cycled.');
    seen.add(parsed.href);
    const response = await fetcher(url, { headers: { Authorization: `Bearer ${token}` } }, { label: 'Microsoft Graph risk detection query', ...dependencies });
    const page = await response.json();
    events.push(...(page.value ?? []));
    url = page['@odata.nextLink'] ?? null;
  }
  return events.sort((a, b) => String(a.detectedDateTime).localeCompare(String(b.detectedDateTime)));
}

export function deliveryKey(eventId, destination) { return `${eventId}|${destination}`; }

export function planDeliveries(events, state, hasUserDestination) {
  const firstRun = !state.seededAt;
  const deliveries = [];
  for (const raw of events) {
    const event = normalizeRiskDetection(raw);
    for (const destination of ['admin', ...(hasUserDestination && isInternalUser(event) ? ['user'] : [])]) {
      const key = deliveryKey(event.eventId, destination);
      if (!state.deliveries[key]) {
        state.deliveries[key] = { status: firstRun ? 'seeded' : 'pending', attempts: 0, eventDetectedAt: event.detectedAt };
        if (!firstRun) deliveries.push({ event, destination, key });
      } else if (state.deliveries[key].status === 'pending') {
        deliveries.push({ event, destination, key });
      }
    }
  }
  return { firstRun, deliveries };
}

export function pruneState(state, cutoff) {
  for (const [key, record] of Object.entries(state.deliveries)) {
    if (new Date(record.eventDetectedAt) < cutoff && record.status !== 'pending') delete state.deliveries[key];
  }
  return state;
}

export function recordDeliveryFailure(record, error, now = new Date(), threshold = 5) {
  record.attempts = (record.attempts ?? 0) + 1;
  record.lastAttemptAt = now.toISOString();
  record.lastError = String(error?.message ?? error).slice(0, 300);
  if (record.attempts >= threshold) record.status = 'deadLettered';
  return record.status === 'deadLettered';
}
