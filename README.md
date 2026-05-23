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

To also launch an installed-style copy of the app from the artifact and then
terminate it:

```bash
scripts/validate-release-package.sh dist/PromptPaster-0.1.0.dmg --launch-smoke
```

## Signing and Notarization

Local validation does not require Apple Developer credentials. By default,
`scripts/build-dmg.sh` applies an ad-hoc signature to the app bundle and
validates the generated DMG structure plus the app signature. Ad-hoc signed
builds are still unsigned alpha builds from Gatekeeper's perspective, but they
must not ship with a broken bundle signature that macOS reports as damaged.
The release validator also confirms the packaged app can find its bundled
SwiftPM resources after being copied out of the mounted DMG, matching the
normal drag-to-Applications install path.

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

The Developer ID signing path signs the app bundle with hardened runtime
options, then signs the generated DMG container before optional notarization.
The app signing step uses `Packaging/Entitlements.plist`. The entitlements file
is intentionally empty for now because Prompt Paster is a local
clipboard/menu-bar app with no sandbox, network, or Apple Events requirements.

When `NOTARIZE=1` is set, `CODESIGN_IDENTITY` is required and the script fails
before building if it is missing.

## GitHub Releases

The release workflow at `.github/workflows/release.yml` builds and validates the
DMG on a GitHub-hosted macOS runner, uploads the DMG as a workflow artifact, and
creates or updates a GitHub Release with the DMG attached.

The workflow uploads both a versioned artifact, such as
`PromptPaster-0.1.0.dmg`, and a stable `PromptPaster.dmg` alias. The stable
asset keeps the website download URL version-independent:

```text
https://github.com/prompt-paster/prompt-paster/releases/latest/download/PromptPaster.dmg
```

Manual alpha release:

```bash
gh workflow run release.yml \
  -f tag_name=v1alpha \
  -f prerelease=false \
  -f notarize=false
```

The website download button uses GitHub's `releases/latest/download` route.
GitHub excludes prereleases from that route, so public website-facing alpha
releases should be published with `prerelease=false` even when the tag name
contains `alpha`.

Tag releases also run automatically for tags matching `v*`.

Unsigned releases do not require repository secrets. Signed and notarized
releases require these GitHub Actions secrets:

```text
APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64
APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD
CODESIGN_IDENTITY
APPLE_ID
APPLE_TEAM_ID
APP_SPECIFIC_PASSWORD
```

`APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64` should contain a base64
encoded `.p12` Developer ID Application certificate. When the workflow's
`notarize` input is true, all signing and Apple account secrets are required and
the workflow fails before building if any are missing.

## Install and Permissions

1. Open the DMG.
2. Drag `Prompt Paster.app` to `Applications`.
3. Launch it from `Applications`.
4. If using double-Control, grant Accessibility permission when macOS prompts or
   from System Settings.

The fallback `Control+Option+Space` hotkey remains available. Launch-at-login
can be enabled from the app settings window.

## Planning Docs

- [Website](https://prompt-paster.github.io/prompt-paster/)
- [Design, architecture, and spec](docs/design-architecture-spec.md)
- [Implementation plan](docs/implementation-plan.md)
- [Review recommendations](docs/review-recommendations.md)
