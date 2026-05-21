# Prompt Paster Design, Architecture, and Spec

## Purpose

Prompt Paster is a small macOS utility for people who repeatedly paste long,
structured prompts into coding agents and other chat tools.

The app should stay out of the way during normal work. When the user presses a
global trigger, a large overlay appears over the current screen, lets the user
pick a prompt with the keyboard or pointer, copies that prompt to the clipboard,
and disappears immediately so the user can paste into the active app.

The core workflow is:

1. Keep Prompt Paster running in the background.
2. Press the global trigger, for example double-tap `Control`.
3. Search or choose a prompt from the overlay.
4. The selected prompt is copied to the clipboard.
5. The overlay closes.
6. The user presses `Command+V` in the current agent/chat window.

The app should optimize for speed, reliability, low cognitive overhead, and
plain-file portability of the prompt library.

## Non-Goals for the First Version

Prompt Paster v1 should not try to be a full text-expansion platform, team
knowledge base, or automation runner.

Out of scope for v1:

- Automatic pasting into the active app.
- Cloud sync.
- Rich text prompts.
- Prompt execution.
- Prompt variables with modal input.
- Multi-user libraries.
- Web app or browser extension surfaces.
- AI-generated prompt suggestions.
- Complex nested folders or permission systems.

These can be added later if the base selection-and-copy loop proves useful.

## Target User

The primary user is a power user who works across many AI coding agents,
repositories, and browser or desktop chat surfaces. They maintain a library of
reusable prompts for recurring workflows such as:

- CI readiness checks.
- PR review and merge loops.
- Handoff prompts for new agent threads.
- Wiki contribution instructions.
- Delegation and feedback intake workflows.
- Repository bootstrap instructions.
- Release and tagging workflows.

The user needs the prompt library to be visible quickly, searchable, and usable
without switching away to Notes or another document editor.

## Platform Choice

Build Prompt Paster as a native macOS app using Swift, SwiftUI, and AppKit.

Reasons:

- Native access to `NSPasteboard` for clipboard writes.
- Native floating overlay behavior through `NSPanel` or `NSWindow`.
- Native menu bar integration through `NSStatusItem`.
- Native launch-at-login support.
- Global keyboard observation through macOS event APIs.
- Lower idle resource usage than Electron.
- Better fit for a utility that should feel like part of the operating system.

SwiftUI should be used for the overlay, prompt list, settings, and editor UI.
AppKit should be used where SwiftUI does not expose the needed windowing or
event behavior directly.

## App Surfaces

### Menu Bar App

Prompt Paster should appear as a menu bar utility. It should not show a Dock
icon by default.

The menu bar item should expose:

- Open Prompt Paster.
- Edit Prompt Library.
- Settings.
- Reload Library.
- About Prompt Paster.
- Quit.

The app should use accessory activation policy so it behaves like a background
utility:

```swift
NSApp.setActivationPolicy(.accessory)
```

If future editing screens need a more normal app-window experience, the app can
temporarily activate itself when opening settings or the editor.

### Overlay

The overlay is the main product surface.

Behavior:

- Opens on the active display.
- Appears centered over the current workspace.
- Uses about 80 percent of the active screen width and height.
- Floats above normal app windows.
- Captures keyboard input while visible.
- Closes on `Escape`, outside click, or prompt selection.
- Does not permanently change the active app after closing.

Recommended window implementation:

- Use `NSPanel` for the overlay controller.
- Use a borderless or title-hidden window style.
- Set level to `.floating` or a similar level that appears above standard app
  windows but does not behave like an alert.
- Use `isReleasedWhenClosed = false` so the panel can be reused.
- Use a SwiftUI root view hosted in `NSHostingView`.

The overlay should be visually calm and dense. It should feel closer to
Spotlight, Raycast, or a command palette than a landing page.

### Settings Window

Settings should initially cover:

- Global trigger choice.
- Double-`Control` timing threshold.
- Fallback hotkey.
- Launch at login.
- Prompt library file location.
- Open prompt library in default editor.
- Reload library.
- Appearance density.
- Whether to show a brief copied confirmation.

Settings can be a normal SwiftUI window.

### Prompt Editor

The first version can avoid a full built-in editor. A good v1 option is:

- Store prompts in a plain JSON file.
- Provide an "Open Prompt Library" menu item.
- Provide a "Reload Library" menu item.
- Validate and show errors if the file cannot be parsed.

A lightweight built-in editor can come later once the storage model is stable.

## Overlay Information Architecture

The overlay should have three zones.

### Header

The header contains:

- Search input, focused automatically.
- Current category filter, if any.
- Settings icon.
- Optional result count.

The search input should be the primary focus target. Typing should filter
prompts immediately.

### Navigation Area

For v1, use either a compact left sidebar or horizontal category chips.

Recommended v1 choice:

- Horizontal chips below the search field.
- Include `All`, `PR`, `Review`, `Handoff`, `Delegation`, `Docs`, `Release`,
  and `System`.

This avoids committing to a heavy folder model too early.

### Prompt Results

Results can be displayed in a grid or dense list. The app should support both
later, but v1 can choose a dense grid because keyboard badges fit well on cards.

Each prompt card should show:

- Prompt title.
- Category.
- One to three line preview.
- Optional tags.
- A keyboard badge in the top-right corner.

Cards should have stable height so filtering and hover states do not cause
layout jumps.

The keyboard badge is assigned to the currently visible results. The first
visible prompts can receive:

```text
1 2 3 4 5 6 7 8 9 A S D F G H J K L
```

The app should avoid badges that conflict with common editing keys while the
search field is active. A practical rule:

- If the search field is empty, number and letter badges select immediately.
- If the search field has focus and contains text, numbers still select, while
  letters continue typing.
- `Command+<badge>` or `Option+<badge>` can always select later if needed.

For v1, the simplest reliable behavior is:

- Numeric badges `1` through `9` select visible prompts.
- Arrow keys move selection.
- `Enter` copies selected prompt.
- Letter badges can be displayed later once key conflict behavior is settled.

## Keyboard Interaction

Global:

- Double-tap `Control`: show or hide overlay.
- Fallback configurable hotkey: default `Control+Option+Space`.

Overlay:

- `Escape`: close.
- Typing: filter prompts.
- `Up` / `Down`: move selection in list mode.
- `Left` / `Right`: move selection in grid mode.
- `Enter`: copy selected prompt and close.
- `1` through `9`: copy visible prompt at that index and close.
- `Command+,`: open settings.

Future:

- `Command+K`: focus search.
- `Command+R`: reload prompt library.
- `Command+E`: open selected prompt in editor.
- `Option+Enter`: copy without closing.

## Pointer Interaction

- Click a prompt card to copy it and close the overlay.
- Hover a card to emphasize it.
- Long prompts can show a preview popover or use a detail pane in a later
  version.
- Clicking outside the overlay closes it.

## Clipboard Behavior

When a prompt is selected:

1. Clear the general pasteboard.
2. Write the prompt body as plain text.
3. Close the overlay.
4. Optionally show a very small copied confirmation.

Use `NSPasteboard.general`.

The app should write plain text only in v1. Markdown remains plain text.

The app should not auto-paste by default. Auto-paste would require Accessibility
permission and could send keystrokes to the wrong target. Keeping v1 to copying
is safer and predictable.

## Permissions

### Accessibility

Double-tap modifier detection is the main permission-sensitive area.

Standard hotkey APIs handle key chords well, but modifier-only gestures like
double-tapping `Control` usually require observing low-level keyboard events,
especially `flagsChanged` events.

Prompt Paster should:

- Detect whether Accessibility permission is available.
- Explain why the permission is needed.
- Offer a button that opens the correct System Settings pane.
- Provide the fallback hotkey when permission is missing.

### Clipboard

Writing to the clipboard through `NSPasteboard` does not require a special user
permission prompt.

### Login Item

Launch at login should use Apple's modern login item APIs and be opt-in.

## Hotkey and Trigger Design

The preferred trigger is double-tap `Control`.

Detection model:

- Listen for keyboard modifier state changes.
- Track `Control` key down/up transitions.
- Count two completed taps inside a configurable threshold, for example 350 ms.
- Ignore taps while another modifier is held, unless explicitly configured.
- Reset state when the threshold expires or a non-control key interrupts.

Fallback trigger:

- `Control+Option+Space`.
- Implement through a reliable hotkey registration package or AppKit-compatible
  event monitor.

The settings UI should allow the user to choose between:

- Double-tap `Control`.
- Double-tap `Option`.
- Fixed hotkey chord.

V1 can ship with double-`Control` plus fallback chord only.

## Prompt Library Format

Use JSON for v1 because it is easy to validate, easy to edit, and easy to evolve.

Default path:

```text
~/Library/Application Support/Prompt Paster/prompts.json
```

Schema:

```json
{
  "version": 1,
  "prompts": [
    {
      "id": "wait-ci-ready-merge",
      "title": "Wait CI + Merge Check",
      "category": "PR",
      "body": "Wait till ci is done then report...",
      "shortcut": "1",
      "tags": ["ci", "merge", "review"],
      "updatedAt": "2026-05-21T00:00:00Z"
    }
  ]
}
```

Field rules:

- `version`: required integer.
- `prompts`: required array.
- `id`: required stable slug, unique.
- `title`: required short display name.
- `category`: optional string.
- `body`: required prompt text.
- `shortcut`: optional preferred badge.
- `tags`: optional array of strings.
- `updatedAt`: optional ISO-8601 timestamp.

The app should tolerate unknown fields so the format can evolve without breaking
older versions.

## Seed Prompt Set

The user's existing note can be converted into an initial bundled prompt library.
The seed set should include short, recognizable titles rather than using the
entire prompt body as the title.

Suggested initial categories:

- `PR`
- `Review`
- `Handoff`
- `Delegation`
- `Feedback`
- `Docs`
- `Release`
- `Bootstrap`
- `System`

Suggested seed prompts:

- Wait CI + Merge Check.
- PR Ready Review + Squash Merge.
- Run Yourself + Recommend Next Steps.
- New Agent Handoff.
- Adanim Knowledge Wiki Contribution.
- General Go-Waiting Handoff.
- Squash Merge + Next Plan.
- Self Review.
- Manual PR Review Handling.
- Delegation Setup.
- Feedback Intake.
- Agents Directory Bootstrap.
- Tech Wiki Intro.
- Planning + PR Notation.
- Semi-Auto PR Loop.
- Hands-Off PR Loop.
- PR Labeling.
- Bootstrap PR Labeling.
- Open PR.
- Release PR.
- Release Tag.
- Add pr-agent-context.
- Init Agent Files In Repo.
- Next On Plan.
- Merge Clean Back To Main.
- Self Review Research.
- HeOCR Wiki Contribution.
- Screen Capture Hygiene.

## Search

Search should work locally and synchronously for v1.

Search fields:

- title
- category
- tags
- body

Ranking:

1. Exact title prefix.
2. Title substring.
3. Tag/category match.
4. Body substring.

The result list should update on each keystroke. For the expected prompt counts,
no search index is needed.

## Architecture Overview

Recommended module boundaries:

```text
PromptPasterApp
  App lifecycle, menu bar, settings scene

HotkeyController
  Global trigger registration and double-modifier detection

OverlayWindowController
  AppKit panel creation, positioning, show/hide lifecycle

PromptOverlayView
  SwiftUI overlay UI, search, categories, keyboard handling

PromptStore
  Load, validate, save, reload, and publish prompt library state

PromptSearch
  Filtering and ranking

ClipboardService
  Pasteboard write operations

SettingsStore
  User defaults and launch-at-login preferences

PermissionService
  Accessibility permission detection and settings deep-link
```

### Data Flow

```text
Global key event
  -> HotkeyController
  -> OverlayWindowController.show()
  -> PromptOverlayView focuses search
  -> User selects prompt
  -> ClipboardService.copy(prompt.body)
  -> OverlayWindowController.hide()
```

Prompt library flow:

```text
App launch
  -> PromptStore ensures Application Support directory
  -> If no library exists, copy bundled seed library
  -> Decode prompts.json
  -> Publish prompts to overlay

Reload Library
  -> PromptStore reloads file
  -> Validation result updates UI
```

## Error States

The app should handle these states explicitly:

- Prompt file missing: recreate from bundled seed.
- Prompt file invalid JSON: keep last valid in-memory library and show an error.
- Duplicate prompt IDs: load valid prompts if possible and surface validation
  warning.
- Empty prompt library: show empty state with "Open Prompt Library".
- Accessibility permission missing: show permission banner in settings and use
  fallback hotkey if possible.
- Clipboard write failure: show short error HUD and keep overlay open if copying
  did not happen.

## Privacy and Locality

Prompt Paster should be local-first.

V1 should:

- Avoid network access.
- Avoid analytics.
- Avoid remote sync.
- Store prompts only on disk in the user's Application Support directory.
- Avoid reading active app content.
- Avoid auto-paste or key injection by default.

This matters because prompts may contain private repository paths, operational
instructions, and internal workflow details.

## Acceptance Criteria

V1 is useful when all of the following are true:

- The app can run as a menu-bar utility with no Dock icon.
- The app can load a local prompt library.
- The app creates a default seed prompt library on first launch.
- The configured global trigger opens the overlay over the active screen.
- The overlay is keyboard-usable without mouse interaction.
- Search filters prompt results.
- Selecting a prompt copies its body to the clipboard.
- Selecting a prompt closes the overlay.
- `Escape` closes the overlay without changing the clipboard.
- The user can open and edit the prompt library file.
- Invalid prompt library JSON produces a clear recoverable error.
- Launch at login can be enabled or disabled.

## Future Directions

Likely future improvements:

- Built-in prompt editor.
- Markdown import from the original Notes-style format.
- Prompt variables and quick fill-in fields.
- Per-app prompt categories.
- iCloud Drive or Git-backed prompt library sync.
- Optional auto-paste mode.
- Usage-based prompt ranking.
- Multi-library support.
- Alfred/Raycast import/export.
- Spotlight-like fuzzy search.
- Secure encrypted libraries for sensitive prompts.
