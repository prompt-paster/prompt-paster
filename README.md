# Prompt Paster

Prompt Paster is a native macOS utility for quickly selecting reusable coding
agent prompts from an overlay and copying them to the clipboard.

## Current Status

The repository currently contains a native menu-bar utility with the core v1
selection loop:

- a SwiftPM macOS executable target
- a menu-bar utility app with no Dock icon
- local prompt storage seeded into Application Support
- a searchable overlay with keyboard and pointer selection
- clipboard copy-and-close behavior
- fallback `Control+Option+Space` global hotkey
- double-Control trigger support
- settings and launch-at-login wiring
- local `.app` and DMG release packaging

Auto-paste is intentionally out of scope for v1. Selecting a prompt copies the
prompt body to the clipboard, then the user pastes into the target app.

## Run Locally

Requirements:

- macOS
- Xcode command line tools or Xcode
- Swift 6.0 or newer

Run the app from the repository root:

```bash
swift run PromptPaster
```

The app appears in the macOS menu bar. Use the menu-bar item, fallback hotkey,
or configured double-Control trigger to open the prompt overlay.

## Build an App Bundle

To build a local `.app` bundle:

```bash
scripts/build-app.sh
```

The script creates:

```text
dist/Prompt Paster.app
```

The bundle uses `LSUIElement`, so it behaves as a hidden menu-bar utility rather
than a normal Dock app.

The app icon is checked in at `Packaging/PromptPaster.icns`. To regenerate it
from the local vector drawing helper:

```bash
scripts/generate-app-icon.sh Packaging/PromptPaster.icns
```

## Build an Installable DMG

The first release packaging artifact is a DMG. That matches the normal macOS
drag-to-Applications install flow while keeping the local release path small and
repeatable. ZIP packaging can be added later if GitHub release distribution
needs it.

Build and validate the DMG:

```bash
scripts/build-dmg.sh
```

The script creates:

```text
dist/PromptPaster-0.1.0.dmg
```

The DMG contains:

```text
Prompt Paster.app
Applications -> /Applications
README.txt
```

To validate an existing artifact:

```bash
scripts/validate-release-package.sh dist/PromptPaster-0.1.0.dmg
```

To also launch the app from the mounted artifact and then terminate it:

```bash
scripts/validate-release-package.sh dist/PromptPaster-0.1.0.dmg --launch-smoke
```

## Signing and Notarization

Local validation does not require Apple Developer credentials. By default,
`scripts/build-dmg.sh` leaves the app unsigned and validates the generated DMG
structure.

For a signed release, provide a Developer ID Application identity:

```bash
CODESIGN_IDENTITY="Developer ID Application: Example Name (TEAMID)" scripts/build-dmg.sh
```

For notarization, also provide Apple account credentials and set `NOTARIZE=1`:

```bash
CODESIGN_IDENTITY="Developer ID Application: Example Name (TEAMID)" \
APPLE_ID="developer@example.com" \
APPLE_TEAM_ID="TEAMID" \
APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
NOTARIZE=1 \
scripts/build-dmg.sh
```

The signing path signs the app bundle with hardened runtime options, then signs
the generated DMG container before optional notarization. The app signing step
uses `Packaging/Entitlements.plist`. The entitlements file is intentionally
empty for now because Prompt Paster is a local clipboard/menu-bar app with no
sandbox, network, or Apple Events requirements.

When `NOTARIZE=1` is set, `CODESIGN_IDENTITY` is required and the script fails
before building if it is missing.

## Install and Permissions

1. Open the DMG.
2. Drag `Prompt Paster.app` to `Applications`.
3. Launch it from `Applications`.
4. If using double-Control, grant Accessibility permission when macOS prompts or
   from System Settings.

The fallback `Control+Option+Space` hotkey remains available. Launch-at-login
can be enabled from the app settings window.

## Planning Docs

- [Design, architecture, and spec](docs/design-architecture-spec.md)
- [Implementation plan](docs/implementation-plan.md)
- [Review recommendations](docs/review-recommendations.md)
