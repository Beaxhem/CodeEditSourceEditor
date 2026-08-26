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

**`CodeSuggestion/Window/SuggestionController.swift` — `cursorsUpdated` presents the list
whenever it should be up and isn't.** Two silent stuck states otherwise. A request that
resolves to no items still leaves `activeTextView` set, and `SuggestionViewModel`'s
"already active" branch then refreshes `items` forever for a window that is never shown
again — one word whose first keystroke matched nothing disables completion until
something else closes the controller. Separately, an outstanding `itemsRequestTask` makes
`cursorsUpdated` return immediately, so keystrokes typed during a schema fetch are dropped
instead of superseding it.

**`CodeSuggestion/TableView/CodeSuggestionLabelView.swift` — the kind symbol is drawn
hierarchically in `imageColor`.** Upstream draws it `.foregroundStyle(.white, imageColor)`,
a palette style that assumes a two-layer filled symbol (`k.square.fill` and friends).
Given a one-layer symbol the whole glyph takes the primary colour, which is white, and
disappears in light mode.

**`SourceEditorConfiguration/SourceEditorConfiguration+Appearance.swift` — a transparent
editor gets a transparent gutter.** With `useThemeBackground: false` upstream still paints
the gutter `.windowBackgroundColor`, which is a white strip down the left of a tile that
draws its own material. (The scroll view and clip view also need `drawsBackground = false`,
which the host sets — upstream only clears the scroll view's background *colour*.)

**`Controller/TextViewController+Lifecycle.swift` — Escape no longer opens the completion
list.** Upstream treats Escape as "show completions" and swallows the event. Querynaut
uses Escape to resign the editor, and its window focus system never sees the key. Escape
now dismisses an open list and otherwise falls through; ⌃Space still opens completions.

## Performance change (2026-08-26)

**`Find/FindViewController.swift` — the find panel is built on demand.** Upstream creates
`FindPanelHostingView` in `init` and adds it as a subview in `loadView`, so every editor
carries a live `NSHostingView` from birth. `viewWillAppear` is the only thing that hides
it — and `TextViewController` attaches this controller with `addChild` plus a manual
`addSubview`, which drives no appearance transition, so for a host that never calls it the
panel stays *visible*. Hiding would not have been enough anyway: an `NSHostingView` builds
and updates its content regardless of `isHidden`, and this one's content is a search field,
a controls row, and a `FindMethodPicker` that makes an `NSPopUpButton`, two labels and a
menu.

Sampling a pure layout loop in Querynaut — editors constructed once, asserted not rebuilt —
put `FindMethodPicker.makeNSView` alone at ~25% of main-thread time and the find panel's
frames together at roughly three quarters of it, in a one-line query bar that never opens
find.

`findPanel` is now a computed property that installs the panel on first access;
``FindViewController/installedFindPanel`` is the one to read when you only want to act on a
panel that already exists. `hideFindPanel` returns early when there is none.

Measured in Querynaut (`QueryEditorKnobBenchmarks`, `InputBarAppearBenchmarks`, Release,
4 tiles, median ns per invalidation):

| | before | after |
|---|---|---|
| editor layout | 9.66 ms/tile | 0.44 ms/tile |
| mounting the input bar (⌘L) | 29 ms/tile | 4.9 ms/tile |

`FindPanelTests.findPanelIsNotBuiltUntilShown` and `hidingAnUnshownPanelBuildsNothing`
guard it. Upstream bug, and worth reporting — it costs every embedder, not just this one.

Also `Tests/CodeEditSourceEditorTests/Mock.swift` now asks for `.sql` rather than `.html`,
which the SQL-only `CodeEditLanguages` no longer defines. The rest of the test target still
does not compile for the same reason.

## Merging upstream

```
git fetch upstream && git merge upstream/main
```

Expect conflicts only in the two files above.
