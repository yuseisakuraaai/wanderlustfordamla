import Foundation
import Combine

@MainActor
final class AirlineDataLoader: ObservableObject {
    static let shared = AirlineDataLoader()

    @Published private(set)
    var airlines: [Airline] = []

    @Published private(set)
    var isLoading = false

    @Published private(set)
    var loadingError: String?

    private var airlinesByID:
        [String: Airline] = [:]

    private var airlinesByIATA:
        [String: Airline] = [:]

    private var airlinesByICAO:
        [String: Airline] = [:]

    private var airlineSearchPrefixIndex:
        [String: [Airline]] = [:]

    private var hasLoaded = false
    private var loadTask: Task<[Airline], Error>?

    private init() {}

    // MARK: - Loading

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        await load()
    }

    func reload() async {
        hasLoaded = false
        airlines = []
        airlinesByID = [:]
        airlinesByIATA = [:]
        airlinesByICAO = [:]
        airlineSearchPrefixIndex = [:]

        await load()
    }

    func releaseMemory() {
        loadTask?.cancel()
        loadTask = nil
        hasLoaded = false
        airlines = []
        airlinesByID = [:]
        airlinesByIATA = [:]
        airlinesByICAO = [:]
        airlineSearchPrefixIndex = [:]
        isLoading = false
        loadingError = nil
    }

    private func load() async {
        if let loadTask {
            do {
                let loadedAirlines = try await loadTask.value
                if !hasLoaded {
                    applyLoadedAirlines(loadedAirlines)
                }
            } catch {
                applyLoadFailure(error)
            }
            return
        }

        isLoading = true
        loadingError = nil
        #if DEBUG
        let start = CFAbsoluteTimeGetCurrent()
        #endif

        do {
            let task = Task.detached(
                priority: .userInitiated
            ) {
                try Self.loadAirlinesFromBundle()
            }
            loadTask = task
            let loadedAirlines = try await task.value

            applyLoadedAirlines(loadedAirlines)

            #if DEBUG
            print(String(format: "[WanderlustPerformance] airlines.json %.1fms %d airlines", (CFAbsoluteTimeGetCurrent() - start) * 1000, loadedAirlines.count))
            #endif
        } catch {
            applyLoadFailure(error)
        }

        loadTask = nil
    }

    private func applyLoadedAirlines(_ loadedAirlines: [Airline]) {
        airlines = loadedAirlines
        buildIndexes(from: loadedAirlines)
        hasLoaded = true
        isLoading = false
        loadingError = nil
    }

    private func applyLoadFailure(_ error: Error) {
        airlines = []
        airlinesByID = [:]
        airlinesByIATA = [:]
        airlinesByICAO = [:]
        loadingError = error.localizedDescription
        isLoading = false
        hasLoaded = false
        loadTask = nil

        WanderlustDiagnostics.error(error, category: .performance, message: "AirlineDataLoader failed")
    }

    // MARK: - Search

    func search(
        query: String,
        activeOnly: Bool = true,
        limit: Int = 20
    ) -> [Airline] {
        let queryContainsJapaneseKana = JapaneseKanaRomajiSearch
            .containsJapaneseKana(query)
        let cleanedQueries = JapaneseKanaRomajiSearch.normalizedQueryVariants(
            query,
            normalizer: Self.normalize,
            includeRomajiForKana: !queryContainsJapaneseKana
        )

        guard !cleanedQueries.isEmpty else {
            return []
        }

        return Self.searchAirlines(
            indexedAirlines(matching: cleanedQueries),
            queries: cleanedQueries,
            activeOnly: activeOnly,
            limit: limit
        )
    }

    func suggestions(
        for query: String,
        limit: Int = 8
    ) -> [Airline] {
        search(
            query: query,
            activeOnly: true,
            limit: limit
        )
    }

    func suggestions(
        for query: String,
        limit: Int = 8
    ) async -> [Airline] {
        search(
            query: query,
            activeOnly: true,
            limit: limit
        )
    }

    // MARK: - Lookup

    func airline(
        withID id: String
    ) -> Airline? {
        airlinesByID[
            normalizeKey(id)
        ]
    }

    func airline(
        withIATACode code: String
    ) -> Airline? {
        airlinesByIATA[
            normalizeKey(code)
        ]
    }

    func airline(
        withICAOCode code: String
    ) -> Airline? {
        airlinesByICAO[
            normalizeKey(code)
        ]
    }

    // MARK: - Indexes

    private func buildIndexes(
        from loadedAirlines: [Airline]
    ) {
        airlinesByID = [:]
        airlinesByIATA = [:]
        airlinesByICAO = [:]
        airlineSearchPrefixIndex = [:]

        for airline in loadedAirlines {
            let idKey = normalizeKey(
                airline.id
            )

            if !idKey.isEmpty {
                airlinesByID[idKey] =
                    airline
            }

            let iata =
                airline.normalizedIATACode

            if !iata.isEmpty,
               airlinesByIATA[iata] == nil {
                airlinesByIATA[iata] =
                    airline
            }

            let icao =
                airline.normalizedICAOCode

            if !icao.isEmpty,
               airlinesByICAO[icao] == nil {
                airlinesByICAO[icao] =
                    airline
            }
        }

        var prefixIndex: [String: [Airline]] = [:]
        for airline in loadedAirlines {
            for key in Self.prefixKeys(for: airline.searchableValues) {
                prefixIndex[key, default: []].append(airline)
            }
        }
        airlineSearchPrefixIndex = prefixIndex
    }

    private func indexedAirlines(matching cleanedQueries: [String]) -> [Airline] {
        var candidates: [Airline] = []
        var seenIDs: Set<String> = []

        for cleanedQuery in cleanedQueries {
            let key = Self.prefixKey(for: cleanedQuery)
            for airline in airlineSearchPrefixIndex[key] ?? [] where seenIDs.insert(airline.id).inserted {
                candidates.append(airline)
            }
        }

        return candidates.isEmpty ? airlines : candidates
    }

    // MARK: - Score Adjustment

    private nonisolated static func searchAirlines(
        _ airlines: [Airline],
        queries: [String],
        activeOnly: Bool,
        limit: Int
    ) -> [Airline] {
        let cleanedQueries = queries
            .map(normalize)
            .filter { !$0.isEmpty }

        guard !cleanedQueries.isEmpty else {
            return []
        }

        return airlines
            .filter { airline in
                activeOnly ? airline.isUsableForFlightSearch : true
            }
            .compactMap { airline -> ScoredAirline? in
                let score = cleanedQueries
                    .map { airline.searchScore(for: $0) }
                    .max() ?? 0

                guard score > 0 else {
                    return nil
                }

                return ScoredAirline(
                    airline: airline,
                    score: adjustedScore(
                        for: airline,
                        baseScore: score
                    )
                )
            }
            .sorted { first, second in
                if first.score != second.score {
                    return first.score > second.score
                }

                return first.airline.displayName
                    .localizedCaseInsensitiveCompare(second.airline.displayName) == .orderedAscending
            }
            .reduce(into: ([Airline](), Set<String>())) { acc, scored in
                guard acc.0.count < max(1, limit) else { return }
                let iata = scored.airline.normalizedIATACode
                if !iata.isEmpty {
                    guard acc.1.insert(iata).inserted else { return }
                }
                acc.0.append(scored.airline)
            }
            .0
    }

    private nonisolated static func adjustedScore(
        for airline: Airline,
        baseScore: Int
    ) -> Int {
        var score = baseScore

        if airline.isActive {
            score += 2_000
        }

        if airline.hasValidIATACode {
            score += 1_500
        }

        if !airline.normalizedICAOCode
            .isEmpty {
            score += 500
        }

        let searchRank = AirlineSearchRank.priority(for: airline)
        if searchRank != Int.max {
            score += max(0, 1_200 - min(searchRank, 1_199))
        }

        return score
    }

    // MARK: - Bundle Loading

    private nonisolated static func
        loadAirlinesFromBundle()
        throws -> [Airline] {
        guard let url =
                locateAirlinesFile() else {
            throw AirlineDataLoaderError
                .fileNotFound
        }

        if let cachedAirlines = WanderlustStaticDataCache.loadArray(
            cacheName: "airlines-v2",
            sourceURL: url,
            as: Airline.self
        ), !cachedAirlines.isEmpty {
            return cachedAirlines
        }

        let data = try Data(
            contentsOf: url
        )

        guard !data.isEmpty else {
            throw AirlineDataLoaderError
                .emptyFile
        }

        let decodedAirlines:
            [Airline]

        if isJSONArray(data) {
            decodedAirlines =
                try decodeJSONArray(
                    data
                )
        } else if isJSONObject(data) {
            decodedAirlines =
                try decodeJSONCatalog(
                    data
                )
        } else {
            decodedAirlines =
                try decodeJSONLines(
                    data
                )
        }

        let sanitizedAirlines =
            sanitize(
                decodedAirlines
            )

        guard !sanitizedAirlines
            .isEmpty else {
            throw AirlineDataLoaderError
                .noValidAirlines
        }

        let sortedAirlines = sanitizedAirlines
            .sorted {
                $0.name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(
                        $1.name
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    ) == .orderedAscending
            }

        WanderlustStaticDataCache.saveArray(
            sortedAirlines,
            cacheName: "airlines-v2",
            sourceURL: url
        )

        return sortedAirlines
    }

    private nonisolated static func
        locateAirlinesFile()
        -> URL? {
        let possibleNames = [
            "airlines",
            "airlinesData",
            "airlineData",
            "openflights_airlines",
            "worldAirlines"
        ]

        let possibleExtensions = [
            "json",
            "jsonl",
            "txt"
        ]

        for name in possibleNames {
            for fileExtension in
                possibleExtensions {
                if let url =
                    Bundle.main.url(
                        forResource: name,
                        withExtension:
                            fileExtension
                    ) {
                    return url
                }
            }
        }

        return nil
    }

    // MARK: - JSON Array

    private nonisolated static func
        decodeJSONArray(
            _ data: Data
        ) throws -> [Airline] {
        do {
            return try JSONDecoder()
                .decode(
                    [Airline].self,
                    from: data
                )
        } catch {
            throw AirlineDataLoaderError
                .invalidJSONArray(
                    error.localizedDescription
                )
        }
    }

    private nonisolated static func
        decodeJSONCatalog(
            _ data: Data
        ) throws -> [Airline] {
        do {
            return try JSONDecoder()
                .decode(
                    AirlineCatalogPayload.self,
                    from: data
                )
                .airlines
        } catch {
            throw AirlineDataLoaderError
                .invalidJSONArray(
                    error.localizedDescription
                )
        }
    }

    // MARK: - JSON Lines

    private nonisolated static func
        decodeJSONLines(
            _ data: Data
        ) throws -> [Airline] {
        guard let text = String(
            data: data,
            encoding: .utf8
        ) else {
            throw AirlineDataLoaderError
                .invalidTextEncoding
        }

        let decoder = JSONDecoder()

        var decodedAirlines:
            [Airline] = []

        var invalidLineCount = 0

        for rawLine in text.split(
            whereSeparator: \.isNewline
        ) {
            let line = rawLine
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

            guard !line.isEmpty else {
                continue
            }

            guard let lineData =
                    line.data(
                        using: .utf8
                    ) else {
                invalidLineCount += 1
                continue
            }

            do {
                let airline =
                    try decoder.decode(
                        Airline.self,
                        from: lineData
                    )

                decodedAirlines.append(
                    airline
                )
            } catch {
                invalidLineCount += 1
            }
        }

        if invalidLineCount > 0 {
            WanderlustDiagnostics.warning("AirlineDataLoader skipped \(invalidLineCount) invalid lines", category: .performance)
        }

        return decodedAirlines
    }

    // MARK: - Sanitizing

    private nonisolated static func
        sanitize(
            _ rawAirlines: [Airline]
        ) -> [Airline] {
        var seenKeys =
            Set<String>()

        return rawAirlines.filter {
            airline in

            guard airline
                .isUsableForFlightSearch
            else {
                return false
            }

            let key = [
                airline
                    .normalizedIATACode,
                airline
                    .normalizedICAOCode,
                airline
                    .displayName
                    .lowercased()
            ]
            .joined(separator: "|")

            return seenKeys
                .insert(key)
                .inserted
        }
    }

    // MARK: - JSON Detection

    private nonisolated static func
        isJSONArray(
            _ data: Data
        ) -> Bool {
        for byte in data {
            guard let scalar =
                    UnicodeScalar(
                        Int(byte)
                    ) else {
                continue
            }

            if CharacterSet
                .whitespacesAndNewlines
                .contains(scalar) {
                continue
            }

            return byte ==
                Character("[")
                    .asciiValue
        }

        return false
    }

    private nonisolated static func
        isJSONObject(
            _ data: Data
        ) -> Bool {
        for byte in data {
            guard let scalar =
                    UnicodeScalar(
                        Int(byte)
                    ) else {
                continue
            }

            if CharacterSet
                .whitespacesAndNewlines
                .contains(scalar) {
                continue
            }

            return byte ==
                Character("{")
                    .asciiValue
        }

        return false
    }

    // MARK: - Helpers

    private nonisolated static func normalize(
        _ text: String
    ) -> String {
        SearchNormalizer.normalize(text)
    }

    private nonisolated static func prefixKey(for normalizedValue: String) -> String {
        String(normalizedValue.prefix(min(3, max(1, normalizedValue.count))))
    }

    private nonisolated static func prefixKeys(for values: [String]) -> Set<String> {
        var keys: Set<String> = []
        for value in values {
            let normalized = normalize(value)
            guard !normalized.isEmpty else { continue }
            for length in 1...min(3, normalized.count) {
                keys.insert(String(normalized.prefix(length)))
            }
        }
        return keys
    }

    private func normalizeKey(
        _ text: String
    ) -> String {
        text
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .uppercased()
    }
}

// MARK: - Search Helper

private struct ScoredAirline {
    let airline: Airline
    let score: Int
}

private struct AirlineCatalogPayload: Decodable {
    let airlines: [Airline]

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        airlines = try container.decode([Airline].self, forKey: .airlines)
    }

    private enum CodingKeys: String, CodingKey {
        case airlines
    }
}

// MARK: - Errors

enum AirlineDataLoaderError:
    LocalizedError
{
    case fileNotFound
    case emptyFile
    case invalidTextEncoding
    case invalidJSONArray(String)
    case noValidAirlines

    var errorDescription:
        String? {
        switch self {
        case .fileNotFound:
            return """
            airlines.json was not found in the app bundle.
            Check Target Membership and Copy Bundle Resources.
            """

        case .emptyFile:
            return """
            airlines.json is empty.
            """

        case .invalidTextEncoding:
            return """
            The airline data file is not valid UTF-8.
            """

        case .invalidJSONArray(
            let message
        ):
            return """
            The airline JSON could not be decoded:
            \(message)
            """

        case .noValidAirlines:
            return """
            No active airlines with valid IATA codes were found.
            """
        }
    }
}
