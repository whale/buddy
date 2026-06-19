// Buddy bug-report intake — a tiny serverless proxy (Vercel).
//
// The desktop app POSTs { version, platform, logs, screenshot } here; we open a
// GitHub issue so reports land in one searchable place instead of an email draft.
//
// PRIVACY: a Buddy screenshot shows the user's task text, and the Buddy repo is
// PUBLIC — so reports go to a PRIVATE repo (BUG_REPO, default whale/buddy-bugs).
// The GitHub token never ships in the app; it lives only in this function's env.
//
// SECURITY: this endpoint is internet-reachable (the URL is in the open-source app),
// so it is hardened as a privileged proxy:
//   - strict screenshot validation (png/jpeg magic bytes) + hard size caps,
//   - field sanitising so report text can't inject markdown into the issue,
//   - an OPTIONAL shared key (BUG_KEY) as a drive-by speed bump.
//   Note: a true rate limit needs Vercel KV/Upstash — see the TODO below. Impact is
//   bounded (a PRIVATE repo you own); the caps stop oversized/abusive single requests.
//
// Env vars (Vercel → Project → Settings → Environment Variables):
//   GITHUB_TOKEN  — fine-grained PAT, Issues:write + Contents:write on BUG_REPO (required)
//   BUG_REPO      — "owner/repo" of the PRIVATE intake repo (default whale/buddy-bugs)
//   BUG_KEY       — optional shared secret; if set, requests must send header x-buddy-key

const GH = 'https://api.github.com';
const MAX_SHOT_BYTES = 3_000_000;   // decoded screenshot cap (~3 MB)
const MAX_LOGS = 8000;
const PNG_MAGIC = '89504e47';       // ‰PNG
const JPG_MAGIC = 'ffd8ff';

async function gh(path, token, init = {}) {
  return fetch(`${GH}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.github+json',
      'User-Agent': 'buddy-bug-report',
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
}

// One-line, length-capped, backtick-stripped — safe to drop into markdown.
function oneline(s, n) {
  return String(s == null ? '' : s).replace(/[`\r\n]+/g, ' ').slice(0, n);
}
// Logs go in a fenced block; neutralise any ``` runs so they can't break out.
function fence(s, n) {
  return String(s == null ? '' : s).replace(/`/g, 'ˋ').slice(0, n);
}
// Validate a base64 PNG/JPEG and return its bytes-as-base64, or null.
function validShot(dataUri) {
  if (typeof dataUri !== 'string') return null;
  const m = /^data:image\/(png|jpe?g);base64,([A-Za-z0-9+/=]+)$/.exec(dataUri);
  if (!m) return null;
  const b64 = m[2];
  if (b64.length * 0.75 > MAX_SHOT_BYTES) return null;     // size cap before decoding
  let head;
  try { head = Buffer.from(b64.slice(0, 16), 'base64').toString('hex'); }
  catch { return null; }
  if (!head.startsWith(PNG_MAGIC) && !head.startsWith(JPG_MAGIC)) return null;  // magic bytes
  const ext = head.startsWith(PNG_MAGIC) ? 'png' : 'jpg';
  return { b64, ext };
}

export default async function handler(req, res) {
  // CORS — the Tauri webview is a non-standard origin. (Not a security boundary;
  // the controls below are. A non-browser caller ignores CORS regardless.)
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, x-buddy-key');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });

  const token = process.env.GITHUB_TOKEN;
  const repo = process.env.BUG_REPO || 'whale/buddy-bugs';
  if (!token) return res.status(500).json({ error: 'server not configured (no GITHUB_TOKEN)' });

  // Optional shared-key speed bump (blocks anonymous drive-by traffic).
  if (process.env.BUG_KEY && req.headers['x-buddy-key'] !== process.env.BUG_KEY) {
    return res.status(401).json({ error: 'unauthorized' });
  }

  let body;
  try { body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {}); }
  catch { return res.status(400).json({ error: 'bad json' }); }

  const version = oneline(body.version || '?', 40);
  const platform = oneline(body.platform || '', 200);
  const logs = fence(body.logs || '', MAX_LOGS);
  const shot = validShot(body.screenshot);   // null if missing/invalid/oversized
  const ts = Date.now();

  // Store a VALIDATED screenshot in the PRIVATE repo at a SERVER-controlled path.
  let shotLink = '';
  if (shot) {
    const path = `shots/${ts}.${shot.ext}`;
    try {
      const up = await gh(`/repos/${repo}/contents/${path}`, token, {
        method: 'PUT',
        body: JSON.stringify({ message: `bug screenshot ${ts}`, content: shot.b64 }),
      });
      if (up.ok) shotLink = `\n\n[📷 screenshot](https://github.com/${repo}/blob/main/${path}) (opens in the private repo)\n`;
    } catch (_) { /* screenshot is best-effort; the logs are the point */ }
  }

  const title = `Bug — ${version} — ${new Date(ts).toISOString().slice(0, 16).replace('T', ' ')}`;
  const issueBody =
    `**From Buddy ${version}**\n\n` +
    `- platform: \`${platform}\`\n` +
    shotLink +
    `\n\`\`\`\n${logs}\n\`\`\`\n`;

  const issue = await gh(`/repos/${repo}/issues`, token, {
    method: 'POST',
    body: JSON.stringify({ title, body: issueBody, labels: ['bug-report'] }),
  });
  if (!issue.ok) {
    const detail = await issue.text();
    return res.status(502).json({ error: 'github issue create failed', detail: detail.slice(0, 300) });
  }
  const data = await issue.json();
  return res.status(200).json({ ok: true, url: data.html_url });

  // TODO (hardening before wide exposure): add per-IP + global daily rate limits via
  // Vercel KV / Upstash at the top of this handler, and rotate BUG_KEY periodically.
}
