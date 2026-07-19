# Beacon — Release Handoff (v1.0.7)

**Date:** 2026-07-19
**HEAD at handoff:** `4714f2e` on `main` (pushed to `origin/main`, tree clean)
**Version:** `1.0.7 (19)` — `Resources/Info.plist`
**For:** the signing/release agent taking v1.0.7 live.

This is the **first public release** — the GitHub repo has no prior releases. Everything below is committed and pushed; nothing is waiting locally.

---

## TL;DR — what you need to do to ship

Prereqs on the signing Mac (these are the reason this is handed off — they require the cert + Keychain the other machine has):

1. **Developer ID cert** `L76TDSSV4Z` imported into the login Keychain.
2. **Notary profile** created once:
   `xcrun notarytool store-credentials "beacon-notary" --team-id L76TDSSV4Z`
3. **Sparkle EdDSA private key** present in the login Keychain (public key is already in `Resources/Info.plist`). ⚠️ **Back this key up** — losing it means no future auto-updates can be signed.
4. **Paddle domain approval** for `beaconmac.com` must be live, then run a real test purchase end-to-end (`/claim` → key → in-app activation).

Then cut the release:

```bash
bash scripts/release.sh 1.0.7 --publish
```

That pipeline: build → sign (Sparkle XPC signed inside-out) → notarize app+DMG → `generate_appcast` (signs update, merges into `docs/appcast.xml`) → `wrangler pages deploy docs --project-name beaconmac` → GitHub Release → commit & push refreshed appcast.

**After a successful test purchase:** rotate the Paddle API key —
`wrangler secret put PADDLE_API_KEY` in `licensing/`. The key passed through chat during setup and must not stay in use.

---

## What changed since 1.0.6

Commits `d20c6dd..4714f2e` (12 commits). Grouped by theme:

### 🔄 Auto-updates (Sparkle)
- **Sparkle 2.9.4** vendored in `Vendor/` (SwiftPM is broken for this project — the real build path is the `swiftc` fallback in `scripts/run.sh`, so Sparkle is checked in rather than resolved as a package). — `6497be3`
- EdDSA **public key in `Info.plist`**; private key lives only in the signer's login Keychain.
- **Feed:** `SUFeedURL = https://beaconmac.com/appcast.xml` (served from `docs/appcast.xml` via Cloudflare Pages). The old GitHub Pages appcast URL is now a redundant mirror.
- `release.sh` runs `generate_appcast`, which **merges** new items into the existing appcast (history preserved) and signs each update.
- Site moved from `website/` → `docs/` for Pages compatibility. — `6497be3`

### 💳 Paddle subscription — **$15/yr** (yearly)
- **Price ID:** `pri_01kxvfwbt3n2www7ahy6ep68fp`. — `117086e`
- **License Worker** live at `license.beaconmac.com` (Cloudflare account `305ab752…`, KV `51e09be3…`):
  - `/claim` mints a license key from a Paddle transaction.
  - `/validate` checks a key (24h cache).
- Worker source in `licensing/`. The Paddle **secret API key is a Worker secret only** — never in the repo. (Also mirrored locally at `~/.config/beacon/paddle.env`, `chmod 600`.) **Rotate after test purchase.**
- **In-app:** `LicenseStore` with a 14-day grace period + gentle enforcement, plus an **"Enter License"** menu item.
- **Site checkout:** every purchase CTA opens the **Paddle checkout directly** (`data-buy` wiring). GitHub/source links are labeled and kept separate from Buy/Download CTAs. — `4714f2e`, `7ed3fa6`, `c39f12d`

### 🧾 Legal / licensing
- **PolyForm Internal Use 1.0.0** (`LICENSE.md`) — source-available, free to read/build/use personally or internally, **no redistribution**. Site/README say "source-available", never "open source" (deliberate). — `c48189f`
- **Terms, Refunds, Privacy** pages added under `docs/legal/`, linked from both footers. Live at `beaconmac.com/legal/{terms,refunds,privacy}`. — `169539c`
- Support: `support@beaconmac.com` → forwards to `claytonwendel@gmail.com` (CF Email Routing).

### 🏗️ Infra / distribution
- **Site + appcast + checkout** deploy to `beaconmac.com` via `wrangler pages deploy docs --project-name beaconmac` (direct-upload Pages project).
- **MAS ruled out** (sandbox blocks Full-Disk-Access reads). Distribution = **$15 direct sales via Paddle**, notarized DMG on GitHub releases.
- **Launch-at-login** via `SMAppService` (on-by-default once). — `37436da`
- **Log rotation** at 5 MB for `~/Library/Logs/Beacon.log`. — `37436da`
- Wrangler cache dirs git-ignored. — `9186821`

### 🔎 App improvements (bundled in this version)
- Search reliability, freshness, and **browse performance** fixes; customizable Finder-style browsing + refinements. — `7769485`, `514cc3d`, `1555c59`

---

## Verified at handoff
- `git status`: clean; `main` == `origin/main` == `4714f2e` (0 ahead / 0 behind after fetch).
- **No secrets tracked** in the repo: no `paddle.env`/`.env`/`.key`/`.pem` files, no hardcoded Paddle API key patterns in tracked files.
- Version stamped `1.0.7 (19)`; `SUFeedURL` correct.

## Open items after launch
- Rotate Paddle API key (see above).
- Back up the Sparkle EdDSA private key.
- Consider removing/rotating instrumentation log lines (`indexedBrowse`/`publishIndex`/`publishPage`) in `~/Library/Logs/Beacon.log` before wide distribution.
- Roadmap: Finder parity (drag-out, context menus, folder drill-in, multi-select), learned frecency ranking, CI/toolchain fixes, new sources (Reminders, bookmarks, Firefox, People).
