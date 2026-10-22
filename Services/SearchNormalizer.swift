import Foundation

enum SearchTokenKind: Sendable {
    case officialName
    case localizedName
    case alias
    case code
    case reading
}

struct SearchToken: Sendable {
    let kind: SearchTokenKind
    let value: String
    let normalizedValues: [String]
    let sourceContainsJapaneseKana: Bool

    nonisolated init(
        kind: SearchTokenKind,
        value: String,
        includeRomajiForKana: Bool = true
    ) {
        self.kind = kind
        self.value = value
        sourceContainsJapaneseKana = SearchNormalizer.containsJapaneseKana(value)
        normalizedValues = SearchNormalizer.queryVariants(
            for: value,
            includeRomajiForKana: includeRomajiForKana
        )
    }
}

struct SearchCandidate<Item: Sendable>: Sendable {
    let item: Item
    let tokens: [SearchToken]

    nonisolated func score(
        for queries: [String],
        containsJapaneseKana: Bool
    ) -> Int? {
        tokens
            .compactMap { token in
                Self.score(
                    token: token,
                    queries: queries,
                    containsJapaneseKana: containsJapaneseKana
                )
            }
            .max()
    }

    private nonisolated static func score(
        token: SearchToken,
        queries: [String],
        containsJapaneseKana: Bool
    ) -> Int? {
        var bestScore: Int?

        for value in token.normalizedValues where !value.isEmpty {
            for query in queries where !query.isEmpty {
                let score: Int?
                if value == query {
                    score = exactScore(for: token.kind)
                } else if value.hasPrefix(query),
                          canPrefixMatch(
                            token: token,
                            query: query,
                            containsJapaneseKana: containsJapaneseKana
                          ) {
                    score = prefixScore(for: token.kind)
                } else if !containsJapaneseKana,
                          query.count >= 3,
                          SearchNormalizer.containsWordPrefix(query, in: value) {
                    score = wordPrefixScore(for: token.kind)
                } else {
                    score = nil
                }

                if let score {
                    bestScore = max(bestScore ?? 0, score)
                }
            }
        }

        return bestScore
    }

    private nonisolated static func canPrefixMatch(
        token: SearchToken,
        query: String,
        containsJapaneseKana: Bool
    ) -> Bool {
        // A single Latin letter is too broad for romaji-expanded Japanese names.
        if token.sourceContainsJapaneseKana,
           !containsJapaneseKana,
           query.count < 2 {
            return false
        }

        switch token.kind {
        case .alias, .reading:
            return containsJapaneseKana || query.count >= 2
        case .code:
            return query.count >= 2
        case .officialName, .localizedName:
            return true
        }
    }

    private nonisolated static func exactScore(
        for kind: SearchTokenKind
    ) -> Int {
        switch kind {
        case .code:
            return 10_000
        case .localizedName:
            return 9_800
        case .officialName:
            return 9_700
        case .alias:
            return 9_500
        case .reading:
            return 9_600
        }
    }

    private nonisolated static func prefixScore(
        for kind: SearchTokenKind
    ) -> Int {
        switch kind {
        case .code:
            return 9_600
        case .localizedName:
            return 9_000
        case .officialName:
            return 8_900
        case .alias:
            return 8_500
        case .reading:
            return 9_100
        }
    }

    private nonisolated static func wordPrefixScore(
        for kind: SearchTokenKind
    ) -> Int {
        switch kind {
        case .code:
            return 8_800
        case .localizedName:
            return 8_000
        case .officialName:
            return 7_900
        case .alias:
            return 7_600
        case .reading:
            return 7_500
        }
    }
}

enum SearchNormalizer {
    nonisolated static func normalize(_ text: String) -> String {
        let foldedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "'", with: "")
            .lowercased()

        return String(foldedText.map(normalizedKanaCharacter))
    }

    nonisolated static func queryVariants(
        for query: String,
        includeRomajiForKana: Bool? = nil
    ) -> [String] {
        let containsKana = containsJapaneseKana(query)
        return JapaneseKanaRomajiSearch.normalizedQueryVariants(
            query,
            normalizer: normalize,
            includeRomajiForKana: includeRomajiForKana ?? !containsKana
        )
    }

    nonisolated static func containsJapaneseKana(_ text: String) -> Bool {
        JapaneseKanaRomajiSearch.containsJapaneseKana(text)
    }

    nonisolated static func containsWordPrefix(
        _ query: String,
        in text: String
    ) -> Bool {
        let words = text.split { character in
            !character.isLetter && !character.isNumber
        }

        return words.contains { word in
            word.hasPrefix(query)
        }
    }

    private nonisolated static func normalizedKanaCharacter(
        _ character: Character
    ) -> Character {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1,
              (0x30A1...0x30F6).contains(Int(scalar.value)),
              let hiragana = UnicodeScalar(scalar.value - 0x60) else {
            return character
        }

        return Character(hiragana)
    }
}
