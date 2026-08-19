# ClickLatch

Windows' **ClickLock** for macOS. Hold the mouse button down briefly and let go: the button
stays pressed as far as the system is concerned. Select text or drag things without keeping the
button held, then click once to release. Works with a mouse and with the trackpad.

ClickLatch is a background app — a menu bar icon, no Dock icon, no window in the way.

A white ring around the pointer shows what is going on: it fills up as a progress arc while you
hold the button, and closes into a full ring once the button is locked.

## Requirements

- macOS 14 or later
- To build it yourself: Xcode or the Xcode command line tools (for `swift build`)

## Install

Two ways in: download a ready-made build, or compile it yourself. The download is quicker; building
gives you an app signed with your own certificate, which the sections further down assume.

### Download a build

Grab `ClickLatch.zip` from the [latest release][releases], unzip it, and drag
`ClickLatch.app` into `/Applications`.

macOS will refuse to open it the first time. The build is signed, but with a self-signed
certificate rather than an Apple-issued one and without Apple's notarisation, so Gatekeeper treats
anything downloaded through a browser as suspect. This is expected, not a sign that something is
wrong — clear the quarantine flag once and it opens normally from then on:

```bash
xattr -dr com.apple.quarantine /Applications/ClickLatch.app
open /Applications/ClickLatch.app
```

If you would rather not touch Terminal: double-click the app, let macOS block it, then open System
Settings → Privacy & Security, scroll to the note about ClickLatch and click **Open Anyway**.

[releases]: https://github.com/joelvalentijn/clicklatch/releases/latest

### Build from source

```bash
git clone https://github.com/joelvalentijn/clicklatch.git
cd clicklatch
./Scripts/create-signing-certificate.sh
./Scripts/bundle.sh --install --run
```

The first script makes a self-signed code signing certificate, once. Skip it and everything still
builds and runs, but the signature is then ad hoc — which means its identity is the hash of that
one build, so **macOS drops the Accessibility permission on every rebuild** and the app cannot
update itself. With the certificate, the identity stays the same and both problems go away.

The second script builds `build/ClickLatch.app`, copies it to `/Applications` and launches it.
Leave out `--install` to keep it inside the project folder — but note that "Open at login" and the
Accessibility permission both work best from a path that does not move.

## First run: the Accessibility permission

ClickLatch has to alter mouse events, and macOS only allows that with the **Accessibility**
permission. Pick **Grant Accessibility permission…** from the menu bar icon, or open System
Settings → Privacy & Security → Accessibility yourself and switch ClickLatch on. Then turn on
**Enable ClickLatch** in the same menu.

macOS ties this permission to the app's code signature. A downloaded build, or one you built after
running the certificate script, keeps the same signature across updates, so the permission sticks.
An ad hoc build (the certificate script skipped) gets a new signature on every rebuild, and the
permission drops with it — if the lock stops working after a rebuild, remove ClickLatch from the
Accessibility list with **–** and add it again.

## Settings

Open them from the menu bar icon. They are split over four tabs.

**General**

- **Short ↔ Long** — how long the button must be held before it locks. 200 to 2200 ms, 1000 ms by
  default. The practice pad below the slider shows a filling bar while you press and reports how
  long your last press actually was, in milliseconds.
- **Open at login** — registers ClickLatch as a login item through `SMAppService`. macOS may ask
  you to approve it under General → Login Items.
- **Updates** — shows the running version, checks GitHub for a newer release once a day when
  switched on, and downloads and installs it on request.

Every setting that holds a value has a small ⟲ next to it that puts that one setting back to its
factory value, greyed out while it already is. **Restore Factory Settings** at the bottom of the
Advanced tab does the lot at once, leaving only the master switch and the login item as they are —
those say whether the app is running, which is not a matter of taste.

**Ring** — a live preview at the top shows every change straight away, mid-press on a dark
background and locked on a light one.

- **Show a ring around the pointer** — on by default. Turn it off for the lock without any visual
  indicator.
- **Colour**, **Thickness** (1–8 pt) and **Size** (radius 8–30 pt).
- **Dark outline and shadow** — on by default. It is what keeps a light ring readable on a light
  background; without it a white ring all but disappears on a white window.
- **Swell briefly when locking** — on by default. The line thickens to 1.7× and back over 220 ms
  at the moment the button locks, which is what makes the change register in the corner of your
  eye.
- **Delay** — how long you have to hold before the ring turns up at all, 0 to 500 ms. Raise it if
  ordinary clicks make it flash.
- **Fade** — how gently it fades in and out, 0 to 400 ms. At zero it simply appears.

**Sound**

- **Play a sound when locking and releasing** — on by default, with a **Volume** slider.
- Separate sounds for locking and releasing, picked from the sounds macOS itself offers, each with
  a preview button. Defaults are Tink and Pop.

**Advanced**

- **Lock the right mouse button as well** — off by default; Windows only locks the primary button.
- **Don't lock if the mouse moves while holding** — off by default. Turning it on stops a slow
  ordinary drag from locking by accident.
- **Escape releases a lock** — off by default. Turning it on routes key presses past the app; it
  only ever examines Escape, passes everything else through untouched, and stores nothing.
- **Release the lock automatically** — off by default; lets go after a number of seconds.

With every option on the Advanced tab off, the behaviour is exactly that of Windows: only the hold
duration counts.

## How it works

A `CGEventTap` at session level rewrites the mouse events:

| Situation | What the app does |
|---|---|
| Button released after ≥ the threshold | swallows the `mouseUp` — the button stays logically down |
| Pointer moves while locked | rewrites `mouseMoved` into `mouseDragged`, so apps see a drag |
| Next click | turns that `mouseDown` itself into the `mouseUp` that was held back |

Event handling runs on a dedicated thread with its own run loop, so a busy main thread cannot make
the tap time out. If macOS switches the tap off anyway, the app immediately switches it back on.

The pointer ring is a separate borderless, click-through window driven by a display link, so
drawing it never slows the event tap down.

When the app quits, gets switched off, or loses the permission, it always sends a final `mouseUp`.
A mouse button can never be left hanging.

## Updating itself

ClickLatch asks the GitHub releases API for the latest release, compares the tag with its own
version and, on request, downloads the archive and swaps itself out. A detached script waits for
the app to quit, moves the old bundle aside, puts the new one in place — restoring the old one if
that fails — and starts it again.

The one rule that makes this safe: an update is installed **only** when the downloaded bundle
satisfies the running app's designated requirement. Whoever manages to serve a different feed still
cannot get code onto the machine that was not signed with the same key. A consequence worth knowing
is that an ad hoc signed copy can never update itself: its requirement is the hash of that single
build, which no other build can match. The app says exactly that instead of installing something it
could not verify.

Downloads made by the app do not carry a quarantine flag, unlike ones made by a browser, so
Gatekeeper does not step in — which is why this works for a build Apple has never notarised.

That same rule has a consequence if you build ClickLatch yourself: your copy is signed with *your*
certificate, so it will refuse the official release, which carries a different one. Updating in
place works within your own builds; to move to an official release, build it from the new source or
replace the app by hand.

To publish a release: bump `CFBundleShortVersionString` in `Resources/Info.plist`, run
`./Scripts/make-release.sh`, and upload the resulting zip as an asset on a GitHub release whose tag
matches that version.

## Limitations

- Apps that read the button state directly (`NSEvent.pressedMouseButtons`) instead of following
  drag events do not notice the lock.
- No event tap sees anything inside secure input contexts (password fields, the login window).
- Mission Control, switching Spaces and menu bar interactions can drop an active lock.

## Layout

```
Sources/ClickLatch/
  ClickLatchApp.swift           app entry point, menu bar and settings scenes
  ClickLatchEngine.swift          event tap and state machine
  CursorOverlay.swift            the ring around the pointer, and how it is drawn
  ColorHex.swift                 colour ↔ hex conversion for stored settings
  SoundFeedback.swift            the lock and release sounds
  Updater.swift                  checking, downloading, verifying and swapping
  LaunchAtLogin.swift            login item registration
  AppModel.swift                 ties settings, permission, engine and ring together
  Preferences.swift              settings in UserDefaults
  AccessibilityPermission.swift  permission check
  MenuBarView.swift              menu bar menu
  SettingsView.swift             settings window
  TestPadView.swift              practice pad with live status
Resources/Info.plist             bundle metadata (LSUIElement)
Resources/AppIcon.icns           the app icon, generated by the script below
Scripts/create-signing-certificate.sh   one-off self-signed identity
Scripts/bundle.sh                build, bundle, sign, install
Scripts/make-release.sh          archive a build for a GitHub release
Scripts/make-icon.swift          draws the icon and writes the .icns
```

The icon is drawn in code rather than kept as an opaque image, so it can be read and changed like
anything else here. Run `swift Scripts/make-icon.swift` after editing it. Below 24 pt the arrow is
left out and the ring is drawn heavier: at 16 pt the two shapes together are barely a dozen pixels
and turn into a smudge.

## Contributing

Issues and pull requests are welcome. `swift build` has to stay warning free, and please keep the
existing style: comments explain *why*, not *what*.

## License

Copyright (C) 2026 Joël in 't Veld

ClickLatch is free software: you can redistribute it and/or modify it under the terms of the GNU
General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. It is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the [LICENSE](LICENSE) file for the full text.
