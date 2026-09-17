# ClipStack

A small, free clipboard history for macOS. Lives in the menu bar, captures every
copy, and pastes it back where you were with **⌥⌘V**.

## Install

Download the latest DMG from [the releases page](https://github.com/mickey187/clipstack/releases/latest)
and drag ClipStack to Applications.

macOS shows a security prompt the first time you open it. Click **Done**, then open
**System Settings → Privacy & Security**, scroll to the bottom, and click
**Open Anyway**. One command does the same thing:

```bash
xattr -dr com.apple.quarantine /Applications/ClipStack.app
```

Then grant Accessibility when asked. Universal (Apple Silicon + Intel), macOS 14+.

## Build from source

Needs only the Xcode **Command Line Tools** (`xcode-select --install`) — not full Xcode.

```bash
./Scripts/create-signing-cert.sh   # once — see "Signing" below
./Scripts/build-app.sh             # builds a universal ClipStack.app and launches it
./Scripts/build-app.sh --host-only # skip the Intel slice for a faster dev loop
./Scripts/test.sh                  # unit tests
swift run                          # run in the terminal to watch stdout
```

## Releasing

```bash
./Scripts/make-icon.sh artwork.png        # once, or when the icon changes
./Scripts/release.sh 1.1.0 --dry-run      # build + DMG, no tag, no publish
./Scripts/release.sh 1.1.0                # tag, build, DMG, GitHub release
```

`release.sh` refuses to run on a dirty tree, or without the `ClipStack Local`
signing identity — releasing an ad-hoc build would cost every existing user
their Accessibility grant (see **Signing**). Back the key up with
`./Scripts/export-signing-cert.sh` and keep it somewhere you'll still have it
after a disk wipe; losing it has the same effect.

The landing page is `docs/index.html`, served by GitHub Pages from `/docs` on
`main`.

Then grant permission: **System Settings → Privacy & Security → Accessibility → add
`ClipStack.app`**.

## Using it

| | |
|---|---|
| **⌥⌘V** | Open the popup at the pointer |
| Just type | Search the history — the list narrows as you go |
| **⇥ / ⇧⇥** | Cycle the category: All, Text, Images, Links |
| **↑ / ↓** | Move the selection |
| **⏎** | Paste the selected item |
| **⌘1**–**⌘9** | Paste the nth item directly |
| **⌫** | Delete the selected item, or erase the search while you have one |
| **⌘⌫** | Delete the selected item even mid-search |
| **⎋** | Clear the search and category, then dismiss |
| Right-click the menu bar icon | Panel Size, Start at Login, Clear History, Quit |
| Hover a row → **⋯** | Pin / Unpin / Delete |

Pinned items are lifted to their own section and are never evicted. Search and
category reset every time the popup opens, so **⌥⌘V** always shows you everything.

## How it works

- **Capture** — macOS has no pasteboard-change notification, so `ClipboardMonitor`
  polls `NSPasteboard.general.changeCount` every 0.4s. Text wins over images when a
  copy carries both, because that is what the user meant.
- **Storage** — the newest 50 unpinned items in `~/Library/Application Support/ClipStack/`.
  Image bytes live as individual PNGs in `Blobs/`, not inline in the JSON, so a
  history full of screenshots doesn't get decoded into memory at launch. Only a
  small thumbnail is kept resident; the full image is read at paste time.
- **Pasting** — the popup takes key focus while it's open, so `Paster` records the
  frontmost app *before* showing, reactivates it afterwards, waits until it really
  is frontmost, and only then synthesises ⌘V. Posting the keystroke too early is
  the classic way this breaks.
- **Finding things** — typing goes straight into the query because the panel, not a
  text field, owns key handling; that is what keeps ↑/↓, ⏎ and ⌘1–9 working while
  you search. Filtering lives in `ClipStackCore` so it can be unit tested. **Links**
  means the whole entry is a URL, not merely that it contains one — otherwise half
  of all prose lands there. Text items include links, since a URL is still text.
- **Panel size** — Small, Medium (the default) or Large, from the menu bar. One
  multiplier scales the panel frame and every point size inside it together;
  growing the window alone would only show more rows at the same squint. Small is
  the 340×440 panel as it shipped before the setting existed.
- **Starting at login** — `SMAppService.mainApp`, so there is no LaunchAgent to ship.
  The menu item reads its checkmark back from the system every time it opens, because
  the registration can be switched off in System Settings without telling the app.
- **Privacy** — copies marked `org.nspasteboard.ConcealedType` (and the related
  transient/auto-generated types, and 1Password's own) are skipped, so passwords
  from a password manager never enter the history.

## Permissions

Only the synthetic ⌘V needs Accessibility. The hotkey does not —
`RegisterEventHotKey` has no TCC gate. So before you grant anything, ClipStack
still works: the popup opens, and selecting an item puts it on the clipboard for
you to paste yourself. The popup says so with a banner.

## Signing

`Scripts/create-signing-cert.sh` creates a self-signed code-signing certificate in
your login keychain, and `build-app.sh` signs with it.

This is not cosmetic. macOS ties the Accessibility grant to the app's signature,
and an ad-hoc signature (`codesign --sign -`) is identified only by its cdhash —
which changes on every build. Ad-hoc therefore means re-granting Accessibility
after *every single rebuild*. A stable certificate pins the grant to the
certificate instead — the designated requirement becomes
`identifier "com.mickey.clipstack" and certificate leaf = H"…"`, with no cdhash
in it — so you grant it once. The same holds for everyone who installs a
release: they keep their grant across updates only as long as every release is
signed with this same key. `build-app.sh` falls back to ad-hoc with a warning if
the identity is missing.

It does **not** affect Gatekeeper's first-launch prompt, which is governed by
notarization rather than by the signature.

## Layout

```
Sources/ClipStackCore/   Model and history logic — no AppKit, so it's unit tested
Sources/ClipStack/       AppKit + SwiftUI: menu bar, monitor, hotkey, panel, paste
Tests/                   swift-testing (CLT ships no XCTest; see Scripts/test.sh)
```

## Not in v1

File/folder copies, configurable history size and hotkey, sync.
