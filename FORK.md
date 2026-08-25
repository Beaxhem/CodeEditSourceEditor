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

## Merging upstream

```
git fetch upstream && git merge upstream/main
```

Expect conflicts only in the two files above.
