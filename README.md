# ClickLocker

Windows' **ClickLock** for macOS. Hold the mouse button down briefly and let go: the button
stays pressed as far as the system is concerned. Select text or drag things without keeping the
button held, then click once to release. Works with a mouse and with the trackpad.

ClickLocker is a background app — a menu bar icon, no Dock icon, no window in the way.

A white ring around the pointer shows what is going on: it fills up as a progress arc while you
hold the button, and closes into a full ring once the button is locked.

## Requirements

- macOS 14 or later
- Xcode or the Xcode command line tools (for `swift build`)

## Install

There is no prebuilt download. The app is signed ad hoc, and Gatekeeper refuses ad hoc signed
apps that arrive over the internet, so building it yourself is the honest path:

```bash
git clone https://github.com/joelintveld/clicklocker.git
cd clicklocker
./Scripts/bundle.sh --install --run
```

That builds `build/ClickLocker.app`, copies it to `/Applications` and launches it. Leave out
`--install` to keep it inside the project folder — but note that "Open at login" and the
Accessibility permission both work best from a path that does not move.

## First run: the Accessibility permission

ClickLocker has to alter mouse events, and macOS only allows that with the **Accessibility**
permission. Pick **Grant Accessibility permission…** from the menu bar icon, or open System
Settings → Privacy & Security → Accessibility yourself and switch ClickLocker on. Then turn on
**Enable click lock** in the same menu.

Because the app is signed ad hoc, its code hash changes on every rebuild, and macOS ties the
permission to that hash. If the lock stops working after a rebuild, remove ClickLocker from the
Accessibility list with **–** and add it again.

## Settings

Open them from the menu bar icon.

- **Short ↔ Long** — how long the button must be held before it locks. 200 to 2200 ms, 1000 ms by
  default. The practice pad below the slider shows a filling bar while you press and reports how
  long your last press actually was, in milliseconds.
- **Open at login** — registers ClickLocker as a login item through `SMAppService`. macOS may ask
  you to approve it under General → Login Items.
- **Show a ring around the pointer** — on by default. Turn it off for the lock without any visual
  indicator.
- **Lock the right mouse button as well** — off by default; Windows only locks the primary button.
- **Don't lock if the mouse moves while holding** — off by default. Turning it on stops a slow
  ordinary drag from locking by accident.
- **Escape releases a lock** — off by default. Turning it on routes key presses past the app; it
  only ever examines Escape, passes everything else through untouched, and stores nothing.
- **Release the lock automatically** — off by default; lets go after a number of seconds.

With every option off the behaviour is exactly that of Windows: only the hold duration counts.

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

## Limitations

- Apps that read the button state directly (`NSEvent.pressedMouseButtons`) instead of following
  drag events do not notice the lock.
- No event tap sees anything inside secure input contexts (password fields, the login window).
- Mission Control, switching Spaces and menu bar interactions can drop an active lock.

## Layout

```
Sources/ClickLocker/
  ClickLockerApp.swift           app entry point, menu bar and settings scenes
  ClickLockEngine.swift          event tap and state machine
  CursorOverlay.swift            the ring around the pointer
  LaunchAtLogin.swift            login item registration
  AppModel.swift                 ties settings, permission, engine and ring together
  Preferences.swift              settings in UserDefaults
  AccessibilityPermission.swift  permission check
  MenuBarView.swift              menu bar menu
  SettingsView.swift             settings window
  TestPadView.swift              practice pad with live status
Resources/Info.plist             bundle metadata (LSUIElement)
Scripts/bundle.sh                build, bundle, sign ad hoc, install
```

## Contributing

Issues and pull requests are welcome. `swift build` has to stay warning free, and please keep the
existing style: comments explain *why*, not *what*.

## License

Copyright (C) 2026 Joël in 't Veld

ClickLocker is free software: you can redistribute it and/or modify it under the terms of the GNU
General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. It is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the [LICENSE](LICENSE) file for the full text.
