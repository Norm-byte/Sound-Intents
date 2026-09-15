#!/usr/bin/env node
/**
 * One-off repair: stale per-week local drafts republished 60 over the intended
 * noticeboard show-before window. Rewrites published slot_ docs for a given week.
 *
 * Usage: node restore_noticeboard_window.js --week 20260914 --minutes 360 [--apply]
 */
const os = require('os');
const path = require('path');

const PROJECT = 'harmony-by-intent';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

// Public client credentials shipped with the firebase-tools CLI.
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
}

const WEEK = arg('week');
const MINUTES = parseInt(arg('minutes', '360'), 10);
const APPLY = process.argv.includes('--apply');

if (!WEEK || !/^\d{8}$/.test(WEEK)) {
  console.error('ERROR: --week must be a yyyyMMdd date suffix, e.g. 20260914');
  process.exit(1);
}
if (!Number.isInteger(MINUTES) || MINUTES < 0 || MINUTES >= 1440) {
  console.error('ERROR: --minutes must be 0-1439 (must stay below International 1440 default)');
  process.exit(1);
}

async function accessToken() {
  const cfg = require(path.join(os.homedir(), '.config/configstore/firebase-tools.json'));
  const refresh = cfg.tokens && cfg.tokens.refresh_token;
  if (!refresh) throw new Error('No firebase-tools refresh token. Run: firebase login');
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      refresh_token: refresh,
      grant_type: 'refresh_token',
    }),
  });
  if (!res.ok) throw new Error(`Token exchange failed: ${res.status} ${await res.text()}`);
  return (await res.json()).access_token;
}

async function listEvents(token) {
  const docs = [];
  let pageToken;
  do {
    const url = new URL(`${BASE}/events`);
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) throw new Error(`List failed: ${res.status} ${await res.text()}`);
    const body = await res.json();
    docs.push(...(body.documents || []));
    pageToken = body.nextPageToken;
  } while (pageToken);
  return docs;
}

(async () => {
  const token = await accessToken();
  const all = await listEvents(token);

  const targets = all.filter((d) => {
    const id = d.name.split('/').pop();
    return id.startsWith('slot_')
      && id.endsWith(`_${WEEK}`)
      && d.fields.isPublished?.booleanValue === true;
  });

  const stale = targets.filter(
    (d) => (d.fields.noticeBoardShowBeforeMinutes?.integerValue ?? '0') !== String(MINUTES)
  );

  console.log(`Week ${WEEK}: ${targets.length} published slots, ${stale.length} need updating to ${MINUTES}m`);
  if (!stale.length) { console.log('Nothing to do.'); return; }

  for (const d of stale) {
    const id = d.name.split('/').pop();
    const from = d.fields.noticeBoardShowBeforeMinutes?.integerValue ?? '(unset)';
    if (!APPLY) { console.log(`  DRY-RUN ${id}: ${from} -> ${MINUTES}`); continue; }
    const url = `https://firestore.googleapis.com/v1/${d.name}`
      + `?updateMask.fieldPaths=noticeBoardShowBeforeMinutes`;
    const res = await fetch(url, {
      method: 'PATCH',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ fields: { noticeBoardShowBeforeMinutes: { integerValue: String(MINUTES) } } }),
    });
    if (!res.ok) { console.error(`  FAIL ${id}: ${res.status} ${await res.text()}`); continue; }
    console.log(`  OK ${id}: ${from} -> ${MINUTES}`);
  }
  console.log(APPLY ? 'Done.' : 'Dry run complete. Re-run with --apply to write.');
})().catch((e) => { console.error(e.message); process.exit(1); });
