# Buddy / Kuma / WIMP — ecosystem map

_One page. Which repo owns what, which doc is the source of truth for what, and
how sessions stay out of each other's way. Update this when a lane or owner
changes._

## The repos (4)

| Repo | Path | Lane (what it owns) |
|---|---|---|
| `whale/buddy` | `~/Projects/buddy` | **The product.** Mac + iOS apps, sync backend (Supabase SQL), releases/updater, the pass backend (Phase 2) |
| `whale/buddy-site` | `~/Projects/buddy-site` | **The funnel.** Kuma marketing site, Polar checkout + webhook function, Ghost newsletter wiring |
| `wimpdecaf/stickers` | `~/Projects/wimp-stickers` | **The mascot.** Kuma character art — icon source for the rebrand |
| _(no repo)_ WIMP Shopify + Ghost | `~/Projects/wimp-decaf` (workspace) | **The store + brand.** Coupon redemption, coffee fulfilment, pass cards in bags, WIMP voice |

## Doc source of truth

| Question | Doc |
|---|---|
| How does the app/service/sync/pass work? | `buddy/HOSTED-PLAN.md` |
| How does the money work? (Polar, tiers, coupon, Apple) | `buddy/PAYMENT-PLAN.md` |
| What is the site/rebrand/launch plan? | `buddy-site/KUMA-WIMP-PLAN.md` |
| What shipped, what's next in the app? | `buddy/STATUS.md` (top) |

A decision that spans repos gets **decided once, written in its owning doc**,
and the other docs point at it — never restated in full (copies drift).

## Contract points between lanes (change these = update both sides)

1. **The pass** — minted by the site's webhook, validated by the app's backend.
   Schema and rules live in `HOSTED-PLAN.md` §4; the site consumes them.
2. **The download link** — the site points at `whale/buddy` GitHub releases.
3. **The coupon** — site webhook mints it via Shopify Admin API; it must redeem
   on wimpdecaf.com (free bag + free shipping).
4. **The drawer** — the site embeds the real Buddy engine and mirrors
   `buddy/dist/index.html` (radius, tokens, celebration). App look changes must
   be mirrored on the site.
5. **The name** — public/marketing name is Kuma; app internals stay Buddy until
   a deliberate rename (bundle id, updater identity, App Store).

## Session rules

- **One session per repo.** A session works its own lane and does not edit the
  other repos' files (exception: doc alignment passes like this one, when the
  other lane has no live session).
- **Read this map + your repo's plan doc at session start.**
- Cross-lane needs → write the ask into your own plan doc's open-decisions
  section and surface it to Matthew; don't reach into the other repo's code.

## Launch dependency order (2026-07-15)

```
buddy: pass backend (Phase 2)  ──►  buddy-site: Polar checkout + webhook  ──►  launch
buddy-site: Kuma rebrand + kuma.wimpdecaf.com DNS   (parallel, no dependency)
wimp: Shopify coupon rule + Kuma icon asset          (parallel, small)
```
