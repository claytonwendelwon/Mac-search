# Beacon — Release Handoff (v1.0.8)

**Date:** 2026-07-24
**HEAD at handoff:** `main` at the commit that adds this file (pushed to `origin/main`, tree clean)
**Version:** `1.0.8 (20)` — `Resources/Info.plist`
**For:** the signing/release agent taking v1.0.8 live.

Still the **first public release** — the GitHub repo has no prior releases; v1.0.7 was staged but never cut. Everything below is committed and pushed; nothing is waiting locally.

> ⚠️ **Payments changed since the old handoff: we moved OFF Paddle to Lemon Squeezy.** Ignore any earlier Paddle instructions. There is **no Paddle API key to rotate** — the current Worker needs no secret at all.

---

## TL;DR — what you need to do to ship

Prereqs on the signing Mac (the reason this is handed off — they need the cert + Keychain this machine has):

1. **Developer ID cert** `L76TDSSV4Z` imported into the login Keychain.
2. **Notary profile** created once:
   `xcrun notarytool store-credentials "beacon-notary" --team-id L76TDSSV4Z`
3. **Sparkle EdDSA private key** in the login Keychain (public key is already in `Resources/Info.plist`). ⚠️ **Back this key up** — losing it means no future auto-updates can be signed.

Then cut the release:

```bash
bash scripts/release.sh 1.0.8 --publish
```

Pipeline: build → sign (Sparkle XPC inside-out) → notarize app+DMG → `generate_appcast` (signs, merges into `docs/appcast.xml`) → `wrangler pages deploy docs --project-name beaconmac` → GitHub Release → commit & push appcast.

**No Paddle key rotation, no domain-approval wait.** Payments already work (see below).

---

## Payments & licensing — CURRENT STATE (Lemon Squeezy)

**Why the change:** Paddle never approved `beaconmac.com` (overlay checkout needs domain approval — stuck 7+ days; hosted checkout is gated behind a separate support request). We pivoted to **Lemon Squeezy** (merchant-of-record, native license keys, no domain approval). Paddle is fully removed from the site; the Worker's Paddle `/claim` handler is kept **dormant** only so we can flip back if Paddle ever approves.

- **Product:** Beacon, **$15/year subscription with a 7-day free trial** (trial configured in Lemon Squeezy — card up front, first charge deferred 7 days).
- **Store:** `beaconmac.lemonsqueezy.com`, **product ID `1241992`**.
- **Checkout URL** (site Buy buttons + in-app "Start free trial"):
  `https://beaconmac.lemonsqueezy.com/checkout/buy/636f0d26-1b9b-4ca4-8434-4476b0f132fe`
- **Key delivery:** Lemon Squeezy generates the license key and shows it on its own confirmation screen + receipt email. `docs/beacon/thanks.html` is just post-purchase instructions (no key-minting).
- **License Worker** (`licensing/`, live at `license.beaconmac.com`):
  - `POST /validate {key}` → checks the key against LS's `/v1/licenses/validate`, and **requires `meta.product_id == 1241992`** so a license key from any other LS store can't unlock Beacon. Normalizes case (app uppercases; LS keys are lowercase UUIDs). Returns `{valid, expiresAt}`. 24h KV cache. **Needs no secret.**
  - `POST /claim` → dormant Paddle path (unused).
  - Worker vars (public, in `wrangler.toml`): `LS_PRODUCT_ID=1241992`, `LS_STORE_ID=""` (optional).
  - **Already deployed.** Redeploy only if `licensing/` changes: `cd licensing && npx wrangler deploy`.
- **Subscription lifecycle (verified against LS docs):** active/trialing → key `active` → valid. Cancelled-but-in-period → still `active` → valid (they paid). Trial ends w/o payment, or sub expires → key `expired` → invalid. Renewal → extended → valid.

### License enforcement (NEW — ships with THIS build)
Previously the app enforced nothing (an unlicensed build ran fully). Now:
- `LicenseStore` (ObservableObject) gates the UI. `SearchView` shows a **full-panel lock** when status is **unlicensed or lapsed**; **licensed** and **grace** (14-day offline window after a prior valid check) keep working.
- Lock offers **"Start your 7-day free trial"** (opens the LS checkout) and **"Enter License…"**. A valid key — including an active trial key — dismisses it instantly.
- **DEV BYPASS:** `defaults write com.beacon.search beacon.dev.bypass -bool YES` grants access for local dev. It's a per-machine UserDefaults key — **make sure it is NOT set on the signing Mac**, or the shipped build won't enforce. (It won't be, unless someone sets it.) Confirm with `defaults read com.beacon.search beacon.dev.bypass` → should be absent / `0`.
- Caveat: source is public, so the hard lock only meaningfully gates the distributed signed binary.

---

## What changed since the old v1.0.7 handoff

Commits `2e0e543..HEAD`:
- **Finder-style result actions:** drag-out (real file references, multi-item via AppKit), right-click context menu (Open, Open With, Quick Look, Reveal, Get Info, Copy, Duplicate, Rename, Compress, Move to Trash), multi-select + bulk actions.
- **Folder drill-in / browse-in-place:** Enter/→/double-click a folder browses into it with a breadcrumb; drag-onto-folder moves files (⌥ = copy); custom cascading "Move to" menu (capped, scrollable, hover-open, overlap-stacked).
- **Payments pivot Paddle → Lemon Squeezy** + **license enforcement + 7-day trial** (above).
- **Perf:** logging moved off the main thread (was opening/closing a file handle per call on the main thread during search); per-tick debug logs removed.
- **Site:** Buy CTAs are single-click same-tab redirects to the LS checkout.

---

## Verified at handoff
- `git status` clean; `main == origin/main` (0/0 after fetch).
- **No secrets tracked** in the repo (no `.env`/`.key`/`.pem`; the LS Worker needs none).
- Release build (`CONFIG=release bash scripts/run.sh`) compiles clean via the `swiftc` fallback (SwiftPM still broken — expected).
- Site + Worker already deployed on Lemon Squeezy; the license Worker validates correctly (probed live).
- Version stamped `1.0.8 (20)`; `SUFeedURL = https://beaconmac.com/appcast.xml`.

## Open items
- Back up the Sparkle EdDSA private key.
- Confirm dev-bypass is NOT set on the signing Mac (see above).
- Post-launch smoke test: trial signup → key in email → Enter License activates → cancel/expire → app locks.
- `beaconmac.com` is a Cloudflare Pages **direct-upload** project — `git push` does NOT auto-deploy; the site goes live via `wrangler pages deploy docs` (release.sh already does this). Consider connecting it to Git for auto-deploy later.
- Roadmap remaining: Phase 3 learned frecency ranking; Phase 4 source-protocol refactor + new sources (Reminders, Contacts, bookmarks); finish Phase 5 perf (main-thread facet reads, FSEvents freshness).
