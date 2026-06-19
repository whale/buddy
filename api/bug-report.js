// Buddy bug-report intake — a tiny serverless proxy (Vercel).
//
// The desktop app POSTs { version, platform, logs, screenshot } here; we open a
// GitHub issue so reports land in one searchable place instead of an email draft.
//
// PRIVACY: a Buddy screenshot shows the user's task text, and the Buddy repo is
// PUBLIC — so reports go to a PRIVATE repo (BUG_REPO, default whale/buddy-bugs).
// The GitHub token never ships in the app; it lives only in this function's env.
//
// Env vars (set in Vercel → Project → Settings → Environment Variables):
//   GITHUB_TOKEN  — fine-grained PAT with Issues:write + Contents:write on BUG_REPO
//   BUG_REPO      — "owner/repo" of the PRIVATE intake repo (default whale/buddy-bugs)

const GH = 'https://api.github.com';

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

export default async function handler(req, res) {
  // CORS — the Tauri webview is a non-standard origin; allow it.
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });

  const token = process.env.GITHUB_TOKEN;
  const repo = process.env.BUG_REPO || 'whale/buddy-bugs';
  if (!token) return res.status(500).json({ error: 'server not configured (no GITHUB_TOKEN)' });

  const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body || {};
  const { version = '?', platform = '', logs = '', screenshot = '' } = body;
  const ts = Date.now();

  // Optionally store the screenshot in the PRIVATE repo and link it (data-URI PNG).
  let shotLink = '';
  if (typeof screenshot === 'string' && screenshot.startsWith('data:image')) {
    const b64 = screenshot.split(',')[1] || '';
    const path = `shots/${ts}.png`;
    try {
      const up = await gh(`/repos/${repo}/contents/${path}`, token, {
        method: 'PUT',
        body: JSON.stringify({ message: `bug screenshot ${ts}`, content: b64 }),
      });
      if (up.ok) shotLink = `\n\n[📷 screenshot](https://github.com/${repo}/blob/main/${path}) (opens in the private repo)\n`;
    } catch (_) { /* screenshot is best-effort; the logs are the point */ }
  }

  const title = `Bug — ${version} — ${new Date(ts).toISOString().slice(0, 16).replace('T', ' ')}`;
  const issueBody =
    `**From Buddy ${version}**\n\n` +
    `- platform: \`${String(platform).slice(0, 200)}\`\n` +
    shotLink +
    `\n\`\`\`\n${String(logs).slice(0, 8000)}\n\`\`\`\n`;

  const issue = await gh(`/repos/${repo}/issues`, token, {
    method: 'POST',
    body: JSON.stringify({ title, body: issueBody, labels: ['bug-report'] }),
  });
  if (!issue.ok) {
    const detail = await issue.text();
    return res.status(502).json({ error: 'github issue create failed', detail: detail.slice(0, 500) });
  }
  const data = await issue.json();
  return res.status(200).json({ ok: true, url: data.html_url });
}
