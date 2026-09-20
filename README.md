# Peek

A minimal, native macOS window switcher — a lean AltTab-style replacement for
`⌘-Tab` with a left-side column of **live window previews**, a built-in
**dashboard of your switching habits** (SwiftUI + Swift Charts), and an order
that **learns which apps you actually use**.

## What makes it different

- **Sticky apps (opt-in, off by default)** — a learning layer: apps are ranked by
  *recency-weighted switch frequency* (7-day half-life), so the more you switch to
  an app the higher Peek floats it. Each row shows an **affinity meter** (signal
  bars) so you can see what it's learned. A first-run window explains it with a
  live demo; enable it there or anytime from the menu-bar icon. Until then, Peek
  is a classic `⌘-Tab`. The current window always stays at index 0.
- **Pinning (always on)** — pin apps to sit first via the 📌 button on every
  switcher row (or the dashboard's **"Your apps"** list). Pins float to the top
  independently of the learning layer.
- **RAM-lite** — only the *selected* window's thumbnail is ever captured, one at
  a time.
- **Live system footer** — CPU, memory, and battery at the bottom of the column,
  sampled on a light 2s timer.
- **Per-app CPU / RAM** — each tile shows the app's live CPU% and memory. Sampled
  only for the visible windows, only while the switcher is open, via a cheap
  per-pid `proc_pid_rusage` call — no global scan, no background polling.
- **Quit from the switcher** — an ✕ button on every row quits that app; hold ⌥
  while clicking to force quit. The row disappears immediately.
- **Settings** (menu bar → Settings…) — General (login item, menu-bar icon shape
  & tint, language), Appearance (theme, preview toggle, animations + fade + appear
  delay), Behavior (release action, arrow-key navigation, which display, Spaces),
  Shortcuts (⌘/⌥/⌃ + Tab and the in-switcher keys), and Apps (hide apps from the
  switcher).
- **Arrow-key navigation** — while holding the activation modifier, use ↑/↓ (or
  ←/→) to move the selection, not just Tab.

## Build & run

```bash
bash setup-signing.sh   # once: stable self-signed identity (permission grants then persist)
bash make-app.sh        # builds + installs /Applications/Peek.app (signed, release)
open /Applications/Peek.app
```

Without `setup-signing.sh`, `make-app.sh` falls back to ad-hoc signing and macOS
re-asks for permissions on every rebuild.

Peek lives in the menu bar (▤ icon). First launch prompts for two permissions:

1. **Accessibility** — to intercept `⌘-Tab` and raise windows.
2. **Screen Recording** — to read window titles and capture thumbnails.

Grant both in **System Settings → Privacy & Security**, then relaunch
`Peek.app`. (Ad-hoc signing keeps the grant stable across rebuilds.)

## Use

| Keys | Action |
|------|--------|
| `⌘-Tab` (hold ⌘) | show switcher, advance selection |
| `⌘-⇧-Tab` | advance backward |
| release `⌘` | switch to the highlighted window |
| `Esc` | cancel |
| hover a row / click | highlight / switch with the mouse |
| menu bar → **Switching Insights…** | open the dashboard (charts + pinning) |

## Layout

- `Sources/PeekCore/` — pure, tested logic: `SwitchEvent`, `StatsStore` /
  `PinStore` (JSON persistence), `StatsAggregator` (per-day / top-apps / hourly /
  transitions), `WindowRanker` (affinity scoring + pin-aware ordering).
- `Sources/Peek/` — the app: `HotKey` (CGEventTap), `WindowLister`
  (`CGWindowList` + thumbnails), `SwitcherPanel` (SwiftUI overlay),
  `WindowActivator` (Accessibility raise), `Dashboard` (Swift Charts).
- `Tests/PeekCoreTests/` — `swift test` covers the aggregation logic.

## Known limits (v1)

- **Blocking system `⌘-Tab`** relies on a `.cghidEventTap`. If macOS still
  shows its own switcher on your setup, it's a permission/timing issue — the
  fallback is to remap the trigger in `HotKey.swift` (e.g. Option+Tab).
- Window raise matches by **title**; apps with duplicate titles fall back to
  app activation. Precise per-window raise needs a private API.
- Thumbnails are captured on show via the (deprecated but working)
  `CGWindowListCreateImage`. Swap to ScreenCaptureKit if capture breaks.
- Stats are a single JSON file rewritten per switch — fine to thousands of
  events.
