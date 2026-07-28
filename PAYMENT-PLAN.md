# Buddy × Kuma × WIMP — payment + funnel plan

_Captured 2026-07-15. Founder decisions from the payment/strategy session._
_Companion docs: `HOSTED-PLAN.md` (this repo, the app/service architecture) and
`~/Projects/buddy-site/KUMA-WIMP-PLAN.md` (the website/rebrand plan). This doc is
the source of truth for **how the money works**; §5 lists what the other two docs
need to change to align._

---

## 1. Founder decisions (locked 2026-07-14/15)

- **No subscription. Ever.** One-time pay-what-you-want. Nothing renews, nothing expires on a clock.
- **Polar** is the merchant for the app (true PWYW slider, merchant of record — they carry sales tax on app sales, per-sale fee only, no monthly bill).
- **Shopify** stays the merchant for coffee (it already runs the WIMP store). The two connect at exactly one point: a $23+ app purchase generates a **single-use Shopify coupon** (free bag + free shipping).
- **Passes from day one.** The sync-pass backend (HOSTED-PLAN §4) is built **before** the site launches. Every checkout — including $0 — issues a pass in the receipt.
- **Buddy/Kuma is a WIMP acquisition tool.** The app's job is attention; the coffee is the business. Payment is designed to be shareable, not extractive.
- **No review-gating.** "Free if you leave a review" is dropped — incentivized reviews are an FTC-disclosure problem (and banned on Amazon). Buying the coffee already is the support.
- **No verification of sharing.** The $0 tier asks people to tell someone about WIMP on the honor system. We never check. ("We're decaf — we don't have the energy to check.")

## 2. The offer — one slider, prices that tell jokes

One pay-what-you-want checkout on Polar, **default $10, minimum $0**. Every
price gets the full app + a sync pass. Labels carry the voice:

| You pay | Label (draft voice) | You get |
|---|---|---|
| **$0** | "Fine. Tell one person about WIMP. We trust you." | App + sync pass |
| **$10** (default) | "Solid buddy. Sync for life." | App + sync pass |
| **$23+** | "You just bought coffee. Check your email." | App + sync pass + **coupon: free bag of WIMP + free shipping** |

- The default anchors at $10 (Radiohead lesson: generous defaults are why PWYW averages above zero).
- The $23 threshold = the price of a bag. The joke is the marketing: *"this $10 app sends you decaf if you overpay."* That sentence is the screenshot people share.
- **Reverse loop:** a pass card goes inside WIMP coffee bags (vinyl-download-code pattern) — the coffee sells the app back.
- Future releases ship to everyone (no feature gates — complexity we refuse); big releases are the excuse to post ("passes free this week with any WIMP order").

## 3. The plumbing (what actually fires on a purchase)

```
buyer → Polar checkout (PWYW, min $0, default $10)
            │  webhook (Vercel function, buddy-site repo)
            ▼
   1. mint pass row (passes table, HOSTED-PLAN §4)
   2. if paid ≥ $23 → Shopify Admin API → single-use discount
      code (free bag + free ship on wimpdecaf.com)
   3. email: download link + pass (+ coupon if ≥$23)
      — Polar receipt and/or Ghost transactional
   4. buyer email → WIMP Ghost, Kuma newsletter, `kuma` label
```

- **The app itself stores no emails** — the no-accounts principle (HOSTED-PLAN) is about the app/server. Commerce (Polar/Shopify/Ghost) naturally holds buyer emails; that's the marketing list, cleanly separated from sync, which knows only `sha256(syncKey)`.
- Pass mechanics are unchanged from HOSTED-PLAN §4: pasted once on the Mac, rides the v2 QR, binds to `max_buckets` (3) on first use, distinguishable "hosting expired" error. "Expired" copy should be revisited — passes are lifetime, so the only error states are *missing* and *revoked*.
- **Beta testers get free-forever passes** before `require_pass` flips on.

## 4. Apple (the whole list)

- iOS app is free on the App Store and fully works as a local task list. ✅ already true.
- **Zero purchase surface in the iOS app** — no price, no link, no "get a pass at…". The pass arrives via the QR from the Mac. This is the Slack/Notion Guideline-3.1.3 pattern; no IAP, no 30%.
- App Review gets a working demo pass + paired setup in the review notes.
- Privacy label updates from "no data collected" (stats counts exist) — with E2E + no accounts the policy is a paragraph.
- If the public name becomes Kuma: the App Store **display name** can change without touching the bundle id — marketing rename is cheap, internals stay Buddy.

## 5. Cross-repo alignment — what each doc/repo must change

**`HOSTED-PLAN.md` (this repo)** — updated alongside this doc:
- Phase 2 is no longer "when ready to charge" — it **blocks site launch**. Merchant decision: **Polar** (was "Lemon Squeezy vs Paddle").
- Landing page is `kuma.wimpdecaf.com` (was `buddy.whale.fyi`).

**`buddy-site/KUMA-WIMP-PLAN.md` (other session owns this — deltas to fold in):**
- §4/§5: app checkout runs on **Polar, not Shopify**. Shopify's only role is the coffee coupon (created via Admin API from the Polar webhook). "Name-your-price product on Shopify" is out.
- §5: every purchase email must include the **sync pass**, not just a download link. Access is instant-on-purchase.
- Phase 3 (commerce) gains a dependency: **this repo's pass backend ships first** (tables + `require_pass` + pass-in-QR + error state).
- The site needs a Vercel serverless function for the Polar webhook (pass mint + Shopify coupon + Ghost subscribe).

**Not blocked / owned elsewhere:** WIMP Ghost admin key, `kuma.wimpdecaf.com` DNS, Kuma icon assets, escalation-colour decision — all tracked in the site plan's §9.

## 6. Launch work order (both repos, sequenced)

1. **Buddy repo — pass backend** (HOSTED-PLAN Phase 2, now critical path): `passes` + `pass_buckets` (+ RLS same commit), `require_pass`, pass field in v2 QR, paste-once field on Mac, distinguishable error in both apps. Free-forever passes minted for current testers **before** the flag flips.
2. **Buddy repo — service prep:** paid Supabase tier before first sale; privacy policy; iOS privacy label; App Store proper release (out of TestFlight) with demo pass in review notes.
3. **Site repo — rebrand + rehome** (Kuma skin, `kuma.wimpdecaf.com`) — parallel with 1.
4. **Site repo — commerce:** Polar product (PWYW, $10 default) + webhook function (pass, coupon, Ghost).
5. **End-to-end test:** $0, $10, and $23 purchases → pass syncs a fresh Mac+iPhone pair; coupon redeems a real free bag on wimpdecaf.com; buyer lands on the Kuma newsletter only.
6. Launch. Every release thereafter: RELEASE-CHECKLIST as usual.

## 7. Cost guardrail (the "no bills bigger than income" check)

Sync traffic is ~10 tiny encrypted rows/day/user; Supabase's paid tier ($25/mo,
required pre-sale anyway) covers thousands of users. One $10 pass covers years of
that user's actual cost. The real cost centre is the **free bag** (~one bag COGS
per $23+ order) — which is deliberate: it's customer acquisition for WIMP, priced
at exactly one bag.
