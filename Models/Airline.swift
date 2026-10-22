import Foundation

struct Airline: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let alias: String
    let iataCode: String
    let icaoCode: String
    let callsign: String
    let country: String
    let countryCode: String
    let active: String

    nonisolated init(
        id: String,
        name: String,
        alias: String = "",
        iataCode: String = "",
        icaoCode: String = "",
        callsign: String = "",
        country: String = "",
        countryCode: String = "",
        active: String = ""
    ) {
        self.id = id
        self.name = name
        self.alias = alias
        self.iataCode = iataCode
        self.icaoCode = icaoCode
        self.callsign = callsign
        self.country = country
        self.countryCode = countryCode
        self.active = active
    }

    // MARK: - Display

    nonisolated var displayName: String {
        WanderlustL10n.airlineName(
            code: bestCode,
            fallback: cleaned(name)
        )
    }

    nonisolated var normalizedIATACode: String {
        normalizedCode(iataCode)
    }

    nonisolated var normalizedICAOCode: String {
        normalizedCode(icaoCode)
    }

    nonisolated var displayCountry: String {
        cleanedValue(country)
    }

    nonisolated var normalizedCountryCode: String {
        let explicitCode = normalizedCode(countryCode)
        if explicitCode.count == 2 {
            return explicitCode
        }

        let resolvedCode = WanderlustNameResolver.normalizedCountryCode(
            displayCountry,
            fallback: explicitCode
        )
        return resolvedCode.count == 2 ? resolvedCode : ""
    }

    nonisolated var displayCallsign: String {
        cleanedValue(callsign)
    }

    nonisolated var bestCode: String {
        if !normalizedIATACode.isEmpty {
            return normalizedIATACode
        }

        return normalizedICAOCode
    }

    nonisolated var displayTitle: String {
        guard !bestCode.isEmpty else {
            return displayName
        }

        return "\(displayName) (\(bestCode))"
    }

    nonisolated var displaySubtitle: String {
        [
            displayCountry,
            displayCallsign
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    // MARK: - Validation

    nonisolated var isActive: Bool {
        let normalized = active
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .uppercased()
        return normalized == "Y" ||
            normalized == "TRUE" ||
            normalized == "1"
    }

    nonisolated var hasValidIATACode: Bool {
        let code = normalizedIATACode

        return code.count == 2 &&
        code != "-" &&
        code != "N/A"
    }

    nonisolated var isUsableForFlightSearch: Bool {
        guard isActive else {
            return false
        }

        guard !displayName.isEmpty else {
            return false
        }

        guard hasValidIATACode || !normalizedICAOCode.isEmpty else {
            return false
        }

        let normalizedName = Self.normalize(
            displayName
        )

        let blockedNames: Set<String> = [
            "unknown",
            "private flight",
            "private flights"
        ]

        return !blockedNames.contains(
            normalizedName
        )
    }

    nonisolated var isMajorRouteAirline: Bool {
        AirlineSearchRank.priority(for: normalizedIATACode) < 120
    }

    // MARK: - Search

    nonisolated var searchableValues: [String] {
        directSearchableValues +
            JapaneseSearchReadingAliases.airlineAliases(
                code: bestCode
            )
    }

    private nonisolated var directSearchableValues: [String] {
        localizedAirlineNameVariants + [
            cleaned(name),
            cleanedValue(alias),
            normalizedIATACode,
            normalizedICAOCode,
            displayCallsign
        ]
        .filter { !$0.isEmpty }
    }

    private nonisolated var localizedAirlineNameVariants: [String] {
        WanderlustL10n.localizedVariants(
            key: "airline.\(bestCode)",
            table: .airlines,
            fallback: cleaned(name)
        )
    }

    nonisolated func matchesLocalizedAirlineNamePrefix(
        for normalizedQueries: [String]
    ) -> Bool {
        localizedAirlineNameVariants.contains { value in
            let normalizedValue = Self.normalize(value)
            return normalizedQueries.contains { query in
                normalizedValue.hasPrefix(query)
            }
        }
    }

    nonisolated func matches(
        query: String
    ) -> Bool {
        let queryContainsJapaneseKana = JapaneseKanaRomajiSearch
            .containsJapaneseKana(query)
        let normalizedQueries = JapaneseKanaRomajiSearch.normalizedQueryVariants(
            query,
            normalizer: Self.normalize,
            includeRomajiForKana: !queryContainsJapaneseKana
        )

        guard !normalizedQueries.isEmpty else {
            return false
        }

        let directMatch = directSearchableValues.contains { value in
            let normalizedValue = Self.normalize(value)
            return normalizedQueries.contains {
                normalizedValue == $0 ||
                    normalizedValue.hasPrefix($0)
            }
        }

        return directMatch || JapaneseSearchReadingAliases.airlineAliasMatches(
            code: bestCode,
            normalizedQueries: normalizedQueries
        )
    }

    nonisolated func searchScore(
        for query: String
    ) -> Int {
        let queryContainsJapaneseKana = JapaneseKanaRomajiSearch
            .containsJapaneseKana(query)
        let normalizedQueries = JapaneseKanaRomajiSearch.normalizedQueryVariants(
            query,
            normalizer: Self.normalize,
            includeRomajiForKana: !queryContainsJapaneseKana
        )

        guard !normalizedQueries.isEmpty else {
            return 0
        }

        let normalizedNameVariants = localizedAirlineNameVariants
            .map(Self.normalize)
            .filter { !$0.isEmpty }

        let normalizedAlias = Self.normalize(
            cleanedValue(alias)
        )

        let normalizedIATA = Self.normalize(
            normalizedIATACode
        )

        let normalizedICAO = Self.normalize(
            normalizedICAOCode
        )

        let normalizedCallsign = Self.normalize(
            displayCallsign
        )

        if normalizedQueries.contains(where: { query in
            normalizedNameVariants.contains(query)
        }) {
            return 20_000
        }

        if normalizedQueries.contains(normalizedIATA) {
            return 19_000
        }

        if normalizedQueries.contains(normalizedICAO) {
            return 18_000
        }

        if normalizedQueries.contains(normalizedCallsign) {
            return 17_000
        }

        if normalizedQueries.contains(where: { query in
            normalizedNameVariants.contains { $0.hasPrefix(query) }
        }) {
            return 16_000
        }

        if normalizedQueries.contains(where: { normalizedAlias.hasPrefix($0) }) {
            return 15_000
        }

        if normalizedQueries.contains(where: { normalizedCallsign.hasPrefix($0) }) {
            return 14_000
        }

        if normalizedQueries.contains(where: { normalizedIATA.hasPrefix($0) }) {
            return 13_000
        }

        if normalizedQueries.contains(where: { normalizedICAO.hasPrefix($0) }) {
            return 12_000
        }

        if directSearchableValues.contains(
            where: {
                let normalizedValue = Self.normalize($0)
                return normalizedQueries.contains {
                    normalizedValue == $0 || normalizedValue.hasPrefix($0)
                }
            }
        ) {
            return 10_000
        }

        if JapaneseSearchReadingAliases.airlineAliasMatches(
            code: bestCode,
            normalizedQueries: normalizedQueries
        ) {
            return 10_000
        }

        return 0
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case defaultName
        case alias
        case iataCode = "iata"
        case iataCodeLong = "iataCode"
        case icaoCode = "icao"
        case icaoCodeLong = "icaoCode"
        case callsign
        case country
        case countryCode
        case countryISO2
        case countryIso2
        case countryCodeSnake = "country_iso2"
        case active
        case isActive
    }

    nonisolated init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        id = Self.decodeFlexibleString(
            from: container,
            key: .id
        )

        name = Self.decodeFlexibleString(
            from: container,
            keys: [.name, .defaultName]
        )

        alias = Self.decodeFlexibleString(
            from: container,
            key: .alias
        )

        iataCode = Self.decodeFlexibleString(
            from: container,
            keys: [.iataCode, .iataCodeLong]
        )

        icaoCode = Self.decodeFlexibleString(
            from: container,
            keys: [.icaoCode, .icaoCodeLong]
        )

        callsign = Self.decodeFlexibleString(
            from: container,
            key: .callsign
        )

        country = Self.decodeFlexibleString(
            from: container,
            key: .country
        )

        countryCode = Self.decodeFlexibleString(
            from: container,
            keys: [.countryCode, .countryISO2, .countryIso2, .countryCodeSnake]
        )

        active = Self.decodeFlexibleString(
            from: container,
            keys: [.active, .isActive]
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(alias, forKey: .alias)
        try container.encode(iataCode, forKey: .iataCode)
        try container.encode(icaoCode, forKey: .icaoCode)
        try container.encode(callsign, forKey: .callsign)
        try container.encode(country, forKey: .country)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(active, forKey: .active)
    }

    private nonisolated static func decodeFlexibleString(
        from container:
            KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> String {
        for key in keys {
            let value = decodeFlexibleString(from: container, key: key)
            if !value.isEmpty {
                return value
            }
        }

        return ""
    }

    private nonisolated static func decodeFlexibleString(
        from container:
            KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String {
        if let value = try? container.decode(
            String.self,
            forKey: key
        ) {
            return value
        }

        if let value = try? container.decode(
            Int.self,
            forKey: key
        ) {
            return String(value)
        }

        if let value = try? container.decode(
            Double.self,
            forKey: key
        ) {
            return String(value)
        }

        if let value = try? container.decode(
            Bool.self,
            forKey: key
        ) {
            return value ? "true" : "false"
        }

        return ""
    }

    // MARK: - Helpers

    private nonisolated func cleaned(
        _ value: String
    ) -> String {
        value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private nonisolated func cleanedValue(
        _ value: String
    ) -> String {
        let cleanedValue = cleaned(value)

        if cleanedValue == "\\N" ||
            cleanedValue == "N/A" ||
            cleanedValue == "-" {
            return ""
        }

        return cleanedValue
    }

    private nonisolated func normalizedCode(
        _ value: String
    ) -> String {
        cleanedValue(value)
            .uppercased()
    }

    private nonisolated static func normalize(
        _ value: String
    ) -> String {
        SearchNormalizer.normalize(value)
    }
}

enum AirlineSearchRank {
    nonisolated static func priority(for airline: Airline) -> Int {
        priority(for: airline.normalizedIATACode)
    }

    nonisolated static func priority(for iataCode: String) -> Int {
        priorityByIATACode[iataCode.uppercased()] ?? Int.max
    }

    nonisolated static func sqliteCaseExpression(column: String) -> String {
        let cases = prioritizedIATACodes.enumerated().map { index, code in
            "WHEN '\(code)' THEN \(index)"
        }
        .joined(separator: " ")
        return "CASE \(column) \(cases) ELSE 9999 END"
    }

    nonisolated static let starAllianceIATACodes: [String] = [
        "A3", "AC", "AI", "CA", "CM", "ET", "LH", "LO", "LX", "MS",
        "NH", "NZ", "OS", "OU", "OZ", "SA", "SK", "SN", "SQ", "TG",
        "TK", "TP", "UA", "AV", "BR"
    ]

    nonisolated static let oneWorldIATACodes: [String] = [
        "AA", "AS", "BA", "CX", "AY", "IB", "JL", "MH", "QF", "QR",
        "RJ", "UL", "AT", "FJ", "OM", "S7", "LA"
    ]

    nonisolated static let skyTeamIATACodes: [String] = [
        "AM", "AR", "CI", "DL", "AF", "GA", "KQ", "KE", "KL", "ME",
        "MU", "SV", "UX", "VN", "VS", "MF", "AZ"
    ]

    private nonisolated static let prioritizedIATACodes: [String] = [
        "JL", "NH", "AA", "DL", "UA", "WN", "BA", "LH", "AF", "KL",
        "EK", "QR", "SQ", "CX", "QF", "TK", "KE", "AC", "AY", "IB",
        "AS", "AI", "NZ", "BR", "TG", "OS", "LX", "LO", "TP", "SN",
        "SK", "A3", "OU", "MS", "ET", "CM", "AV", "CA", "OZ", "MH",
        "UL", "RJ", "AT", "FJ", "OM", "LA", "MU", "CZ", "6E", "FR",
        "U2", "LS", "W6", "EW", "3U", "F9", "HU", "PC", "MF", "WS",
        "9C", "B6", "AD", "VY", "G3", "SV", "EI", "AM", "JQ", "AK",
        "VN", "GA", "PR", "EY", "SA", "AZ", "VS", "UX", "AR", "BT",
        "DE", "FZ", "NK", "HV", "TO", "SU", "XQ", "Y4", "VF", "G4",
        "V7", "W4", "ZH", "IX", "AH", "VB", "SC", "HO", "FM", "S7",
        "XY", "TS", "HY", "VJ", "JU", "G9", "FD", "OD", "MM", "BC",
        "GK", "7G"
    ]

    private nonisolated static let priorityByIATACode: [String: Int] = {
        var priorities: [String: Int] = [:]
        for (index, code) in prioritizedIATACodes.enumerated() {
            if priorities[code] == nil {
                priorities[code] = index
            }
        }
        return priorities
    }()
}
