# PROMPT-SOURCES-1: GitHub sources, favorites home, and composite prompts

## Scope

This vertical slice adds three related prompt-selection capabilities while
keeping the local library as the user's durable configuration:

1. GitHub sources fetch one Markdown or UTF-8 text file from a configured
   `owner/repository`, ref, and path whenever the overlay opens.
2. Starred prompts form an optional home screen with a user-controlled order
   and unique letter key for each prompt.
3. Composite prompts concatenate complete local and/or GitHub-backed prompts
   in configured order, entirely on the local Prompt Paster side.

## Security boundary

GitHub source definitions live in `prompts.json`, but the fine-grained GitHub
token is stored only in the current user's macOS Keychain. Prompt Paster sends
that token only to `api.github.com` while reading configured GitHub contents.
The token needs read-only Contents access for private repositories; public
repositories can be used without one.

## Effective prompt order

At each successful refresh, the overlay receives:

```text
local prompts -> fetched GitHub file prompts -> resolved composites
```

A composite is omitted, with a visible warning, whenever one of its component
prompt IDs is unavailable. This prevents copying an incomplete composition.

## Interaction model

- The home screen is enabled by default and appears when the overlay opens with
  an empty query.
- Starring a card adds it to home (up to eight prompts) with an initial key from
  `A S D F G H J K`.
- The pencil in the overlay switches home into edit mode. Cards can be dragged
  to reorder them, and their one-letter keys can be changed in place.
- Typing in search immediately switches from home to the normal dynamic search
  result layout and its existing result shortcuts.
- The Settings toggle can disable home, restoring the prior empty-query result
  grid.

## Configuration UI

Use **Edit Prompt Library → Sources & Composites** to add GitHub Markdown/text
files or composite definitions. A GitHub source with ID `team-rules` becomes
the dynamic prompt ID `github-team-rules`; that is the ID a composite should
list as a component.
