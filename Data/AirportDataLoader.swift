import Foundation
import Combine

@MainActor
final class AirportDataLoader: ObservableObject {
    static let shared = AirportDataLoader()

    @Published private(set)
    var airports: [Airport] = []

    @Published private(set)
    var isLoading = false

    @Published private(set)
    var loadingError: String?

    private var airportsByID: [String: Airport] = [:]
    private var airportsByIATA: [String: Airport] = [:]
    private var airportsByICAO: [String: Airport] = [:]
    private var airportsByCountryCode: [String: [Airport]] = [:]
    private var airportSearchPrefixIndex: [String: [Airport]] = [:]

    private var hasLoaded = false
    private var loadTask: Task<[Airport], Error>?

    private init() {}

    // MARK: - Public Loading

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        await load()
    }

    func reload() async {
        hasLoaded = false

        airports = []
        airportsByID = [:]
        airportsByIATA = [:]
        airportsByICAO = [:]
        airportsByCountryCode = [:]
        airportSearchPrefixIndex = [:]

        await load()
    }

    func releaseMemory() {
        loadTask?.cancel()
        loadTask = nil
        hasLoaded = false
        airports = []
        airportsByID = [:]
        airportsByIATA = [:]
        airportsByICAO = [:]
        airportsByCountryCode = [:]
        airportSearchPrefixIndex = [:]
        isLoading = false
        loadingError = nil
    }

    // MARK: - Main Load

    private func load() async {
        if let loadTask {
            do {
                let loadedAirports = try await loadTask.value
                if !hasLoaded {
                    applyLoadedAirports(loadedAirports)
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
                try Self.loadAirportsFromBundle()
            }
            loadTask = task
            let loadedAirports = try await task.value

            applyLoadedAirports(loadedAirports)

            #if DEBUG
            print(String(format: "[WanderlustPerformance] airports.json %.1fms %d airports", (CFAbsoluteTimeGetCurrent() - start) * 1000, loadedAirports.count))
            #endif
        } catch {
            applyLoadFailure(error)
        }

        loadTask = nil
    }

    private func applyLoadedAirports(_ loadedAirports: [Airport]) {
        airports = loadedAirports
        buildIndexes(from: loadedAirports)
        hasLoaded = true
        isLoading = false
        loadingError = nil
    }

    private func applyLoadFailure(_ error: Error) {
        airports = []
        airportsByID = [:]
        airportsByIATA = [:]
        airportsByICAO = [:]
        airportsByCountryCode = [:]
        airportSearchPrefixIndex = [:]
        loadingError = error.localizedDescription
        isLoading = false
        hasLoaded = false
        loadTask = nil

        WanderlustDiagnostics.error(error, category: .performance, message: "AirportDataLoader failed")
    }

    // MARK: - Search

    func search(
        query: String,
        countryCode: String? = nil,
        commercialOnly: Bool = false,
        limit: Int = 20
    ) -> [Airport] {
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

        let sourceAirports = indexedAirports(
            matching: cleanedQueries,
            countryCode: countryCode
        )

        return Self.searchAirports(
            sourceAirports,
            queries: cleanedQueries,
            commercialOnly: commercialOnly,
            limit: limit
        )
    }

    func suggestions(
        for query: String,
        limit: Int = 10
    ) -> [Airport] {
        search(
            query: query,
            commercialOnly: true,
            limit: limit
        )
    }

    func suggestions(
        for query: String,
        excluding excludedAirportID: String? = nil,
        limit: Int = 10
    ) async -> [Airport] {
        search(
            query: query,
            commercialOnly: true,
            limit: limit + 2
        )
        .filter { airport in
            guard let excludedAirportID else {
                return true
            }

            return airport.id != excludedAirportID
        }
        .prefix(max(1, limit))
        .map { $0 }
    }

    // MARK: - Lookup

    func airport(
        withID id: String
    ) -> Airport? {
        airportsByID[
            normalizeKey(id)
        ]
    }

    func airport(
        withIATACode code: String
    ) -> Airport? {
        airportsByIATA[
            normalizeKey(code)
        ]
    }

    func airport(
        withICAOCode code: String
    ) -> Airport? {
        airportsByICAO[
            normalizeKey(code)
        ]
    }

    func airports(
        inCountryCode countryCode: String
    ) -> [Airport] {
        let normalizedCode = countryCode
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .uppercased()

        return airportsByCountryCode[
            normalizedCode
        ] ?? []
    }

    func commercialAirports(
        inCountryCode countryCode: String
    ) -> [Airport] {
        airports(
            inCountryCode: countryCode
        )
        .filter {
            $0.isCommercialAirport
        }
    }

    func airports(
        nearLatitude latitude: Double,
        longitude: Double,
        limit: Int = 10
    ) -> [Airport] {
        airports
            .filter {
                $0.isCoordinateValid &&
                !$0.isClosed
            }
            .map { airport in
                NearbyAirport(
                    airport: airport,
                    distanceSquared:
                        distanceSquared(
                            latitude1: latitude,
                            longitude1: longitude,
                            latitude2: airport.latitude,
                            longitude2: airport.longitude
                        )
                )
            }
            .sorted {
                $0.distanceSquared <
                $1.distanceSquared
            }
            .prefix(max(1, limit))
            .map {
                $0.airport
            }
    }

    // MARK: - Indexes

    private func buildIndexes(
        from loadedAirports: [Airport]
    ) {
        airportsByID = [:]
        airportsByIATA = [:]
        airportsByICAO = [:]

        // Sort by quality so IATA/ICAO lookups prefer the best airport for each code
        let prioritized = loadedAirports.sorted { a, b in
            let aPriority = AirportSearchRank.priority(for: a)
            let bPriority = AirportSearchRank.priority(for: b)
            if aPriority != bPriority { return aPriority < bPriority }
            if a.isCommercialAirport != b.isCommercialAirport { return a.isCommercialAirport }
            if a.scheduledService != b.scheduledService { return a.scheduledService }
            if a.isLargeAirport != b.isLargeAirport { return a.isLargeAirport }
            return a.isMediumAirport && !b.isMediumAirport
        }

        for airport in prioritized {
            airportsByID[
                normalizeKey(airport.id)
            ] = airport

            let iata = airport.normalizedIATACode

            if !iata.isEmpty,
               airportsByIATA[iata] == nil {
                airportsByIATA[iata] = airport
            }

            let icao = airport.normalizedICAOCode

            if !icao.isEmpty,
               airportsByICAO[icao] == nil {
                airportsByICAO[icao] = airport
            }
        }

        airportsByCountryCode = Dictionary(
            grouping: loadedAirports
        ) { airport in
            airport.normalizedCountryCode
        }

        for countryCode in
            airportsByCountryCode.keys {
            airportsByCountryCode[
                countryCode
            ]?.sort {
                let firstPriority = AirportSearchRank.priority(for: $0)
                let secondPriority = AirportSearchRank.priority(for: $1)
                if firstPriority != secondPriority {
                    return firstPriority < secondPriority
                }

                if $0.isCommercialAirport !=
                    $1.isCommercialAirport {
                    return $0.isCommercialAirport
                }

                if $0.isLargeAirport !=
                    $1.isLargeAirport {
                    return $0.isLargeAirport
                }

                if $0.isMediumAirport !=
                    $1.isMediumAirport {
                    return $0.isMediumAirport
                }

                return $0.displayTitle
                    .localizedCaseInsensitiveCompare(
                        $1.displayTitle
                    ) == .orderedAscending
            }
        }

        var prefixIndex: [String: [Airport]] = [:]
        for airport in loadedAirports {
            for key in Self.prefixKeys(for: airport.searchableValues) {
                prefixIndex[key, default: []].append(airport)
            }
        }
        airportSearchPrefixIndex = prefixIndex
    }

    private func indexedAirports(matching cleanedQueries: [String], countryCode: String?) -> [Airport] {
        var candidates: [Airport] = []
        var seenIDs: Set<String> = []

        for cleanedQuery in cleanedQueries {
            let key = Self.prefixKey(for: cleanedQuery)
            for airport in airportSearchPrefixIndex[key] ?? [] where seenIDs.insert(airport.id).inserted {
                candidates.append(airport)
            }
        }

        if candidates.isEmpty {
            candidates = airports
        }

        guard let countryCode,
              !countryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return candidates
        }

        let normalizedCountry = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return candidates.filter { $0.normalizedCountryCode == normalizedCountry }
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

    // MARK: - Score Adjustment

    private nonisolated static func searchAirports(
        _ airports: [Airport],
        queries: [String],
        commercialOnly: Bool,
        limit: Int
    ) -> [Airport] {
        let cleanedQueries = queries
            .map(normalize)
            .filter { !$0.isEmpty }

        guard !cleanedQueries.isEmpty else {
            return []
        }

        let sorted = airports
            .filter { airport in
                commercialOnly ? airport.isCommercialAirport : true
            }
            .compactMap { airport -> ScoredAirport? in
                let score = cleanedQueries
                    .map { airport.searchScore(for: $0) }
                    .max() ?? 0

                guard score > 0 else {
                    return nil
                }

                return ScoredAirport(
                    airport: airport,
                    score: adjustedScore(
                        for: airport,
                        baseScore: score
                    )
                )
            }
            .sorted { first, second in
                if first.score != second.score {
                    return first.score > second.score
                }

                if first.airport.isCommercialAirport != second.airport.isCommercialAirport {
                    return first.airport.isCommercialAirport
                }

                let firstPriority = AirportSearchRank.priority(for: first.airport)
                let secondPriority = AirportSearchRank.priority(for: second.airport)
                if firstPriority != secondPriority {
                    return firstPriority < secondPriority
                }

                if first.airport.isLargeAirport != second.airport.isLargeAirport {
                    return first.airport.isLargeAirport
                }

                return first.airport.displayTitle
                    .localizedCaseInsensitiveCompare(second.airport.displayTitle) == .orderedAscending
            }

        var seenAirportIDs: Set<String> = []
        var seenIATACodes: Set<String> = []
        var results: [Airport] = []
        for entry in sorted {
            guard seenAirportIDs.insert(entry.airport.id).inserted else { continue }
            let iata = entry.airport.normalizedIATACode
            if !iata.isEmpty {
                guard seenIATACodes.insert(iata).inserted else { continue }
            }
            results.append(entry.airport)
            if results.count >= max(1, limit) { break }
        }
        return results
    }

    private nonisolated static func adjustedScore(
        for airport: Airport,
        baseScore: Int
    ) -> Int {
        var score = baseScore

        let passengerPriority = AirportSearchRank.priority(for: airport)
        if passengerPriority != Int.max {
            score += max(0, 5_000 - passengerPriority * 50)
        }

        if airport.isCommercialAirport {
            score += 2_000
        }

        if airport.isLargeAirport {
            score += 1_500
        } else if airport.isMediumAirport {
            score += 1_000
        } else if airport.isSmallAirport {
            score += 200
        }

        if airport.scheduledService {
            score += 1_000
        }

        if !airport.normalizedIATACode.isEmpty {
            score += 700
        }

        if airport.isClosed {
            score -= 10_000
        }

        return score
    }

    // MARK: - Bundle Loading

    private nonisolated static func
        loadAirportsFromBundle()
        throws -> [Airport] {
        guard let url = locateAirportsFile() else {
            throw AirportDataLoaderError
                .fileNotFound
        }

        if let cachedAirports = WanderlustStaticDataCache.loadArray(
            cacheName: "airports-v1",
            sourceURL: url,
            as: Airport.self
        ), !cachedAirports.isEmpty {
            return cachedAirports
        }

        let fileExtension = url
            .pathExtension
            .lowercased()

        let loadedAirports: [Airport]

        switch fileExtension {
        case "csv":
            loadedAirports = try decodeCSV(
                from: url
            )

        default:
            let data = try Data(
                contentsOf: url
            )

            guard !data.isEmpty else {
                throw AirportDataLoaderError
                    .emptyFile
            }

            if isJSONArray(data) {
                loadedAirports =
                    try decodeJSONArray(
                        data
                    )
            } else if isJSONObject(data) {
                loadedAirports =
                    try decodeJSONCatalogOrDictionary(
                        data
                    )
            } else {
                loadedAirports =
                    try decodeJSONLines(
                        data
                    )
            }
        }

        let validAirports = sanitize(
            loadedAirports
        )

        guard !validAirports.isEmpty else {
            throw AirportDataLoaderError
                .noValidAirports
        }

        WanderlustStaticDataCache.saveArray(
            validAirports,
            cacheName: "airports-v1",
            sourceURL: url
        )

        return validAirports
    }

    private nonisolated static func
        locateAirportsFile() -> URL? {
        let possibleNames = [
            "airports",
            "airportsData",
            "airportData",
            "worldAirports",
            "ourairports",
            "airports_large"
        ]

        let possibleExtensions = [
            "json",
            "jsonl",
            "txt",
            "csv"
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
        ) throws -> [Airport] {
        do {
            return try JSONDecoder()
                .decode(
                    [Airport].self,
                    from: data
                )
        } catch {
            throw AirportDataLoaderError
                .invalidJSONArray(
                    error.localizedDescription
                )
        }
    }

    private nonisolated static func
        decodeJSONCatalogOrDictionary(
            _ data: Data
        ) throws -> [Airport] {
        do {
            let catalog = try JSONDecoder()
                .decode(
                    AirportCatalogPayload.self,
                    from: data
                )

            return catalog.airports
        } catch {
            do {
                let decoded = try JSONDecoder()
                    .decode(
                        [String: Airport].self,
                        from: data
                    )

                return Array(decoded.values)
            } catch {
                throw AirportDataLoaderError
                    .invalidJSONArray(
                        error.localizedDescription
                    )
            }
        }
    }

    // MARK: - JSON Lines

    private nonisolated static func
        decodeJSONLines(
            _ data: Data
        ) throws -> [Airport] {
        guard let text = String(
            data: data,
            encoding: .utf8
        ) else {
            throw AirportDataLoaderError
                .invalidTextEncoding
        }

        let decoder = JSONDecoder()

        var decodedAirports: [Airport] = []
        decodedAirports.reserveCapacity(
            80_000
        )

        var invalidLineCount = 0

        for rawLine in text.split(
            whereSeparator: \.isNewline
        ) {
            let line = rawLine
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
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
                let airport =
                    try decoder.decode(
                        Airport.self,
                        from: lineData
                    )

                decodedAirports.append(
                    airport
                )
            } catch {
                invalidLineCount += 1
            }
        }

        if invalidLineCount > 0 {
            WanderlustDiagnostics.warning("AirportDataLoader skipped \(invalidLineCount) invalid JSON lines", category: .performance)
        }

        return decodedAirports
    }

    // MARK: - CSV

    private nonisolated static func
        decodeCSV(
            from url: URL
        ) throws -> [Airport] {
        let text = try String(
            contentsOf: url,
            encoding: .utf8
        )

        let rows = text.split(
            whereSeparator: \.isNewline
        )

        guard let headerRow = rows.first else {
            throw AirportDataLoaderError
                .emptyFile
        }

        let headers = parseCSVRow(
            String(headerRow)
        )
        .map {
            normalizeHeader($0)
        }

        var decodedAirports: [Airport] = []
        decodedAirports.reserveCapacity(
            rows.count
        )

        for row in rows.dropFirst() {
            let values = parseCSVRow(
                String(row)
            )

            guard !values.isEmpty else {
                continue
            }

            var dictionary: [String: String] = [:]

            for index in headers.indices {
                guard values.indices.contains(
                    index
                ) else {
                    continue
                }

                dictionary[
                    headers[index]
                ] = values[index]
            }

            if let airport = airport(
                fromCSV: dictionary
            ) {
                decodedAirports.append(
                    airport
                )
            }
        }

        return decodedAirports
    }

    private nonisolated static func
        airport(
            fromCSV values: [String: String]
        ) -> Airport? {
        let id = firstValue(
            in: values,
            keys: [
                "id",
                "_id",
                "ident"
            ]
        )

        let ident = firstValue(
            in: values,
            keys: [
                "ident",
                "icao",
                "icao_code",
                "gps_code"
            ]
        )

        let name = firstValue(
            in: values,
            keys: [
                "name"
            ]
        )

        guard !name.isEmpty else {
            return nil
        }

        let latitude = firstDouble(
            in: values,
            keys: [
                "latitude_deg",
                "latitude",
                "lat"
            ]
        )

        let longitude = firstDouble(
            in: values,
            keys: [
                "longitude_deg",
                "longitude",
                "lon",
                "lng"
            ]
        )

        guard let latitude,
              let longitude else {
            return nil
        }

        let scheduledValue = firstValue(
            in: values,
            keys: [
                "scheduled_service",
                "scheduled"
            ]
        )
        .lowercased()

        let scheduledService = [
            "yes",
            "true",
            "1",
            "y"
        ]
        .contains(scheduledValue)

        return Airport(
            id: id.isEmpty
                ? ident
                : id,
            ident: ident,
            type: firstValue(
                in: values,
                keys: ["type"]
            ),
            name: name,
            latitude: latitude,
            longitude: longitude,
            elevationFeet: firstInt(
                in: values,
                keys: [
                    "elevation_ft",
                    "elevation"
                ]
            ),
            continent: firstValue(
                in: values,
                keys: ["continent"]
            ),
            countryCode: firstValue(
                in: values,
                keys: [
                    "iso_country",
                    "country_code",
                    "country"
                ]
            ),
            regionCode: firstValue(
                in: values,
                keys: [
                    "iso_region",
                    "region_code",
                    "region"
                ]
            ),
            municipality: firstValue(
                in: values,
                keys: [
                    "municipality",
                    "city"
                ]
            ),
            scheduledService:
                scheduledService,
            gpsCode: firstValue(
                in: values,
                keys: [
                    "gps_code",
                    "icao_code",
                    "icao"
                ]
            ),
            iataCode: firstValue(
                in: values,
                keys: [
                    "iata_code",
                    "iata"
                ]
            ),
            localCode: firstValue(
                in: values,
                keys: [
                    "local_code"
                ]
            ),
            timezone: firstValue(
                in: values,
                keys: [
                    "timezone",
                    "tz"
                ]
            )
        )
    }

    // MARK: - Sanitizing

    private nonisolated static func
        sanitize(
            _ rawAirports: [Airport]
        ) -> [Airport] {
        var seenIDs = Set<String>()

        return rawAirports.filter { airport in
            guard !airport.displayName.isEmpty else {
                return false
            }

            guard airport.isCoordinateValid else {
                return false
            }

            guard !airport.isClosed else {
                return false
            }

            let uniqueKey = [
                airport.id,
                airport.ident,
                airport.normalizedIATACode,
                String(airport.latitude),
                String(airport.longitude)
            ]
            .joined(separator: "|")
            .lowercased()

            return seenIDs
                .insert(uniqueKey)
                .inserted
        }
    }

    // MARK: - JSON Detection

    private nonisolated static func
        isJSONArray(
            _ data: Data
        ) -> Bool {
        guard let firstByte =
                data.first(
                    where: { byte in
                        guard let scalar =
                                UnicodeScalar(
                                    Int(byte)
                                ) else {
                            return false
                        }

                        return !CharacterSet
                            .whitespacesAndNewlines
                            .contains(scalar)
                    }
                ) else {
            return false
        }

        return firstByte ==
            Character("[")
                .asciiValue
    }

    private nonisolated static func
        isJSONObject(
            _ data: Data
        ) -> Bool {
        guard let firstByte =
                data.first(
                    where: { byte in
                        guard let scalar =
                                UnicodeScalar(
                                    Int(byte)
                                ) else {
                            return false
                        }

                        return !CharacterSet
                            .whitespacesAndNewlines
                            .contains(scalar)
                    }
                ) else {
            return false
        }

        return firstByte ==
            Character("{")
                .asciiValue
    }

    // MARK: - CSV Helpers

    private nonisolated static func
        parseCSVRow(
            _ row: String
        ) -> [String] {
        var values: [String] = []
        var currentValue = ""
        var isInsideQuotes = false

        var index = row.startIndex

        while index < row.endIndex {
            let character = row[index]

            if character == "\"" {
                let nextIndex =
                    row.index(
                        after: index
                    )

                if isInsideQuotes,
                   nextIndex < row.endIndex,
                   row[nextIndex] == "\"" {
                    currentValue.append("\"")
                    index = nextIndex
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == ",",
                      !isInsideQuotes {
                values.append(
                    currentValue
                )
                currentValue = ""
            } else {
                currentValue.append(
                    character
                )
            }

            index = row.index(
                after: index
            )
        }

        values.append(
            currentValue
        )

        return values.map {
            $0.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }
    }

    private nonisolated static func
        normalizeHeader(
            _ value: String
        ) -> String {
        value
            .trimmingCharacters(
                in: CharacterSet(
                    charactersIn:
                        "\" "
                )
            )
            .lowercased()
    }

    private nonisolated static func
        firstValue(
            in values: [String: String],
            keys: [String]
        ) -> String {
        for key in keys {
            if let value = values[key],
               !value
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty {
                return value
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
            }
        }

        return ""
    }

    private nonisolated static func
        firstDouble(
            in values: [String: String],
            keys: [String]
        ) -> Double? {
        let value = firstValue(
            in: values,
            keys: keys
        )

        return Double(value)
    }

    private nonisolated static func
        firstInt(
            in values: [String: String],
            keys: [String]
        ) -> Int? {
        let value = firstValue(
            in: values,
            keys: keys
        )

        if let integer = Int(value) {
            return integer
        }

        if let double = Double(value) {
            return Int(double)
        }

        return nil
    }

    // MARK: - General Helpers

    private nonisolated static func normalize(
        _ text: String
    ) -> String {
        SearchNormalizer.normalize(text)
    }

    private func normalizeKey(
        _ text: String
    ) -> String {
        text
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .uppercased()
    }

    private func distanceSquared(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double {
        let latitudeDifference =
            latitude2 - latitude1

        let longitudeDifference =
            longitude2 - longitude1

        return
            latitudeDifference *
            latitudeDifference +
            longitudeDifference *
            longitudeDifference
    }
}

// MARK: - Search Helpers

private struct ScoredAirport {
    let airport: Airport
    let score: Int
}

private struct AirportCatalogPayload: Decodable {
    let airports: [Airport]

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        airports = try container.decode([Airport].self, forKey: .airports)
    }

    private enum CodingKeys: String, CodingKey {
        case airports
    }
}

private struct NearbyAirport {
    let airport: Airport
    let distanceSquared: Double
}

// MARK: - Errors

enum AirportDataLoaderError: LocalizedError {
    case fileNotFound
    case emptyFile
    case invalidTextEncoding
    case invalidJSONArray(String)
    case noValidAirports

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return """
            The airport data file was not found in the app bundle.
            Check Target Membership and Copy Bundle Resources.
            """

        case .emptyFile:
            return """
            The airport data file is empty.
            """

        case .invalidTextEncoding:
            return """
            The airport data file is not valid UTF-8 text.
            """

        case .invalidJSONArray(
            let message
        ):
            return """
            The airport JSON array could not be decoded:
            \(message)
            """

        case .noValidAirports:
            return """
            No valid airport records were found in the airport data file.
            """
        }
    }
}//
//  AirportDataLoader.swift
//  Wanderlust
//
//  Created by Yusei Sakurai on 2026/07/12.
//
