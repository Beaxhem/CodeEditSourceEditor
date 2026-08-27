//
//  HighlightProviderState.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 10/13/24.
//

import Foundation
import CodeEditLanguages
import CodeEditTextView
import OSLog

@MainActor
protocol HighlightProviderStateDelegate: AnyObject {
    typealias ProviderID = Int
    func applyHighlightResult(provider: ProviderID, highlights: [HighlightRange], rangeToHighlight: NSRange)
}

/// Keeps track of the valid and pending indices for a single highlight provider in the editor.
///
/// When ranges are invalidated, edits are made, or new text is made visible, this class is notified and queries its
/// highlight provider for invalidated indices.
///
/// Once it knows which indices were invalidated by the edit, it queries the provider for highlights and passes the
/// results to a ``StyledRangeContainer`` to eventually be applied to the editor.
///
/// This class will also chunk the invalid ranges to avoid performing a massive highlight query.
@MainActor
class HighlightProviderState {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "HighlightProviderState")

    /// The length to chunk ranges into when passing to the highlighter.
    private static let rangeChunkLimit = 4096

    // MARK: - State

    /// A unique identifier for this provider. Used by the delegate to determine the source of results.
    let id: Int

    /// Any indexes that highlights have been requested for, but haven't been applied.
    /// Indexes/ranges are added to this when highlights are requested and removed
    /// after they are applied
    private var pendingSet: IndexSet = IndexSet()

    /// The set of valid indexes
    private var validSet: IndexSet = IndexSet()

    // MARK: - Providers

    private weak var delegate: HighlightProviderStateDelegate?

    /// Calculates invalidated ranges given an edit.
    /// Marked as package for deduplication when updating highlight providers.
    package weak var highlightProvider: HighlightProviding?

    /// Provides a constantly updated visible index set.
    private weak var visibleRangeProvider: VisibleRangeProvider?

    /// A weak reference to the text view, used by the highlight provider.
    private weak var textView: TextView?

    private var visibleSet: IndexSet {
        visibleRangeProvider?.visibleSet ?? IndexSet()
    }

    private var documentSet: IndexSet {
        IndexSet(integersIn: visibleRangeProvider?.documentRange ?? .zero)
    }

    /// Creates a new highlight provider state object.
    /// Sends the `setUp` message to the highlight provider object.
    /// - Parameters:
    ///   - id: The ID of the provider
    ///   - delegate: The delegate for this provider. Is passed information about ranges to highlight.
    ///   - highlightProvider: The object to query for highlight information.
    ///   - textView: The text view to highlight, used by the highlight provider.
    ///   - visibleRangeProvider: A visible range provider for determining which ranges to query.
    ///   - language: The language to set up the provider with.
    init(
        id: Int,
        delegate: HighlightProviderStateDelegate,
        highlightProvider: HighlightProviding,
        textView: TextView,
        visibleRangeProvider: VisibleRangeProvider,
        language: CodeLanguage
    ) {
        self.id = id
        self.delegate = delegate
        self.highlightProvider = highlightProvider
        self.textView = textView
        self.visibleRangeProvider = visibleRangeProvider

        highlightProvider.setUp(textView: textView, codeLanguage: language)
    }

    func setLanguage(language: CodeLanguage) {
        guard let textView else { return }
        highlightProvider?.setUp(textView: textView, codeLanguage: language)
        invalidate()
    }

    /// Invalidates all pending and valid ranges, resetting the provider.
    func invalidate() {
        validSet.removeAll()
        pendingSet.removeAll()
        highlightInvalidRanges()
    }

    /// Invalidates a given index set and adds it to the queue to be highlighted.
    /// - Parameter set: The index set to invalidate.
    func invalidate(_ set: IndexSet) {
        if set.isEmpty {
            return
        }

        validSet.subtract(set)

        highlightInvalidRanges()
    }

    /// Accumulates all pending ranges and calls `queryHighlights`.
    func highlightInvalidRanges() {
        var ranges: [NSRange] = []
        while let nextRange = getNextRange() {
            ranges.append(nextRange)
            pendingSet.insert(range: nextRange)
        }
        queryHighlights(for: ranges)
    }
}

extension HighlightProviderState {
    /// Keeps ``validSet`` aligned with the document after an edit.
    ///
    /// It is a plain index set in document coordinates, so an insertion or a deletion moves every
    /// index after it. Without this it goes on naming the characters that *used* to sit at those
    /// offsets, and text after an edit reads as already-highlighted — so nothing queries it again and
    /// it keeps the colours it had before the edit. That is mostly hidden by ``applyEdit`` returning a
    /// generous invalid set, but not on the path where the edit is cancelled and only the edited range
    /// is invalidated.
    ///
    /// Mirrors the convention `RangeStore` uses for the same notification: for a pure deletion
    /// `editedRange` is empty and sits at the start of what was removed.
    ///
    /// ``pendingSet`` is deliberately left alone. A query in flight completes against the range it was
    /// *requested* with — see ``queryHighlights`` — so moving those indices here would leave residue
    /// that `remove(integersIn:)` no longer matches, and an index stuck in `pendingSet` is subtracted
    /// from every future query for the lifetime of the editor. Leaving it stale costs one round trip of
    /// imprecision instead, and clears itself exactly.
    func storageUpdated(editedRange: NSRange, changeInLength delta: Int) {
        guard delta != 0 else { return }

        let replaced: Range<Int> = if editedRange.length == 0 {
            editedRange.location..<(editedRange.location - delta)
        } else {
            editedRange.location..<(editedRange.location + editedRange.length - delta)
        }

        // Whatever was known about the replaced characters died with them.
        validSet.remove(integersIn: replaced)
        validSet.shift(startingAt: replaced.upperBound, by: delta)
    }

    func storageWillUpdate(in range: NSRange) {
        guard let textView else { return }
        highlightProvider?.willApplyEdit(textView: textView, range: range)
    }

    func storageDidUpdate(range: NSRange, delta: Int) {
        guard let textView else { return }
        highlightProvider?.applyEdit(textView: textView, range: range, delta: delta) { [weak self] result in
            switch result {
            case .success(let invalidSet):
                let modifiedRange = NSRange(location: range.location, length: range.length + delta)
                // Make sure we add in the edited range too
                self?.invalidate(invalidSet.union(IndexSet(integersIn: modifiedRange)))
            case .failure(let error):
                if case HighlightProvidingError.operationCancelled = error {
                    self?.invalidate(IndexSet(integersIn: range))
                } else {
                    self?.logger.error("Failed to apply edit. Query returned with error: \(error)")
                }
            }
        }
    }
}

private extension HighlightProviderState {
    /// Gets the next `NSRange` to highlight based on the invalid set, visible set, and pending set.
    /// - Returns: An `NSRange` to highlight if it could be fetched.
    func getNextRange() -> NSRange? {
        let set: IndexSet = documentSet // All text
            .subtracting(validSet)      // Subtract valid = Invalid set
            .intersection(visibleSet)   // Only visible indexes
            .subtracting(pendingSet)    // Don't include pending indexes

        guard let range = set.rangeView.first else {
            return nil
        }

        // Chunk the ranges in sets of rangeChunkLimit characters.
        return NSRange(
            location: range.lowerBound,
            length: min(Self.rangeChunkLimit, range.upperBound - range.lowerBound)
        )
    }

    /// Queries for highlights for the given ranges
    /// - Parameter rangesToHighlight: The ranges to request highlights for.
    func queryHighlights(for rangesToHighlight: [NSRange]) {
        guard let textView else { return }
        for range in rangesToHighlight {
            highlightProvider?.queryHighlightsFor(textView: textView, range: range) { [weak self] result in
                guard let providerId = self?.id else { return }
                assert(Thread.isMainThread, "Highlighted ranges called on non-main thread.")

                self?.pendingSet.remove(integersIn: range)
                self?.validSet.insert(range: range)

                switch result {
                case .success(let highlights):
                    self?.delegate?.applyHighlightResult(
                        provider: providerId,
                        highlights: highlights,
                        rangeToHighlight: range
                    )
                case .failure(let error):
                    // Only invalidate if it was cancelled.
                    if let error = error as? HighlightProvidingError, error == .operationCancelled {
                        self?.invalidate(IndexSet(integersIn: range))
                    } else {
                        self?.logger.debug("Highlighter Error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
