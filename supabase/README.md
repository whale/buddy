# Buddy sync backend (Supabase)

Buddy is **local-first** — it works fully offline and this backend is **optional**.
Turn it on only if you want your tasks to sync between your Mac and iPhone.

## The model (capability, no login)

One row per user holds your whole Buddy document as JSON, keyed by a **high-entropy
sync key** generated on first run. You link a second device by **scanning a QR code**
that carries the key — no email, no password.

Security: the table has RLS on with **no policies**, so the public anon key grants
*nothing* directly. All access goes through two `SECURITY DEFINER` functions
(`buddy_pull`, `buddy_push`) that only ever touch the one row matching the supplied
key — so no one can enumerate or read anyone else's data. The key is the secret.
`buddy_push` is last-write-wins by `updated_at` (a stale device can't clobber a
fresher one). See `migrations/*_buddy_state.sql`.

## Deploy your own (one time)

1. Create a project at **https://supabase.com/dashboard** (free tier is plenty).
2. Link this repo to it and push the schema:
   ```bash
   supabase login
   supabase link --project-ref <your-project-ref>   # ref is in the project URL
   supabase db push                                  # applies migrations/
   ```
3. From **Dashboard → Project Settings → API**, copy:
   - **Project URL** (e.g. `https://abcd.supabase.co`)
   - **anon public** key
4. Put those into Buddy's Settings → Sync (Mac shows a QR; the phone scans it).
   Nothing secret is committed — the anon key is publishable by design.

## Local development (optional)

Needs Docker running:
```bash
supabase start          # spins up a local stack + applies migrations
supabase status         # prints the local URL + anon key
supabase stop
```

## TODO before wide use
- Edge rate-limiting on the RPC endpoints (Supabase doesn't rate-limit RPC by
  default) to blunt brute-force/flood attempts, even though keys are 256-bit.
