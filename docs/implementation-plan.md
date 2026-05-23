# Prompt Paster Implementation Plan

## Implementation Strategy

Build the app in small vertical slices. The first useful slice should prove the
actual workflow:

```text
global trigger -> overlay -> choose prompt -> clipboard -> close overlay
```

Everything else should support that loop.

The recommended stack is:

- Swift 5.10 or newer.
- SwiftUI for views.
- AppKit for menu bar, overlay window, and global event integration.
- Native XCTest for unit tests.
- Manual macOS verification for global trigger and overlay behavior.

## Repository Setup

The repository currently has only a minimal `README.md`. The first app PR should
create a standard macOS app layout.

Recommended initial tree:

```text
PromptPaster.xcodeproj
PromptPaster/
  App/
    PromptPasterApp.swift
    AppDelegate.swift
  Models/
    Prompt.swift
    PromptLibrary.swift
  Services/
    ClipboardService.swift
    HotkeyController.swift
    PermissionService.swift
    PromptSearch.swift
    PromptStore.swift
    SettingsStore.swift
  Overlay/
    OverlayWindowController.swift
    PromptOverlayView.swift
    PromptCardView.swift
  Settings/
    SettingsView.swift
  Resources/
    SeedPrompts.json
PromptPasterTests/
  PromptStoreTests.swift
  PromptSearchTests.swift
  PromptLibraryValidationTests.swift
docs/
  design-architecture-spec.md
  implementation-plan.md
```

If the project starts as a Swift Package instead of an Xcode project, keep the
same conceptual module boundaries under `Sources/PromptPaster`.

## Milestone 1: Native App Shell

Goal: create a runnable menu-bar utility with no business logic.

Tasks:

- Create the macOS app project.
- Add `PromptPasterApp`.
- Add an `AppDelegate` for AppKit lifecycle hooks.
- Set app activation policy to accessory.
- Add a menu bar icon through `NSStatusItem`.
- Add menu items:
  - Open Prompt Paster.
  - Settings.
  - Reload Library.
  - Quit.
- Add an empty SwiftUI settings window.
- Add a placeholder overlay panel that can be opened from the menu.

Validation:

- App launches.
- No Dock icon is shown by default.
- Menu bar item appears.
- Quit works.
- Placeholder overlay opens from the menu.

Risks:

- Accessory apps can be awkward while debugging. Keep a temporary debug command
  or scheme setting to show the Dock icon if needed.

## Milestone 2: Prompt Library Storage

Goal: load, validate, and expose prompts from a local JSON file.

Tasks:

- Define `Prompt`.
- Define `PromptLibrary`.
- Add JSON decoding and encoding.
- Add prompt validation:
  - required `id`
  - required `title`
  - required `body`
  - unique IDs
  - optional shortcut uniqueness warning
- Add `PromptStore`.
- Create Application Support directory:

```text
~/Library/Application Support/Prompt Paster/
```

- Copy bundled `SeedPrompts.json` to `prompts.json` on first launch.
- Add "Open Prompt Library" action.
- Add "Reload Library" action.
- Add errors for invalid JSON and validation failures.

Validation:

- Unit test decoding a valid library.
- Unit test rejecting invalid JSON.
- Unit test detecting duplicate IDs.
- Unit test creating the default library when missing.
- Manual test editing and reloading the file.

Implementation notes:

- Keep unknown JSON fields tolerated by default.
- Keep the last valid in-memory prompt set if reload fails.
- Avoid silently overwriting user edits after first launch.

## Milestone 3: Search and Ranking

Goal: make prompt lookup fast and predictable.

Tasks:

- Implement `PromptSearch`.
- Search across title, category, tags, and body.
- Rank matches:
  1. exact title prefix
  2. title substring
  3. category/tag match
  4. body substring
- Add simple normalization:
  - lowercase
  - trim whitespace
  - collapse repeated spaces
- Add tests for common ranking cases.

Validation:

- Searching `merge` surfaces merge-related prompts above body-only matches.
- Searching `handoff` surfaces handoff prompts.
- Empty query returns prompts in configured order.

Future option:

- Add fuzzy matching after exact ranking behavior feels stable.

## Milestone 4: Overlay Window

Goal: create the real overlay shell.

Tasks:

- Implement `OverlayWindowController`.
- Use `NSPanel` or `NSWindow` hosted by AppKit.
- Size to 80 percent of the active display.
- Center on the active display.
- Use rounded corners and a subtle shadow.
- Host `PromptOverlayView` in `NSHostingView`.
- Focus the search field on open.
- Close on `Escape`.
- Close on outside click if practical in v1.
- Restore focus to the previous app as cleanly as possible.

Validation:

- Overlay opens on the display where the user is working.
- Overlay appears above normal windows.
- Overlay captures typing.
- `Escape` closes it.
- Reopening does not create duplicate windows.

Implementation notes:

- Window behavior will need real macOS testing, not just unit tests.
- Prefer a reusable singleton-style controller owned by the app lifecycle.
- Avoid creating a new panel on every trigger.

## Milestone 5: Overlay UI

Goal: make the overlay usable for real prompt selection.

Tasks:

- Build `PromptOverlayView`.
- Add search field.
- Add category chips.
- Add prompt result grid or dense list.
- Build `PromptCardView`.
- Show title, category, preview, tags, and shortcut badge.
- Add selected state.
- Add empty search state.
- Add invalid-library warning state.
- Add copied confirmation state if desired.

Validation:

- Prompt titles and previews are readable at 80 percent screen size.
- Long prompts do not break card layout.
- Filtering does not cause jarring layout jumps.
- Empty results are clear.

Design defaults:

- Keep the UI dense.
- Avoid large hero-style typography.
- Avoid decorative gradients or illustration.
- Use native vibrancy or a restrained solid surface.
- Keep cards small enough to scan quickly.

## Milestone 6: Clipboard Selection Loop

Goal: make selecting a prompt copy it and close the overlay.

Tasks:

- Implement `ClipboardService`.
- Add `copyPlainText(_:)`.
- Wire prompt click to clipboard copy.
- Wire selected prompt `Enter` to clipboard copy.
- Wire numeric shortcuts `1` through `9` to visible results.
- Close overlay after successful copy.
- Keep overlay open and show error if clipboard write fails.

Validation:

- Selecting by pointer copies the expected prompt.
- Selecting by keyboard copies the expected prompt.
- Clipboard contains only the prompt body.
- Overlay closes after success.
- `Escape` does not alter clipboard content.

Manual test:

1. Open TextEdit or a browser chat box.
2. Open Prompt Paster overlay.
3. Choose a prompt.
4. Press `Command+V`.
5. Confirm the selected prompt appears.

## Milestone 7: Global Trigger

Goal: open the overlay from anywhere.

Tasks:

- Implement fallback hotkey first, ideally `Control+Option+Space`.
- Add double-`Control` detector after the fallback works.
- Observe modifier key transitions.
- Track two `Control` taps inside a threshold, for example 350 ms.
- Add debounce so a third tap does not immediately reopen after close.
- Add settings for trigger mode and threshold.
- Add permission checks for Accessibility.
- Add a settings action to open Privacy and Security settings.

Validation:

- Fallback hotkey opens overlay globally.
- Double-`Control` opens overlay globally after permission is granted.
- Trigger hides overlay if it is already visible.
- Trigger does not fire while holding `Control` as part of another chord.
- Missing permission produces a clear settings warning.

Implementation notes:

- Modifier-only global gestures are more fragile than standard chords.
- Keep the fallback hotkey available permanently.
- If double-`Control` proves unreliable, ship fallback chord first and keep the
  modifier gesture behind an experimental setting.

## Milestone 8: Settings and Preferences

Goal: make the app configurable enough for daily use.

Tasks:

- Add `SettingsStore` backed by `UserDefaults`.
- Add settings for:
  - trigger mode
  - double-tap threshold
  - fallback hotkey display
  - launch at login
  - overlay density
  - prompt library path
  - copied confirmation
- Add "Open Prompt Library".
- Add "Reveal Prompt Library in Finder".
- Add "Reload Library".
- Add "Reset Seed Library" with confirmation.

Validation:

- Settings persist across app relaunch.
- Reload library works from settings and menu bar.
- Launch-at-login toggle updates the system login item state.
- Reset seed library never overwrites without confirmation.

## Milestone 9: Seed Library Import

Goal: ship a useful prompt library from the user's original note.

Tasks:

- Convert the original note into `SeedPrompts.json`.
- Split long note sections into discrete prompt entries.
- Assign stable IDs.
- Assign categories.
- Add tags.
- Add short titles.
- Preserve prompt body text faithfully where useful.
- Fix obvious typos only if the prompt meaning is unchanged.

Validation:

- Seed JSON decodes.
- Seed prompts show in overlay.
- Categories are useful.
- Search terms like `ci`, `handoff`, `merge`, `review`, `wiki`, and `release`
  find the expected prompts.

Suggested seed prompt count:

- 20 to 35 prompts.

## Milestone 10: Packaging and Release

Goal: produce an installable app artifact.

Current `PACKAGING-1` scope uses a DMG as the first installable artifact. This
matches the normal macOS drag-to-Applications release flow and keeps local
validation independent of Apple Developer credentials. ZIP packaging remains a
later distribution option if release hosting needs it.

Tasks:

- Configure app icon.
- Configure bundle identifier.
- Add hardened runtime settings if signing.
- Decide signing and notarization path.
- Create a `.dmg` packaging script.
- Add install instructions to `README.md`.
- Add permission instructions.
- Add troubleshooting section.
- Keep signing and notarization optional for local validation.

Validation:

- Fresh install works on another macOS user account or machine.
- App can be moved to `/Applications`.
- Menu bar item appears after launch.
- First-run seed library is created.
- Global trigger works after permissions are granted.

## Testing Plan

Unit tests:

- Prompt JSON decoding.
- Prompt validation.
- Prompt search ranking.
- Settings defaults.
- Clipboard service can be tested through a protocol abstraction.

Manual tests:

- Menu bar lifecycle.
- Overlay placement.
- Keyboard focus.
- Clipboard copy.
- Global trigger.
- Accessibility permission flow.
- Launch at login.

Regression checklist before release:

- App launches cleanly.
- Menu bar item exists.
- Overlay opens from menu.
- Overlay opens from global trigger.
- Search works.
- Pointer selection copies and closes.
- Keyboard selection copies and closes.
- `Escape` closes without copying.
- Invalid JSON shows an error and does not crash.
- Reload after fixing JSON works.
- Quit exits the process.

## Open Technical Questions

### Xcode Project vs Swift Package

An Xcode project is the most straightforward path for a macOS app with signing,
entitlements, assets, and packaging.

A Swift Package can keep the codebase cleaner and make core logic easier to
test, but the app target still needs Xcode project configuration.

Recommended approach:

- Use an Xcode app project.
- Keep core services and models clean enough to move into a package later.

### Hotkey Dependency

Options:

- Write the fallback hotkey and modifier detector directly using AppKit/Core
  Graphics APIs.
- Use a small maintained Swift hotkey package for chord registration and keep
  double-`Control` custom.

Recommended approach:

- Minimize dependencies for v1.
- Add a dependency only if direct global hotkey registration becomes noisy.

### Auto-Paste

Auto-paste is tempting, but should not be part of v1.

Reasons:

- It requires sending synthetic key events.
- It depends on the correct target still being focused.
- It increases permission burden.
- It can paste into the wrong app if focus changes.

Recommended approach:

- Copy only in v1.
- Consider opt-in auto-paste later with clear warnings.

## Suggested PR Sequence

1. `DOCS-SPEC-1`: Add design, architecture, and implementation docs.
2. `APP-SHELL-1`: Add native macOS menu-bar app shell.
3. `PROMPTS-1`: Add prompt library storage and seed JSON.
4. `OVERLAY-1`: Add overlay UI and search.
5. `CLIPBOARD-1`: Add copy-and-close selection loop.
6. `HOTKEY-1`: Add fallback global hotkey.
7. `HOTKEY-2`: Add double-control trigger and permission flow.
8. `SETTINGS-1`: Add settings and launch-at-login controls.
9. `PACKAGING-1`: Add installable app packaging.

## Post-Sequence Routing

The planned v1 implementation sequence is complete after `PACKAGING-1`.
Additional PRs should come from fresh release QA, user feedback, or a new
planning pass rather than continuing this initial sequence by default.

## Post-v1 Feedback Roadmap

This roadmap captures manual QA feedback after the first usable release build.
Keep these as small reviewable slices; do not combine layout, shortcut
semantics, ordering, and editing into one large PR.

### `UI-QA-1`: Make menu-bar icon reliably visible

Goal: make Prompt Paster discoverable as a menu-bar utility.

Tasks:

- Replace or adjust the current status-item symbol so the menu-bar icon is
  clearly visible in common light and dark menu bars.
- Keep it template-safe for macOS menu-bar rendering.
- Preserve status-item menu actions.
- Add a fallback title or tooltip if it improves discoverability without adding
  visible clutter.

Validation:

- Installed app shows a visible menu-bar icon.
- Icon remains visible in dark and light mode.
- Menu opens from the icon.
- Fallback hotkey and double-Control still open the overlay.

### `PREFS-2`: Add overlay display preferences

Goal: make overlay sizing and prompt preview density user-configurable.

Tasks:

- Add overlay size settings:
  - percentage of active display
  - optional fixed pixel width/height mode if practical
- Add configurable maximum prompt preview characters.
- Persist settings in `SettingsStore`.
- Apply settings when opening the overlay.
- Keep safe minimum and maximum bounds so the overlay cannot become unusable.

Validation:

- Settings persist across relaunch.
- Overlay opens at the configured size.
- Preview text length changes without breaking row/card layout.
- Invalid or old preference values clamp to safe defaults.

### `LAYOUT-1`: Replace full-width rows with smart prompt cards

Goal: improve scanning by using variable-sized rectangular cards rather than
full-width rows.

Tasks:

- Introduce a card/grid layout that adapts to overlay size and content.
- Size cards based on prompt metadata and preview length while preserving a
  stable, predictable scan order.
- Keep category chips, search, selected state, empty/error states, and copy
  behavior.
- Avoid layout jumps while typing.
- Preserve keyboard navigation and visible shortcut badges.

Validation:

- Cards fit without overlapping at small and large overlay sizes.
- Long titles, tags, and previews remain readable.
- Search filtering does not produce jarring reshuffles beyond the expected
  result-set change.
- Pointer and keyboard selection still copy and close.

### `SHORTCUTS-1`: Add spatial letter shortcut assignment

Goal: make selection shortcuts faster than number keys by default.

Tasks:

- Default visible prompt shortcuts to center-keyboard letters.
- Assign letters roughly by card position and keyboard geography:
  - center/right cards prefer keys such as `j` and `k`
  - center/top cards prefer keys such as `t` and `y`
  - nearby cards should get nearby keys where practical
- Add a Settings option to switch shortcut badges back to numeric `1`-`9`.
- Keep shortcut assignment deterministic for a given visible layout.
- Avoid stealing normal text input while the search field is active except for
  deliberate shortcut handling.

Validation:

- Visible badges match the keys that select prompts.
- Shortcut mapping tracks card position predictably.
- Numeric mode restores current `1`-`9` behavior.
- Search typing still works normally.

### `ORDERING-1`: Add configurable ordering and usage ranking

Goal: let users control prompt order globally and per category, with optional
frequency-based ranking.

Tasks:

- Add local usage statistics keyed by prompt ID:
  - copy count
  - last copied timestamp
- Add configurable global ordering.
- Add configurable per-category ordering.
- Add an option to sort by use frequency by default.
- Define how manual ordering, search relevance, category filtering, and usage
  ranking interact.
- Keep usage stats local and out of the seed prompt file unless explicitly
  exported later.

Implementation decision:

- `prompts.json` order remains the library/default order.
- Search and category filters narrow the visible prompt set first.
- For non-empty searches, search relevance sorts first:
  - title prefix
  - title substring
  - category/tag match
  - body substring
- The selected ordering mode then sorts within the filtered/relevance group.
- Category-specific ordering overrides the global ordering mode when a category
  chip is selected.
- Frequency order uses copy count descending, then last copied timestamp
  descending, then library order.
- Recently used order uses last copied timestamp descending, then copy count
  descending, then library order.
- Usage stats persist locally by prompt ID in user defaults through
  `PromptUsageStore`, are updated only after a successful clipboard copy, and
  are pruned for prompt IDs no longer present in the loaded library.

Validation:

- Copying prompts updates local usage stats.
- Frequency sort changes ordering predictably.
- Manual order remains stable when frequency sorting is disabled.
- Search ranking remains understandable when usage sorting is enabled.

### `LIBRARY-UI-1`: Add prompt library manager

Goal: provide a proper UI for viewing, searching, and editing the prompt
library instead of requiring JSON edits.

Tasks:

- Add a library manager window.
- List prompts with search and category/tag filtering.
- Allow editing:
  - title
  - body
  - category
  - tags
  - ordering metadata if introduced by `ORDERING-1`
- Validate before saving and show recoverable errors.
- Preserve JSON compatibility with existing `prompts.json`.
- Keep direct file open/reload actions available for advanced users.

Validation:

- Edits persist to the prompt library file.
- Invalid edits are blocked with clear errors.
- Reload keeps the last valid library when saved JSON is invalid.
- Overlay reflects saved library changes after reload.

## Post-v1 Suggested PR Sequence

1. `ROADMAP-1`: Add post-v1 feedback roadmap.
2. `UI-QA-1`: Make menu-bar icon reliably visible.
3. `PREFS-2`: Add overlay display preferences.
4. `LAYOUT-1`: Replace full-width rows with smart prompt cards.
5. `SHORTCUTS-1`: Add spatial letter shortcut assignment.
6. `ORDERING-1`: Add configurable ordering and usage ranking.
7. `LIBRARY-UI-1`: Add prompt library manager.

## Release Automation Follow-Up

### `RELEASE-1`: Add GitHub Actions DMG release publishing

Goal: make GitHub the source of release artifacts by building the DMG on a
GitHub-hosted macOS runner and publishing it on a GitHub Release.

Tasks:

- Add a release workflow triggered by manual dispatch and `v*` tags.
- Run the validation suite before publishing:
  - `swift build`
  - `swift test`
  - `plutil -lint Packaging/Info.plist`
  - `git diff --check`
- Build the release DMG through `scripts/build-dmg.sh`; unsigned alpha builds
  must ad-hoc sign the final `.app` bundle so macOS does not inherit a stale
  linker signature and report the app as damaged after browser download.
- Validate the DMG, including app bundle code-signature verification and launch
  smoke, through `scripts/validate-release-package.sh`.
- Upload the DMG as a workflow artifact.
- Create or update the GitHub Release and attach the DMG.
- Download the published stable `PromptPaster.dmg` release asset and run the
  same validator on that downloaded artifact before the workflow succeeds.
- Support optional Developer ID signing and notarization through GitHub Actions
  secrets without requiring those secrets for unsigned alpha releases.

Required secrets for signed/notarized releases:

- `APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`
- `APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`
- `CODESIGN_IDENTITY`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APP_SPECIFIC_PASSWORD`

Validation:

- Manual workflow dispatch can publish `v1alpha`.
- The release page contains the generated DMG.
- Unsigned alpha releases work without Apple secrets and pass bundle-signature
  validation from the mounted DMG.
- Notarized releases fail before building when required Apple secrets are
  missing.

### `SITE-1`: Move repo and publish GitHub Pages minisite

Goal: give Prompt Paster a small public product page with a direct download
link that downloads the latest DMG without sending users through the GitHub
release page.

Tasks:

- Transfer the repository from `shaypal5/prompt-paster` to
  `prompt-paster/prompt-paster`.
- Publish a one-page GitHub Pages site from `docs/index.html`.
- Add a primary download link to:
  `https://github.com/prompt-paster/prompt-paster/releases/latest/download/PromptPaster.dmg`.
- Update the release workflow to upload a stable `PromptPaster.dmg` asset
  alongside the versioned DMG artifact.
- Keep source, release notes, install requirements, and signing status visible
  but secondary to the direct download action.

Validation:

- `swift test`
- `scripts/build-dmg.sh`
- `scripts/validate-release-package.sh dist/PromptPaster-0.1.0.dmg --launch-smoke`
- GitHub Pages is enabled for `main` / `docs`.
- `PromptPaster.dmg` is present on the latest release and the website download
  URL resolves directly to the DMG. Because GitHub excludes prereleases from
  `/releases/latest/download/...`, website-facing alpha releases are published
  with `prerelease=false`.
