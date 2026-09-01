const graphBase = 'https://graph.microsoft.com/v1.0';

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
  const filter = `detectedDateTime ge ${since.toISOString()}`;
  const select = 'id,detectedDateTime,activityDateTime,userId,userPrincipalName,userDisplayName,riskEventType,riskDetail,riskLevel,riskState';
  let url = `${graphBase}/identityProtection/riskDetections?$filter=${encodeURIComponent(filter)}&$select=${select}&$top=500`;
  while (url) {
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
