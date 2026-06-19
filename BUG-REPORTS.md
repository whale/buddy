# Buddy bug reports — where they go & how to turn them on

When someone clicks **Report a bug** in Buddy, the app sends a screenshot + a bit
of diagnostic info to a tiny web function, which files it as a **GitHub issue in a
private repo** you own. You (and Claude, via `gh`) read those each session. No more
email-to-yourself.

**Why private:** a screenshot shows your task text, and the Buddy code repo is
public — so reports go to a separate **private** repo instead.

Until the four setup steps below are done, Buddy quietly falls back to the old
"open a mail draft" behaviour, so nothing is ever lost.

---

## One-time setup (about 10 minutes)

### Step 1 — Make the private inbox repo
1. Go to **https://github.com/new**
2. Repository name: type **`buddy-bugs`**
3. Click the **Private** circle.
4. Click **Create repository**.

### Step 2 — Make a key the function can use
1. Go to **https://github.com/settings/tokens?type=beta** (fine-grained tokens).
2. Click **Generate new token**.
3. Name: type **`buddy-bug-reports`**.
4. Under **Repository access**, choose **Only select repositories** → pick **`buddy-bugs`**.
5. Under **Permissions → Repository permissions**, set **Issues** to **Read and write**, and **Contents** to **Read and write**.
6. Click **Generate token**, then **copy** the token (a long `github_pat_…` string). Keep this tab open.

### Step 3 — Put the function online (Vercel)
1. Go to **https://vercel.com/new**.
2. Click **Import** next to your **`buddy`** repository.
3. Before clicking Deploy, open **Environment Variables** and add two:
   - Name: **`GITHUB_TOKEN`** — Value: paste the token from Step 2.
   - Name: **`BUG_REPO`** — Value: type **`whale/buddy-bugs`**.
4. Click **Deploy**.
5. When it finishes, copy the site address it gives you (looks like **`https://buddy-xxxx.vercel.app`**).

### Step 4 — Point Buddy at it
1. In `dist/index.html`, find the line that starts with **`const BUG_ENDPOINT =`**.
2. Replace the placeholder URL with your address from Step 3, keeping the
   `/api/bug-report` at the end, e.g. **`https://buddy-xxxx.vercel.app/api/bug-report`**.
3. Build a new Buddy and ship it (per `RELEASE-UPDATER.md`).

That's it. Click **Report a bug** in Buddy → a new issue appears in **`buddy-bugs`**.

---

## How it works (for later)

- `api/bug-report.js` — the serverless function. Receives `{version, platform, logs,
  screenshot}`, commits the PNG into the private repo under `shots/`, and opens an
  issue labelled `bug-report` linking it.
- `dist/index.html` `reportBug()` — POSTs to `BUG_ENDPOINT`; on any failure (offline
  or not-yet-configured) it falls back to the native mail draft.
- The token never ships inside the app — it lives only in Vercel's env vars.

## Reading reports each session
```
gh issue list --repo whale/buddy-bugs --label bug-report
gh issue view <n> --repo whale/buddy-bugs
```
