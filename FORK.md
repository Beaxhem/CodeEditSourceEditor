# Querynaut fork

Fork of [CodeEditApp/CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor),
branched from tag `0.15.2`.

## Why fork at all

Two reasons, both about the grammar payload:

1. Upstream pins `CodeEditLanguages` at `exact: "0.1.20"`, whose prebuilt
   `CodeLanguagesContainer.xcframework` carries **all 37** tree-sitter grammars —
   34 MB, none of it strippable. Querynaut needs one: SQL.
2. `TreeSitterLanguage+TagFilter.swift` referenced `CodeLanguage.html`,
   `.javascript`, `.typescript`, `.jsx` and `.tsx` by name, so it does not compile
   against a trimmed grammar set at all.

A local-path override of `CodeEditLanguages` alone is not enough. It does take
precedence — SwiftPM resolves the local copy over the transitive pin — but it emits
`Conflicting identity for codeeditlanguages … This will be escalated to an error in
future versions of SwiftPM`, and it does nothing about reason 2.

## What was changed

| File | Change |
|------|--------|
| `Package.swift` | `CodeEditLanguages` dependency now `.package(path: "../CodeEditLanguages")` |
| `Sources/CodeEditSourceEditor/Extensions/TreeSitterLanguage+TagFilter.swift` | `shouldProcessTags()` returns `false` unconditionally |

Tag processing only ever applied to HTML and the JS/TS family, so for SQL the answer
was already constant.

## Layout requirement

The relative path means this package expects
[Beaxhem/CodeEditLanguages](https://github.com/Beaxhem/CodeEditLanguages) checked out
as a **sibling directory**:

```
Querynaut/
├── CodeEditLanguages/        ← SQL-only grammar fork
├── CodeEditSourceEditor/     ← this package
└── Querynaut/                ← the app
```

That matches how the app's other vendored packages (`PostgresKit`, `DuckDbKit`,
`SSHKit`, …) are already arranged. The trade-off is that this repository does not
build standalone on GitHub CI.

## Behaviour changes (2026-08-25)

Three edits beyond the grammar strip, each marked `// Querynaut fork:` in the source.

**`CodeSuggestion/TableView/SuggestionViewController.swift` — applying a completion tears
the window down through the window controller.** Upstream passes `view.window` into
`SuggestionViewModel.applySelectedItem(item:window:)`, which calls `window.close()` on the
`NSWindow` directly. That bypasses `SuggestionController.close()`, so `willClose()` never
runs and `activeTextView` is left set. From then on `cursorsUpdated` takes the
"already active" branch, refreshes `items`, and never calls the closure that would
re-present the window — the completion list works exactly once per editor. Upstream bug;
worth reporting.

**`CodeSuggestion/TableView/CodeSuggestionLabelView.swift` — the kind symbol is drawn
hierarchically in `imageColor`.** Upstream draws it `.foregroundStyle(.white, imageColor)`,
a palette style that assumes a two-layer filled symbol (`k.square.fill` and friends).
Given a one-layer symbol the whole glyph takes the primary colour, which is white, and
disappears in light mode.

**`Controller/TextViewController+Lifecycle.swift` — Escape no longer opens the completion
list.** Upstream treats Escape as "show completions" and swallows the event. Querynaut
uses Escape to resign the editor, and its window focus system never sees the key. Escape
now dismisses an open list and otherwise falls through; ⌃Space still opens completions.

## Merging upstream

```
git fetch upstream && git merge upstream/main
```

Expect conflicts only in the two files above.
