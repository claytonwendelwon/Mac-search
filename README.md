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
  etc.); content matches are flagged with a "text match" badge and kick in
  once the query is 3+ characters (name search is instant from the first).
- All matching is case- and accent-insensitive across every source
  ("jose" finds "José" in files, messages, notes, and history alike).
- **Search your text messages** (iMessage & SMS) under the Messages filter:
  find by word, phrase, or **contact name** across your whole history
  (typing "Mom" surfaces Mom's messages, not just texts containing the word);
  results show the
  **contact's name**, a snippet centered on the match, and when it was sent.
  `return` opens the conversation in Messages and `⌘C` copies the text.
  (Requires Full Disk Access; sender names use Contacts — see below.)
- **Search your Apple Notes** under the Notes filter: full-text search across
  every note (title + body), with the matched word shown and bolded; `return`
  opens Notes. (Uses the same Full Disk Access as Messages.)
- Matched words are **bolded** in result titles and message/note snippets.
- Type filters: All, Apps, Messages, Notes, Docs, PDFs, Audio, Folders,
  Photos, Videos.
- Fully keyboard-driven (no mouse needed).
- Quick Look previews, reveal in Finder, copy path.
- Native Swift/SwiftUI, zero third-party dependencies.

## Download (for users)

1. Go to the [latest release](https://github.com/claytonwendelwon/Mac-search/releases/latest).
2. Download `Beacon-<version>.dmg` and open it.
3. **Double-click Beacon** - it installs itself into Applications, relaunches
   from there, and opens the search bar with a first-run hotkey tip.
   (Dragging it to Applications works too.)
4. Press **Option + S** anywhere to search. Beacon lives in the menu bar.

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

## Full Disk Access

Spotlight already indexes most user locations, so **file search works out of the
box** with no permissions. Full Disk Access unlocks the extras:

- **Message search** (reading `~/Library/Messages/chat.db`),
- **Notes search** (reading the Apple Notes database), and
- complete coverage of every folder, including some protected locations.

Beacon touches the Messages database once at launch, so it automatically appears
in the Full Disk Access list — you don't need the `+` button. To grant it:

1. In Beacon, select the **Messages** filter and click **Open Settings**
   (or open **System Settings → Privacy & Security → Full Disk Access**).
2. Find **Beacon** in the list and turn its switch **on**.
3. When prompted, choose **Quit & Reopen** (or relaunch Beacon).

> If Beacon isn't listed yet, launch it once first, then reopen the list — or
> drag `Beacon.app` from Applications into the list.

The first time you search Messages, macOS also asks for **Contacts** access —
allow it to see sender names instead of raw phone numbers. If you decline,
message search still works; it just shows the number/email.

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
- `Sources/Beacon/MessageStore.swift` powers the Messages filter: it opens the
  Messages SQLite database read-only, decodes message text (including the binary
  `attributedBody` blobs newer macOS uses), caches recent messages in memory,
  and filters them as you type.
- `Sources/Beacon/NotesStore.swift` powers the Notes filter: it opens the Apple
  Notes SQLite database read-only and decodes each note body (gzip-compressed
  protobuf) to enable full-text search across your notes.

## Roadmap (distribution)

- Settings UI with a customizable hotkey recorder and result limits.
- Developer ID signing + notarization, packaged as a `.dmg`.
- Optional content-aware search (text inside documents/PDFs, on-device photo
  recognition).
