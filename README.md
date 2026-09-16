# ClipStack

A small, free clipboard history for macOS. Lives in the menu bar, captures every
copy, and pastes it back where you were with **⌥⌘V**.

## Install

Download the latest DMG from [the releases page](https://github.com/mickey187/clipstack/releases/latest)
and drag ClipStack to Applications.

The first launch is blocked: ClipStack isn't notarized, because notarizing needs a
$99/year Apple Developer ID. macOS says *"Apple could not verify 'ClipStack' is free
of malware."* Click **Done**, then **System Settings → Privacy & Security**, scroll to
the bottom, and click **Open Anyway**. Or skip the clicking:

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
| **↑ / ↓** | Move the selection |
| **⏎** | Paste the selected item |
| **⌘1**–**⌘9** | Paste the nth item directly |
| **⌫** | Delete the selected item |
| **⎋** | Dismiss |
| Right-click the menu bar icon | Clear History, Quit |
| Hover a row → **⋯** | Pin / Unpin / Delete |

Pinned items are lifted to their own section and are never evicted.

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

It does **not** help with Gatekeeper. Only notarization does that, and that needs
a paid Developer ID.

## Layout

```
Sources/ClipStackCore/   Model and history logic — no AppKit, so it's unit tested
Sources/ClipStack/       AppKit + SwiftUI: menu bar, monitor, hotkey, panel, paste
Tests/                   swift-testing (CLT ships no XCTest; see Scripts/test.sh)
```

## Not in v1

File/folder copies, search, configurable history size and hotkey, launch at login,
sync.
