import Testing
@testable import PlaceLock

/// Pressing Search in Add place: take the top suggestion when it's for this text, otherwise
/// search directly so a stalled type-ahead doesn't leave you stuck.
struct PlaceSearchRulesTests {
    @Test func emptyFieldDoesNothing() {
        for query in ["", "   "] {
            #expect(PlaceSearchRules.onSubmit(query: query, suggestionsQuery: "cafe", suggestionCount: 3, busy: false) == .nothing)
        }
    }

    @Test func busyDoesNothing() {
        #expect(PlaceSearchRules.onSubmit(query: "Smith Hall", suggestionsQuery: "Smith Hall", suggestionCount: 2, busy: true) == .nothing)
        #expect(PlaceSearchRules.onSubmit(query: "Smith Hall", suggestionsQuery: nil, suggestionCount: 0, busy: true) == .nothing)
    }

    @Test func currentSuggestionsPickTheFirst() {
        #expect(PlaceSearchRules.onSubmit(query: "Smith Hall", suggestionsQuery: "Smith Hall", suggestionCount: 2, busy: false)
                == .pickFirstSuggestion)
    }

    @Test func surroundingSpacesDontMatter() {
        #expect(PlaceSearchRules.onSubmit(query: " Smith Hall ", suggestionsQuery: "Smith Hall", suggestionCount: 1, busy: false)
                == .pickFirstSuggestion)
        #expect(PlaceSearchRules.onSubmit(query: "  Gates  ", suggestionsQuery: nil, suggestionCount: 0, busy: false)
                == .searchDirectly("Gates"))
    }

    @Test func noAnswerYetSearchesDirectly() {
        #expect(PlaceSearchRules.onSubmit(query: "Smith Hall", suggestionsQuery: nil, suggestionCount: 0, busy: false)
                == .searchDirectly("Smith Hall"))
    }

    @Test func noMatchesOrFailureSearchesDirectly() {
        // The completer answered with nothing, or failed (which also empties the list).
        #expect(PlaceSearchRules.onSubmit(query: "Smith Hall", suggestionsQuery: "Smith Hall", suggestionCount: 0, busy: false)
                == .searchDirectly("Smith Hall"))
    }

    @Test func leftoverSuggestionsFromEarlierTextSearchDirectly() {
        // The list still shows rows for "Smi" while the completer hasn't answered "Smith Hall".
        #expect(PlaceSearchRules.onSubmit(query: "Smith Hall", suggestionsQuery: "Smi", suggestionCount: 5, busy: false)
                == .searchDirectly("Smith Hall"))
    }

    @Test func directResultAppliesOnlyIfTheFieldStillMatches() {
        #expect(PlaceSearchRules.shouldApplyDirectResult(searched: "Smith Hall", current: "Smith Hall"))
        #expect(PlaceSearchRules.shouldApplyDirectResult(searched: "Smith Hall", current: "Smith Hall "))
        #expect(!PlaceSearchRules.shouldApplyDirectResult(searched: "Smith Hall", current: ""))
        #expect(!PlaceSearchRules.shouldApplyDirectResult(searched: "Smith Hall", current: "Gates"))
    }
}
