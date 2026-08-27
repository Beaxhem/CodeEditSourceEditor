//
//  VisibleRangeProvider.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 10/13/24.
//

import AppKit
import CodeEditTextView

@MainActor
protocol VisibleRangeProviderDelegate: AnyObject {
    func visibleSetDidUpdate(_ newIndices: IndexSet)
}

/// Provides information to ``HighlightProviderState``s about what text is visible in the editor. Keeps it's contents
/// in sync with a text view and notifies listeners about changes so highlights can be applied to newly visible indices.
@MainActor
class VisibleRangeProvider {
    private weak var textView: TextView?
    weak var delegate: VisibleRangeProviderDelegate?

    var documentRange: NSRange {
        textView?.documentRange ?? .notFound
    }

    /// The set of visible indexes in the text view
    lazy var visibleSet: IndexSet = {
        return IndexSet(integersIn: textView?.visibleTextRange ?? NSRange())
    }()

    init(textView: TextView) {
        self.textView = textView

        if let scrollView = textView.enclosingScrollView {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(visibleTextChanged),
                name: NSView.frameDidChangeNotification,
                object: scrollView
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(visibleTextChanged),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(visibleTextChanged),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
    }

    /// Keeps the visible set aligned with the document after an edit.
    ///
    /// Deliberately does *not* re-read `visibleTextRange`. The layout manager is a storage delegate
    /// processing the same notification, and it is not guaranteed to be finished with it — so right
    /// after an edit that range still describes the document as it was. Highlight queries are clamped
    /// to this set (see `HighlightProviderState.getNextRange`), so a short answer here drops the tail
    /// of the edit from the query, and because the truncated range is then marked *valid* nothing ever
    /// queries it again: the text keeps the colours it had before the edit.
    ///
    /// Layout-driven corrections still arrive the usual way, through the frame and bounds observers.
    func storageUpdated(editedRange: NSRange, changeInLength delta: Int) {
        if delta != 0 {
            // For a pure deletion `editedRange` is empty and sits at the start of what was removed —
            // the same convention `RangeStore` reads this notification with.
            let replaced: Range<Int> = if editedRange.length == 0 {
                editedRange.location..<(editedRange.location - delta)
            } else {
                editedRange.location..<(editedRange.location + editedRange.length - delta)
            }

            visibleSet.remove(integersIn: replaced)
            visibleSet.shift(startingAt: replaced.upperBound, by: delta)
        }

        if !editedRange.isEmpty {
            visibleSet.insert(range: editedRange)
        }

        // No delegate call: the providers have not been told about the edit yet, so a pass kicked off
        // here would query a tree that still describes the old text. `storageDidUpdate` runs one
        // immediately after, which is the right moment for it.
    }

    /// Updates the view to highlight newly visible text when the textview is scrolled or bounds change.
    @objc func visibleTextChanged() {
        guard let textViewVisibleRange = textView?.visibleTextRange else {
            return
        }

        let visibleSet = IndexSet(integersIn: textViewVisibleRange)

        self.visibleSet = visibleSet
        delegate?.visibleSetDidUpdate(visibleSet)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
