// Uploads a reference catalogue to Cloud Firestore so the app fetches it from
// Firestore instead of a bundled file. Used for both catalogues:
//
//   node tools/seed_firestore.js "<app>/assets/data/foods.json"     --collection foods
//   node tools/seed_firestore.js "<app>/assets/data/exercises.json" --collection exercises
//
// Optional: --project <firebase project id> (default baymax-148da)
//
// Several files can be given as a comma-separated list (curated foods + the searchable food list):
//   node tools/seed_firestore.js "<app>/assets/data/foods.json,<app>/assets/data/foods_bulk.json" --collection foods
//
// Authorisation: if GOOGLE_APPLICATION_CREDENTIALS points at a service-account key file, that is used (keep the key OUTSIDE the project and
// never commit it). Otherwise it reuses your `firebase login` session (the same credentials
// `firebase deploy` uses), so nothing extra needs to be configured. Admin
// access bypasses the Firestore security rules, which keep the catalogue
// read-only for app users.
//
// Safe to re-run: documents are upserted, foods no longer in the file are
// deleted, and `meta/foods.version` is bumped so apps know to refresh.
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const args = process.argv.slice(2);
const file = args.find((a, i) => !a.startsWith('--') && !args[i - 1]?.startsWith('--'));
const flag = (name, fallback) => (args.indexOf(name) >= 0 ? args[args.indexOf(name) + 1] : fallback);
const PROJECT = flag('--project', 'baymax-148da');
const COLLECTION = flag('--collection', 'foods');

// Minimal sanity checks so a malformed file never reaches the app.
const VALIDATORS = {
  foods: (f) => f.id && f.name && typeof f.kcal === 'number',
  exercises: (e) => e.id && e.name && e.group && typeof e.met === 'number' && Array.isArray(e.steps) && e.steps.length > 0,
};
const DOCS = `projects/${PROJECT}/databases/(default)/documents`;
const API = `https://firestore.googleapis.com/v1/${DOCS}`;

function findFirebaseTools() {
  const candidates = [];
  if (process.env.FIREBASE_TOOLS_DIR) candidates.push(process.env.FIREBASE_TOOLS_DIR);
  try {
    const bin = fs.realpathSync(execSync('which firebase', { encoding: 'utf8' }).trim());
    let dir = path.dirname(bin);
    for (let i = 0; i < 8; i++) {
      candidates.push(path.join(dir, 'node_modules', 'firebase-tools'));
      candidates.push(path.join(dir, 'lib', 'node_modules', 'firebase-tools'));
      candidates.push(path.join(dir, 'libexec', 'lib', 'node_modules', 'firebase-tools'));
      dir = path.dirname(dir);
    }
  } catch (_) { /* firebase CLI not on PATH */ }
  try { candidates.push(path.join(execSync('npm root -g', { encoding: 'utf8' }).trim(), 'firebase-tools')); } catch (_) {}
  const found = candidates.find((c) => fs.existsSync(path.join(c, 'package.json')));
  if (!found) throw new Error('Could not locate firebase-tools. Install the Firebase CLI and run `firebase login`, or set FIREBASE_TOOLS_DIR.');
  return found;
}

async function accessToken() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    const { GoogleAuth } = require('google-auth-library');
    const client = await new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/datastore'] }).getClient();
    const t = await client.getAccessToken();
    return t.token || t;
  }
  const dir = findFirebaseTools();
  const auth = require(path.join(dir, 'lib', 'auth'));
  const { configstore } = require(path.join(dir, 'lib', 'configstore'));
  const tokens = configstore.get('tokens');
  if (!tokens || !tokens.refresh_token) throw new Error('Not logged in. Run `firebase login` first.');
  const t = await auth.getAccessToken(tokens.refresh_token, []);
  return t.access_token || t;
}

// Firestore REST typed values
function toValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toValue) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, toValue(x)])) } };
}
const toFields = (obj) => Object.fromEntries(Object.entries(obj).map(([k, x]) => [k, toValue(x)]));

async function call(token, url, options = {}) {
  const res = await fetch(url, {
    ...options,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...(options.headers || {}) },
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${options.method || 'GET'} ${url} -> ${res.status} ${JSON.stringify(body).slice(0, 300)}`);
  return body;
}

async function existingIds(token) {
  const ids = [];
  let pageToken = '';
  do {
    const url = `${API}/${COLLECTION}?pageSize=300&mask.fieldPaths=name${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''}`;
    const body = await call(token, url);
    for (const d of body.documents || []) ids.push(d.name.split('/').pop());
    pageToken = body.nextPageToken || '';
  } while (pageToken);
  return ids;
}

async function main() {
  if (!file) {
    console.error('Usage: node tools/seed_firestore.js <file.json> --collection foods|exercises [--project <id>]');
    process.exit(1);
  }
  const validate = VALIDATORS[COLLECTION];
  if (!validate) throw new Error(`Unknown collection "${COLLECTION}" (use foods or exercises)`);
  const foods = file.split(',').flatMap((f) => JSON.parse(fs.readFileSync(f.trim(), 'utf8')));
  const seen = new Set();
  for (const f of foods) {
    if (seen.has(f.id)) throw new Error(`Duplicate id ${f.id} across the input files`);
    seen.add(f.id);
  }
  if (!Array.isArray(foods) || foods.length === 0) throw new Error('The JSON file is empty or not an array');

  const token = await accessToken();
  const before = await existingIds(token);
  const keep = new Set(foods.map((f) => f.id));

  const writes = [];
  for (const food of foods) {
    if (!validate(food)) throw new Error(`Invalid ${COLLECTION} entry: ${JSON.stringify(food).slice(0, 100)}`);
    writes.push({ update: { name: `${DOCS}/${COLLECTION}/${food.id}`, fields: toFields(food) } });
  }
  const removed = before.filter((id) => !keep.has(id));
  for (const id of removed) writes.push({ delete: `${DOCS}/${COLLECTION}/${id}` });

  for (let i = 0; i < writes.length; i += 400) {
    await call(token, `${API}:commit`, { method: 'POST', body: JSON.stringify({ writes: writes.slice(i, i + 400) }) });
  }

  const meta = { version: Math.floor(Date.now() / 1000), count: foods.length };
  let summary;
  if (COLLECTION === 'foods') {
    const n = (src) => foods.filter((f) => f.source === src).length;
    meta.usda = n('usda');
    meta.indb = n('indb');
    meta.teamList = n('calorica');
    meta.estimate = foods.length - meta.usda - meta.indb - meta.teamList;
    summary = `${meta.usda} USDA, ${meta.indb} Indian Nutrient Databank, ${meta.teamList} team list, ${meta.estimate} estimates`;
  } else {
    meta.fromDataset = foods.filter((e) => e.techniqueSource === 'free-exercise-db').length;
    meta.teamWritten = foods.length - meta.fromDataset;
    summary = `${meta.fromDataset} matched to free-exercise-db, ${meta.teamWritten} team-written`;
  }
  await call(token, `${API}:commit`, {
    method: 'POST',
    body: JSON.stringify({ writes: [{ update: { name: `${DOCS}/meta/${COLLECTION}`, fields: toFields(meta) } }] }),
  });

  console.log(`Seeded ${foods.length} ${COLLECTION} to ${PROJECT} (${summary}); removed ${removed.length} stale; catalogue version ${meta.version}.`);
}

main().catch((e) => { console.error('FAILED:', e.message); process.exit(1); });
