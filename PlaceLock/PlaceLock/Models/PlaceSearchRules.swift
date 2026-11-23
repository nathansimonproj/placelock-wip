import Foundation

// MARK: - Place search: what pressing Search does

/// Decisions for the Add place search field. Apple's type-ahead completer can stall on a slow
/// network (seen on plane Wi-Fi), so pressing Search falls back to one plain search request.
enum PlaceSearchRules {
    enum SubmitAction: Equatable {
        /// Empty field, or a search or pick is already running.
        case nothing
        /// The list matches what's typed: take its top row, as tapping it would.
        case pickFirstSuggestion
        /// The completer hasn't answered for this text: search for it directly.
        case searchDirectly(String)
    }

    /// The search text as the completer and the search request see it.
    static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// - Parameters:
    ///   - query: what's in the search field.
    ///   - suggestionsQuery: the text the current list of suggestions answers, nil before any answer.
    ///   - suggestionCount: rows in that list.
    ///   - busy: a pick or direct search is already running.
    static func onSubmit(query: String, suggestionsQuery: String?, suggestionCount: Int, busy: Bool) -> SubmitAction {
        let text = normalized(query)
        guard !text.isEmpty, !busy else { return .nothing }
        // Rows left over from an earlier, shorter query don't count: they may not be what was typed.
        if suggestionCount > 0, let suggestionsQuery, normalized(suggestionsQuery) == text {
            return .pickFirstSuggestion
        }
        return .searchDirectly(text)
    }

    /// A direct search can take a long time on a bad network. Only fill in its result if the
    /// search field still says what was searched for; if it was cleared or retyped, drop it.
    static func shouldApplyDirectResult(searched: String, current: String) -> Bool {
        normalized(searched) == normalized(current)
    }
}
