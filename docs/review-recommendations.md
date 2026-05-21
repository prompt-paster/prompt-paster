# PR Review Recommendations

This document records the self-review findings for `APP-SHELL-1` and the
recommended fixes applied to the branch.

## Overlay Focus Restoration

Finding: the overlay activated Prompt Paster with `NSApp.activate` but only hid
the panel on close. That made the core copy-then-`Command+V` workflow fragile,
because the previously active app might no longer be focused.

Recommendation: capture the frontmost application before showing the overlay and
reactivate it when the overlay closes. This keeps the current activating overlay
model usable for keyboard input while preserving the expected return-to-workflow
behavior.

Applied fix: `OverlayWindowController` stores
`NSWorkspace.shared.frontmostApplication` before opening the panel and activates
that app in `hide()`.

## Key-Capable Borderless Overlay Panel

Finding: the overlay was a borderless `NSPanel`, but it did not explicitly allow
itself to become key or main. That is risky because the next slices depend on
keyboard search, `Escape`, arrows, and prompt shortcut keys.

Recommendation: use a small `NSPanel` subclass that overrides `canBecomeKey` and
`canBecomeMain`.

Applied fix: added `OverlayPanel` and used it for the overlay window.

## Active Screen Selection

Finding: the overlay used `NSScreen.main`, which is not always the display the
user is working on in a multi-monitor setup.

Recommendation: choose the screen containing the mouse pointer as the shell-level
proxy for active display. This is simple and better aligned with the command
palette interaction model.

Applied fix: added `screenContainingMouse()` and use it before falling back to
`NSScreen.main`.

## Installable App Shell

Finding: the PR only produced a raw SwiftPM executable via `swift run`, not a
`.app` bundle. That left the app shell short of the product requirement to be
installed and hidden as a macOS utility.

Recommendation: keep SwiftPM for development, but add an app bundle packaging
path now with an `Info.plist` that declares app identity and `LSUIElement`.

Applied fix: added `Packaging/Info.plist` and `scripts/build-app.sh`, which
builds `dist/Prompt Paster.app`.
