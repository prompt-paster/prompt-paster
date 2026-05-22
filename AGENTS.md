# Agent Instructions

## Repository Rules

- Prefer standard `git` and `gh` CLI commands for Git and GitHub work.
- Start feature and PR work from current `origin/main` on a fresh branch.
- Treat feature work as incomplete until a non-draft GitHub PR is open, labeled, and assigned to a relevant milestone when one exists.
- Do not edit generated build output under `.build/` or `dist/`.
- Keep long-form planning in `docs/`; keep immediate state in `.agent-plan.md`.

## Commands

- Build: `swift build`
- Test: `swift test`
- Build app bundle: `scripts/build-app.sh`
- Validate bundle metadata: `plutil -lint Packaging/Info.plist`
- Run development app: `swift run PromptPaster`

## Branch and PR Naming

- Use planning notation in branch names when practical:
  - `clipboard-1-copy-close-loop`
  - `hotkey-1-global-fallback-hotkey`
- Use PR title format: `<NOTATION>: <sentence-case summary>`.
- Include PR body sections for planning notation, summary, scope boundary, validation, and follow-up.

## Architecture Boundaries

- App lifecycle and menu-bar integration live under `Sources/PromptPaster/App/`.
- Prompt models live under `Sources/PromptPaster/Models/`.
- Storage, coding, and search services live under `Sources/PromptPaster/Services/`.
- Overlay window and prompt browser UI live under `Sources/PromptPaster/Overlay/`.
- Settings UI lives under `Sources/PromptPaster/Settings/`.
- Bundled prompt data lives under `Sources/PromptPaster/Resources/`.
- Packaging metadata and scripts live under `Packaging/` and `scripts/`.

## Coding Standards

- Keep SwiftUI views thin; put testable state transitions and filtering logic in separate types.
- Keep AppKit windowing and macOS integration isolated from prompt data logic.
- Preserve local-first behavior; do not add network access or analytics.
- Do not implement auto-paste unless a later task explicitly asks for it.
- Add focused XCTest coverage for model, validation, search, and state logic.
