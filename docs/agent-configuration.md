# Agent-managed prompt libraries

Prompt Paster 0.3.1 includes a headless CLI in the installed app. It uses the
same JSON library, GitHub reader, extraction, and composite resolver as the GUI.
Library commands never open an overlay or change the clipboard.
For an agent handoff with the app closed, `--show`, `--edit-library`, and
`--settings` launch the corresponding GUI view. Reopening the running app also
shows its overlay when no window is visible.

```sh
PP="/Applications/Prompt Paster.app/Contents/MacOS/PromptPaster"
"$PP" --help
"$PP" --version
"$PP" library info
"$PP" library list
"$PP" library export > library-backup.json
```

The default file is `~/Library/Application Support/Prompt Paster/prompts.json`.
Commands accept `--library /absolute/path/prompts.json` for isolated configuration
and testing. `info`, `list`, and `export` treat a missing library as empty;
`validate` requires an existing file. JSON output goes to stdout, errors to
stderr, and failures exit nonzero. `render` prints prompt text instead of JSON.
Exports and backups contain prompt bodies; store them privately.

## Apply a manifest

`library example` prints a complete example manifest. A manifest may contain any
of `version`, `prompts`, `githubSources`, and `composites`. Entries are merged by
ID. Only supplied fields are updated, unmentioned entries and metadata survive,
and applying the same manifest again is a no-op. An empty array does not delete
entries. Unknown fields, duplicate manifest IDs, invalid definitions, ambiguous
IDs across prompt types, and missing composite components are rejected before
writing. Existing version-1 libraries and sources retain their old defaults.

```json
{
  "githubSources": [
    {
      "id": "team-base",
      "title": "Team base",
      "owner": "example",
      "repository": "team-wiki",
      "ref": "main",
      "path": "prompts/base.md",
      "authentication": "githubCLI",
      "content": "pasteReadyBlock"
    },
    {
      "id": "team-suffix",
      "title": "Project suffix",
      "owner": "example",
      "repository": "project-wiki",
      "ref": "main",
      "path": "prompts/suffix.md",
      "authentication": "githubCLI",
      "content": "wholeFile"
    }
  ],
  "composites": [
    {
      "id": "project-start",
      "title": "Start a project agent",
      "componentPromptIDs": ["github-team-base", "github-team-suffix"],
      "separator": "\n\n"
    }
  ]
}
```

```sh
"$PP" library apply manifest.json --dry-run
"$PP" library apply manifest.json
# Or: "$PP" library apply - < manifest.json
"$PP" library validate
"$PP" library refresh
"$PP" library render project-start > complete-prompt.txt
"$PP" library favorites project-start
```

`apply` holds an advisory lock shared with GUI saves, validates the complete
result, saves an exact private backup under the library's `Backups` directory,
and atomically replaces the file with owner-only permissions. Dry runs do not
write a library or backup (a lock file and parent directory may be created).
Concurrent CLI updates are serialized. GUI drafts detect a changed file and
refuse to overwrite it. Discard the stale draft, then reapply the edit.
For removal, use the GUI's source/composite delete controls; remove references
before removing their component source. Direct file writers should use atomic
replacement and avoid editing while a GUI draft is open.

## Access and extraction

Each source has its own access mode:

- `githubCLI`: runs an installed `gh api` against `github.com` using its existing
  sign-in. Run `gh auth login` once; the signed-in account needs read access to
  each repository. Prompt Paster finds gh in `/opt/homebrew/bin`, `/usr/local/bin`,
  or `/usr/bin`, including when launched from Finder. It never reads or copies
  the gh token, invokes a shell, or exposes gh's raw stderr. Calls time out after
  20 seconds and cap their output at 4 MiB.
- `storedToken` (the backward-compatible default): uses the app token in macOS
  Keychain, configured in **Settings → GitHub access**. Without a token it can
  read public repositories.
- `anonymous`: public GitHub access without sending the app token.

There are no credentials in manifests. Authentication must already exist on the
Mac. The GUI exposes both access and content modes under **Edit Prompt Library
→ Sources & Composites**.

`wholeFile` (default) uses the complete UTF-8 Markdown/text file. `pasteReadyBlock`
requires exactly one `## Paste-Ready Prompt` heading followed immediately (apart
from blank lines) by a nonempty fenced text/Markdown block. It removes the
wrapper, fences, and surrounding documentation. Backtick and tilde fences are
supported; a longer outer fence preserves shorter nested code fences. A missing,
ambiguous, empty, or unclosed block is an error, never a whole-file fallback.

## Refresh and layering

Library file edits and home favorites reload when the overlay opens. Every
source is fetched afresh at its configured ref; use `main` for current content or
a commit SHA for a pinned version. Remote bodies are not persisted into the
library. `refresh` reports availability and character counts without exposing
bodies; `render ID` fetches and prints the complete selected prompt. A failed
source makes dependent composites unavailable with an error. Partial composites
and stale cached source bodies are never offered. Configured favorites and usage
history survive temporary GitHub failures.

Composites join **local prompt IDs** and **`github-<source-id>` IDs** in their
specified order. They do not execute generators, interpret includes, or nest
other composites. For an upstream repository with layered/generated prompts,
point the source at its maintained assembled artifact and extract its paste-ready
block, then add only layers that artifact does not already include. Upstream
agents continue maintaining those owning repositories; Prompt Paster follows
their committed output.

`favorites ID ...` appends missing IDs without disturbing existing slots, enables
the home screen, and fails before changing settings if its sixteen slots are full.
It operates only on the default installed library. An optional local symlink to
the bundled executable can give agents a shorter command; the app does not
install privileged helpers.

## AGENT-SOURCES-1 scope

Baseline: 0.2.0 had whole-file sources and a single app token, without a headless
management workflow. The measurable outcome is complete current layered prompts
with repeatable agent configuration. Existing local prompts, favorites,
clipboard behavior, and Keychain credentials must survive. Personal repository
definitions and prompt bodies stay in the local library, outside this public
repository. Release completion requires a labeled ready PR, passing tests and
live source comparison, a verified signed/notarized 0.3.1 download, and validation
of the configured local installation.
