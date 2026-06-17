# Buddy — Project Rules

Buddy is a calm macOS menu-bar focus app: pick your top three each morning, a
right-edge drawer holds them all day, complete them, glance at history. Single
self-contained web app in `dist/index.html` wrapped in a Tauri v2 shell
(`src-tauri/`). No build step for the web app.

---

## 🔴 RULE 1 — Use the escalation theme tokens. NEVER hardcode adaptive colours.

Buddy has three escalation levels driven by **active** task count:

- **lvl0** — normal (white cards, black text)
- **lvl1** — 5 active → all text turns **red** (the "you're getting full" warning)
- **lvl2** — 6 active → the **whole drawer background turns red**, text turns light

The UI re-themes itself across these states **entirely through CSS custom
properties** defined in the `<style>` block. When you add or change any UI that
shows text/borders/icons on a card, you MUST use these tokens so it adapts:

| Token | lvl0 (white) | lvl2 (red bg) | Use for |
|-------|-------------|---------------|---------|
| `var(--ink)` | `#000` | `#fff` | primary text |
| `var(--ink-dim)` | `rgba(0,0,0,.45)` | `rgba(255,255,255,.6)` | secondary / done / dim text |
| `.chrome` class | black | white (red on lvl1) | header glyphs that should go red at lvl1 |
| `.bd` class | `#d9d9d9` border | `rgba(255,255,255,.3)` | adaptive card borders/dividers |
| `var(--chrome-ink)` / `--sel-bg` / `--sel-ink` / `--line` | … | … | buttons, selected pills, lines |

**Hardcoding `text-black`, `text-black/35`, `rgba(0,0,0,…)`, `#000`, `border-[#d9d9d9]`
on anything that sits on a card is a BUG** — it stays dark on the red background and
becomes illegible (this exact mistake shipped the unreadable "Donezo" rows on red).

- "Done" / Donezo rows are **neutral but adaptive** → `--ink` (label) + `--ink-dim`
  (struck title). They must NOT use `.chrome` (that turns them red at lvl1 — done
  work isn't pressure) and must NOT be hardcoded dark (illegible at lvl2).
- Active task text is the exception: it intentionally uses the escalation colours
  directly (`#fff` at lvl2, `RED` at lvl1, `#000` otherwise).

---

## 🧪 RULE 2 — Verify every build before shipping. Two gates, both required.

A change that "looks cosmetic" can break shared plumbing three steps away
(rendering, attributes, focus, colours). Before **every** `pnpm tauri build`:

1. **Functional smoke test.** Serve `dist/` and run in the console:
   ```js
   await window.__buddy.smokeTest()   // must return { ok: true }
   ```
   It asserts: add focuses the new task, edit focuses the task text, complete
   marks done + drops the red count, undo restores, rows don't reuse `data-tid`,
   and **lvl2 done text adapts to light** (the red-bg legibility guard).

2. **Visual red-state sweep.** Inject states and screenshot all three levels;
   confirm every element is legible and correctly themed:
   - **lvl0**: ≤4 active — black text on white.
   - **lvl1**: exactly 5 active — all text red on white.
   - **lvl2**: 6 active — light text on red background (check Donezo rows, dividers,
     icons, the date card, settings sheet).

   Force a level by injecting items (see `__buddy.inject`); lvl = active count.
   Both `ok:true` AND a clean visual sweep are required — neither alone is enough.

---

## Releasing / auto-updater

See `RELEASE-UPDATER.md`. Builds are signed + notarized (Apple creds in `.env`,
local only) and updater-signed (key at `~/.tauri/buddy-updater.key`). Ship a new
version by bumping `package.json` + `src-tauri/Cargo.toml` + `tauri.conf.json` in
lockstep, building, then `gh release create` with the DMG, `Buddy.app.tar.gz`,
and a `latest.json` manifest. The installed app auto-checks and shows an update
banner. Repo is public (MIT).

## Foundation

Buddy's design language follows the shared Foundation system — prefer its tokens
and primitives over inventing local ones. When a colour/spacing/type value needs
to adapt to state, it belongs in a token, not inline.
