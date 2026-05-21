# Prompt Paster

Prompt Paster is a native macOS utility for quickly selecting reusable coding
agent prompts from an overlay and copying them to the clipboard.

## Current Status

The repository currently contains the first native app shell:

- a SwiftPM macOS executable target
- a menu-bar utility app with no Dock icon
- a placeholder overlay window
- a placeholder settings window

Prompt library storage, real search, clipboard selection, and global hotkeys are
planned in follow-up PRs.

## Run Locally

Requirements:

- macOS
- Xcode command line tools or Xcode
- Swift 6.0 or newer

Run the app from the repository root:

```bash
swift run PromptPaster
```

The app appears in the macOS menu bar. Use the menu-bar item to open the
placeholder overlay or settings window.

## Planning Docs

- [Design, architecture, and spec](docs/design-architecture-spec.md)
- [Implementation plan](docs/implementation-plan.md)
