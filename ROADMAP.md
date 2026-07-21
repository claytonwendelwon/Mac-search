# Beacon Roadmap

**Goal:** the best Spotlight/Finder replacement on macOS — not a search box, a place you *find and act on* everything.
**Written:** 2026-07-21. Anchored to code at `main`. File:line refs are where the work lands or the gap lives.

---

## Where we stand today

**Solid — the launch layer.** Enter opens the right thing per type, ⌘Return reveals in Finder, ⌘Y is QuickLook, ⌘C copies file URL + text, and Messages/Notes/Mail/Calendar/Clipboard get real in-app previews. — `SearchView.swift:1869-2026`

**Broad — source coverage.** Files, folders, apps, recents, cloud drives, doc types, Messages, Notes, Mail, Calendar, browser history, clipboard, system settings.

**The strategic gap.** Every result is a *"launch it somewhere else"* link. You find a thing, then bounce to Finder/Mail/Notes to actually do anything with it. Closing that gap — acting on items *in place* — plus *learning what you use* is what makes Beacon beat Finder + Spotlight instead of just supplementing them.

---

## Phase 1 — Act on items in place ("Finder-like tech")

The highest-impact work. Turns results from links into manipulable objects. All four are currently **absent**.

- [ ] **Drag-out** — drag a file from Beacon into a folder, email, Slack, upload dialog. *The* Finder gesture; zero drag-source code exists today. Self-contained, highest bang — **start here.** (NSItemProvider / drag source on result rows in `SearchView.swift`.)
- [ ] **Right-click context menu** — Finder's core action set: Open With, Move to Trash, Rename, Duplicate, Compress, Get Info, Share. No `contextMenu` anywhere today. *(Tags intentionally excluded — nobody uses Finder tags.)*
- [ ] **"Open With…"** — application chooser. Trivial next to the above, high daily utility.
- [ ] **Multi-select + bulk actions** — today `selectedIndex` is a single `Int` (`SearchView.swift:12`); no shift/⌘-click, no bulk move/trash.

## Phase 2 — Folder drill-in / browse-in-place

- [ ] **Drill into folders without leaving Beacon.** Today opening a folder kicks you to Finder (`SearchView.swift:1889`). Add → to enter a folder, a breadcrumb, browse, and back out. The browse-mode plumbing (`indexedBrowse`) already exists — this is an extension, not greenfield.

## Phase 3 — The moat: learned frecency ranking

- [ ] **Track opens and rank by them.** Ranking today is pure string-match tiers + a `lastUsed` tiebreaker and does **not** track what you open (`SearchEngine.swift:2961-2994`). Only browser history has true frecency (`BrowserHistoryStore.swift:113-126`).
- [ ] Log opens per result, boost by frequency × recency across *all* types. Spotlight structurally can't prioritize "the thing Clayton opens every Monday." **This is the differentiator** — and the frecency formula to copy already lives in our own codebase.

## Phase 4 — More sources (refactor first)

- [ ] **Extract a shared `Source` protocol FIRST (~1-2 days).** There's no shared abstraction today — every store re-implements permissions, caching, folding, and wiring across ~12-15 points in `SearchEngine`. Adding 4-5 more the current way compounds the duplication.
- [ ] **Reminders** — EventKit, ~200 LOC, near-identical to `CalendarStore`. Easiest.
- [ ] **Contacts / People** — Contacts framework already imported for Messages name resolution; ~250 LOC.
- [ ] **Bookmarks (Safari/Chrome/Firefox)** — extend `BrowserHistoryStore`, ~100-200 LOC.
- [ ] **Spotlight comments** — ~50 LOC; data already in the metadata we read. *(Tags dropped — unused.)*
- [ ] **Gmail** — partial scaffolding exists (`searchGmail`, Gmail account detection) but it's the expensive one (OAuth). Defer.

## Phase 5 — Make it extremely smooth (polish pass)

The real risks found in the code, in priority order:

- [ ] **Main-thread metadata reads during refinements** (`SearchEngine.swift:2850-2855`) — can freeze the UI on large browses. **HIGH.** Move facet reads off the main thread.
- [ ] **No passive filesystem watching** — index only refreshes on panel-show + a 60s snapshot TTL, so freshly created files lag. Add FSEvents / Spotlight-live watching so "I just saved it" appears instantly.
- [ ] **Message DB query pileup** on rare/huge-history searches — mitigated by token cancellation, but real.

---

## Recommended sequence

1. Drag-out → most visceral "whoa, it's a real Finder" upgrade, unblocks nothing else.
2. Right-click context menu → completes the act-in-place story.
3. Learned frecency → the moat.
4. Folder drill-in.
5. `Source` protocol refactor + Reminders / Contacts / bookmarks.
6. Smoothness hardening pass.

*Rationale: breadth (more sources) isn't the moat — acting in place and learning your habits are. Do those first, then widen, then polish.*
