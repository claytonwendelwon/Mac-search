# Beacon

A fast, native macOS search launcher. Press a hotkey anywhere, type, and
instantly find any file, app, photo, video, or document on your Mac, then open
it with a keystroke.

Beacon taps directly into the system Spotlight index (`NSMetadataQuery`), so
results are instant and there's no separate disk crawl to wait on. It's a
lightweight menu-bar app with a keyboard-driven overlay, in the spirit of
Spotlight / Raycast / Alfred, but tuned for finding files.

## Features

- Global hotkey overlay: summon the search bar from any app.
- Live results as you type, with smart ranking (exact name matches and your
  own files first; folders surface reliably).
- Searches by name **and by text inside documents** (PDFs, text, Office/iWork,
  etc.); content matches are flagged with a "text match" badge.
- Type filters: All, Apps, Photos, Videos, Docs, PDFs, Audio, Folders.
- Fully keyboard-driven (no mouse needed).
- Quick Look previews, reveal in Finder, copy path.
- Native Swift/SwiftUI, zero third-party dependencies.

## Download (for users)

1. Go to the [latest release](https://github.com/claytonwendelwon/Mac-search/releases/latest).
2. Download `Beacon-<version>.dmg`.
3. Open the `.dmg` and drag **Beacon** into your **Applications** folder.
4. Launch Beacon from Applications. It lives in the menu bar (magnifying-glass icon).
5. Press **Option + S** anywhere to search.

The app is signed with a Developer ID and notarized by Apple, so it opens
without security warnings.

## Requirements (to build from source)

- macOS 13 or newer.
- Xcode command-line tools / Swift toolchain (`swift --version`).

## Build & run

From the project root:

```bash
bash scripts/run.sh
```

This builds the app, assembles `Beacon.app`, ad-hoc signs it, quits any running
copy, and launches the new build. Look for the magnifying-glass icon in your
menu bar.

To build a debug variant, set `CONFIG=debug bash scripts/run.sh`.

## Using Beacon

- **Open / close:** `Option + S` (toggles the search bar). Also available by
  clicking the menu-bar icon. (`Cmd + S` is left alone for Save, and
  `Cmd + Space` for Spotlight.)
- **Type** to search by name. Multiple words narrow the results (all words must
  appear in the name).
- **Filter by type:** click a chip, or press `Tab` / `Shift + Tab` to cycle.

### Keyboard shortcuts

| Key            | Action                          |
| -------------- | ------------------------------- |
| `↑` / `↓`      | Move selection                  |
| `return`       | Open the selected item          |
| `⌘ return`     | Reveal in Finder                |
| `⌘ Y`          | Quick Look preview              |
| `⌘ C`          | Copy the file's path            |
| `Tab` / `⇧Tab` | Cycle type filter               |
| `esc`          | Dismiss the search bar          |

> Note: Quick Look is mapped to `⌘ Y` (instead of the Finder-style `Space`)
> because `Space` is needed for typing multi-word searches.

## Full Disk Access (optional)

Spotlight already indexes most user locations, so Beacon works out of the box.
For complete coverage of every folder (including some system and protected
locations), grant access once:

1. Open **System Settings → Privacy & Security → Full Disk Access**.
2. Add `Beacon.app` and enable it.
3. Quit and relaunch Beacon (`bash scripts/run.sh`).

## How it works

```
Hotkey / menu bar  ->  floating NSPanel  ->  SwiftUI SearchView
                                                   |
                                          SearchEngine (NSMetadataQuery)
                                                   |
                                            Spotlight index
```

- `Sources/Beacon/HotKey.swift` registers the global hotkey via the Carbon
  Hot Key API (no Accessibility permission required).
- `Sources/Beacon/SearchPanel.swift` is a borderless, floating, non-activating
  panel that hosts the SwiftUI UI.
- `Sources/Beacon/SearchEngine.swift` builds the Spotlight predicate
  (name tokens + `kMDItemContentTypeTree` filter), runs a debounced live query,
  and publishes sorted, capped results.
- `Sources/Beacon/FileType.swift` maps each filter chip to Uniform Type
  Identifiers.

## Roadmap (distribution)

- Settings UI with a customizable hotkey recorder and result limits.
- Developer ID signing + notarization, packaged as a `.dmg`.
- Optional content-aware search (text inside documents/PDFs, on-device photo
  recognition).
