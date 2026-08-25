//
//  TreeSitterLanguage+TagFilter.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 5/25/24.
//

import CodeEditLanguages

extension TreeSitterLanguage {
    /// Tag processing exists for the markup languages — HTML and the JavaScript/TypeScript
    /// family — none of which this fork of `CodeEditLanguages` ships. Referencing them by
    /// name would not compile against a SQL-only grammar set, and SQL has no tags to
    /// process, so the answer is constant. See `FORK.md`.
    func shouldProcessTags() -> Bool {
        false
    }
}
