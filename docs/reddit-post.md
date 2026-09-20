# Reddit post draft

**Suggested subreddits:** r/macapps (best fit), r/opensource, r/SwiftUI, r/macOS
(check each sub's self-promo / "Show off" rules first — r/macapps is developer-friendly).

**Attach:** the switcher screenshot as the main image, plus the dashboard and settings
(`docs/images/`). Reddit lets you add an image gallery — lead with the switcher.

---

## Title

> I built Peek — an open-source macOS ⌘-Tab replacement that learns which apps you actually use

*(alt: “Peek: a native ⌘-Tab switcher for macOS that ranks your windows by real usage — free & open source”)*

---

## Body

I got tired of the macOS `⌘-Tab` switcher showing me the same flat, most-recently-used
order every time, so I built **Peek** — a native (SwiftUI + AppKit) window switcher that
**replaces the system switcher and gets smarter the more you use it**. It's free and open
source.

**It overrides the macOS switcher — same keys.** Peek intercepts `⌘-Tab` at the system
level, so nothing changes in your muscle memory: hold `⌘`, tap `Tab`, and you get Peek's
column instead of Apple's. The native switcher never shows up. (You can remap it to
`⌥-Tab` or `⌃-Tab` if you'd rather keep the system one.)

**The main idea: smart ordering.** Two layers, and they're independent:

- 🧠 **Sticky apps (opt-in, off by default)** — a learning layer scores each app by
  *recency-weighted switch frequency* (7-day half-life). The more you switch to an app, the
  higher Peek floats it, automatically — your busiest apps drift to the top and are always
  the first keystroke away. Every row shows an "affinity meter" so you can see what it's
  learned. Until you turn it on, it's just a nicer classic `⌘-Tab`.
- 📌 **Pinning (always on)** — pin the apps you always want first; they float to the top
  regardless of the learning layer. Pins = your fixed home row, sticky apps orders the rest.

**It also shows you how you work.** There's a built-in **Switching Insights** dashboard
(Swift Charts) — total switches, busiest hour, most-used app, switches per day, your most
common app-to-app transitions, and the exact order driving the switcher. That history is
also the groundwork for what I want to build next: **customizable, per-user workflows** —
surfacing the right set of apps for the task and time of day you usually do it.

**Other bits:**
- Live window previews (RAM-lite — only the selected window is ever captured, via
  ScreenCaptureKit)
- Per-app live CPU/RAM on each row + a system CPU/RAM/battery footer
- Quit or force-quit an app straight from the switcher
- Keyboard-first: `1`–`9` jump to a window, `Home`/`End`, `P` to pin, `Q`/`W` to quit
- Themes, 5 languages (incl. Arabic RTL), in-app auto-update

It's macOS 14+, Apple Silicon or Intel, built with Swift Package Manager. Needs
Accessibility (to intercept `⌘-Tab`) and Screen Recording (for titles + thumbnails) — the
usual for this kind of tool, and it's all local; nothing leaves your machine.

**Repo:** https://github.com/doitrous/peek

Would genuinely love feedback — especially on the ranking model and what workflow automations
would actually be useful to you. Issues and PRs welcome.

---

## First-comment (drop your build/permissions note here so the post stays clean)

Build is `bash setup-signing.sh && bash make-app.sh`. Because I'm still setting up a
Developer ID cert, right now it's self-signed — if you build it yourself it just works;
a notarized download is coming. Happy to answer anything about how the affinity scoring or
the `⌘-Tab` interception works.
