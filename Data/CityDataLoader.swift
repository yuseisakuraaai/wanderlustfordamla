import Foundation
import Combine

@MainActor
final class CityDataLoader: ObservableObject {
    static let shared = CityDataLoader()

    @Published private(set) var cities: [WanderlustCity] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingError: String?

    private var citiesByID: [Int: WanderlustCity] = [:]
    private var citiesByCountryCode: [String: [WanderlustCity]] = [:]
    private var citySearchPrefixIndex: [String: [WanderlustCity]] = [:]
    private var countryScopedCitiesByCode: [String: [WanderlustCity]] = [:]

    private var hasLoaded = false
    private var loadTask: Task<LoadedCityData, Error>?
    private var countryLoadTasks: [String: Task<[WanderlustCity], Error>] = [:]

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
        cities = []
        citiesByID = [:]
        citiesByCountryCode = [:]
        citySearchPrefixIndex = [:]
        countryScopedCitiesByCode = [:]

        await load()
    }

    func releaseMemory() {
        loadTask?.cancel()
        loadTask = nil
        countryLoadTasks.values.forEach { $0.cancel() }
        countryLoadTasks = [:]
        hasLoaded = false
        cities = []
        citiesByID = [:]
        citiesByCountryCode = [:]
        citySearchPrefixIndex = [:]
        countryScopedCitiesByCode = [:]
        isLoading = false
        loadingError = nil
    }

    func prepareSearch(countryCode: String?) async {
        guard let countryCode,
              !countryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        _ = await loadCountryCitiesIfNeeded(countryCode)
    }

    // MARK: - Main Load

    private func load() async {
        if let loadTask {
            do {
                let loadedData = try await loadTask.value
                if !hasLoaded {
                    applyLoadedCities(loadedData)
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
                let loadedCities = try Self.loadCitiesFromBundle()
                return Self.loadedData(from: loadedCities)
            }
            loadTask = task
            let loadedData = try await task.value

            applyLoadedCities(loadedData)

            #if DEBUG
            print(String(format: "[WanderlustPerformance] cities15000.json %.1fms %d cities", (CFAbsoluteTimeGetCurrent() - start) * 1000, loadedData.cities.count))
            #endif
        } catch {
            applyLoadFailure(error)
        }

        loadTask = nil
    }

    private func applyLoadedCities(_ loadedData: LoadedCityData) {
        cities = loadedData.cities
        citiesByID = loadedData.citiesByID
        citiesByCountryCode = loadedData.citiesByCountryCode
        citySearchPrefixIndex = loadedData.citySearchPrefixIndex
        hasLoaded = true
        isLoading = false
        loadingError = nil
    }

    private func applyLoadFailure(_ error: Error) {
        cities = []
        citiesByID = [:]
        citiesByCountryCode = [:]
        citySearchPrefixIndex = [:]
        loadingError = error.localizedDescription
        isLoading = false
        hasLoaded = false
        loadTask = nil

        WanderlustDiagnostics.error(error, category: .performance, message: "CityDataLoader failed")
    }

    private func loadCountryCitiesIfNeeded(_ countryCode: String) async -> [WanderlustCity] {
        let normalizedCountry = countryCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalizedCountry.isEmpty else {
            return []
        }

        if hasLoaded {
            return cities(in: normalizedCountry)
        }

        if let cachedCities = countryScopedCitiesByCode[normalizedCountry] {
            return cachedCities
        }

        if let task = countryLoadTasks[normalizedCountry] {
            do {
                let loadedCities = try await task.value
                countryScopedCitiesByCode[normalizedCountry] = loadedCities
                countryLoadTasks[normalizedCountry] = nil
                return loadedCities
            } catch {
                countryLoadTasks[normalizedCountry] = nil
                return await loadCountryFallback(normalizedCountry, error: error)
            }
        }

        let task = Task.detached(priority: .userInitiated) {
            try Self.loadCitiesFromBundle(countryCode: normalizedCountry)
        }
        countryLoadTasks[normalizedCountry] = task

        do {
            let loadedCities = try await task.value
            countryScopedCitiesByCode[normalizedCountry] = loadedCities
            countryLoadTasks[normalizedCountry] = nil
            return loadedCities
        } catch {
            countryLoadTasks[normalizedCountry] = nil
            return await loadCountryFallback(normalizedCountry, error: error)
        }
    }

    private func loadCountryFallback(_ countryCode: String, error: Error) async -> [WanderlustCity] {
        WanderlustDiagnostics.warning(
            "Country-scoped city load unavailable: \(error.localizedDescription)",
            category: .search
        )
        await loadIfNeeded()
        return cities(in: countryCode)
    }

    // MARK: - Search

    func search(
        query: String,
        countryCode: String? = nil,
        limit: Int = 20
    ) -> [WanderlustCity] {
        let queryContainsJapaneseKana = JapaneseKanaRomajiSearch
            .containsJapaneseKana(query)
        let cleanedQueries = JapaneseKanaRomajiSearch.normalizedQueryVariants(
            query,
            normalizer: Self.normalize,
            includeRomajiForKana: true
        )

        guard let cleanedQuery = cleanedQueries.first else {
            return []
        }

        let sourceCities = indexedCities(
            matching: cleanedQueries,
            countryCode: countryCode,
            allowsKanaInfix: queryContainsJapaneseKana
        )

        return Self.scoredSearchResults(
            from: sourceCities,
            cleanedQuery: cleanedQuery,
            limit: limit
        )
    }

    func searchOffMain(
        query: String,
        countryCode: String? = nil,
        limit: Int = 20
    ) async -> [WanderlustCity] {
        let queryContainsJapaneseKana = JapaneseKanaRomajiSearch
            .containsJapaneseKana(query)
        let cleanedQueries = JapaneseKanaRomajiSearch.normalizedQueryVariants(
            query,
            normalizer: Self.normalize,
            includeRomajiForKana: true
        )

        guard let cleanedQuery = cleanedQueries.first else {
            return []
        }

        let sourceCities: [WanderlustCity]
        if let countryCode,
           !countryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !hasLoaded {
            sourceCities = await loadCountryCitiesIfNeeded(countryCode)
        } else {
            sourceCities = indexedCities(
                matching: cleanedQueries,
                countryCode: countryCode,
                allowsKanaInfix: queryContainsJapaneseKana
            )
        }

        return await Task.detached(priority: .userInitiated) {
            Self.scoredSearchResults(
                from: sourceCities,
                cleanedQuery: cleanedQuery,
                limit: limit
            )
        }.value
    }

    func suggestions(
        for query: String,
        limit: Int = 10
    ) -> [WanderlustCity] {
        search(
            query: query,
            limit: limit
        )
    }

    // MARK: - Lookup

    func city(
        withID id: Int
    ) -> WanderlustCity? {
        citiesByID[id]
    }

    func cities(
        inCountryCode countryCode: String
    ) -> [WanderlustCity] {
        let normalizedCode = countryCode
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .uppercased()

        return citiesByCountryCode[
            normalizedCode
        ] ?? []
    }

    func mostPopulatedCities(
        inCountryCode countryCode: String,
        limit: Int = 20
    ) -> [WanderlustCity] {
        Array(
            cities(
                inCountryCode: countryCode
            )
            .sorted {
                $0.population > $1.population
            }
            .prefix(max(1, limit))
        )
    }

    // MARK: - Indexes

    private nonisolated static func loadedData(
        from loadedCities: [WanderlustCity]
    ) -> LoadedCityData {
        let citiesByID = Dictionary(
            uniqueKeysWithValues:
                loadedCities.map {
                    ($0.id, $0)
                }
        )

        var citiesByCountryCode = Dictionary(
            grouping: loadedCities
        ) { city in
            city.normalizedCountryCode
        }

        for countryCode in
            citiesByCountryCode.keys {
            citiesByCountryCode[
                countryCode
            ]?.sort {
                let firstDemandRank = CityTravelDemandRank.priority(for: $0)
                let secondDemandRank = CityTravelDemandRank.priority(for: $1)
                if firstDemandRank != secondDemandRank {
                    return firstDemandRank < secondDemandRank
                }

                if $0.population !=
                    $1.population {
                    return $0.population >
                        $1.population
                }

                return $0.displayName
                    .localizedCaseInsensitiveCompare(
                        $1.displayName
                    ) == .orderedAscending
            }
        }

        var prefixIndex: [String: [WanderlustCity]] = [:]
        for city in loadedCities {
            for key in prefixKeys(for: city.searchableNames) {
                prefixIndex[key, default: []].append(city)
            }
        }

        return LoadedCityData(
            cities: loadedCities,
            citiesByID: citiesByID,
            citiesByCountryCode: citiesByCountryCode,
            citySearchPrefixIndex: prefixIndex
        )
    }

    private func indexedCities(
        matching cleanedQueries: [String],
        countryCode: String?,
        allowsKanaInfix: Bool = false
    ) -> [WanderlustCity] {
        if allowsKanaInfix {
            return cities(in: countryCode)
        }

        var candidates: [WanderlustCity] = []
        var seenIDs: Set<Int> = []

        for cleanedQuery in cleanedQueries {
            let key = Self.prefixKey(for: cleanedQuery)
            for city in citySearchPrefixIndex[key] ?? [] where seenIDs.insert(city.id).inserted {
                candidates.append(city)
            }
        }

        if candidates.isEmpty {
            candidates = cities
        }

        guard let countryCode,
              !countryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return candidates
        }

        let normalizedCountry = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return candidates.filter { $0.normalizedCountryCode == normalizedCountry }
    }

    private func cities(in countryCode: String?) -> [WanderlustCity] {
        guard let countryCode,
              !countryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return cities
        }

        let normalizedCountry = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return citiesByCountryCode[normalizedCountry] ?? []
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

    private nonisolated static func scoredSearchResults(
        from sourceCities: [WanderlustCity],
        cleanedQuery: String,
        limit: Int
    ) -> [WanderlustCity] {
        sourceCities
            .compactMap { city -> ScoredCity? in
                let score = city.searchScore(for: cleanedQuery)

                guard score > 0 else {
                    return nil
                }

                return ScoredCity(city: city, score: score)
            }
            .sorted { first, second in
                if first.score != second.score {
                    return first.score > second.score
                }

                let firstDemandRank = CityTravelDemandRank.priority(
                    for: first.city
                )
                let secondDemandRank = CityTravelDemandRank.priority(
                    for: second.city
                )
                if firstDemandRank != secondDemandRank {
                    return firstDemandRank < secondDemandRank
                }

                if first.city.population != second.city.population {
                    return first.city.population > second.city.population
                }

                return first.city.name.localizedCaseInsensitiveCompare(
                    second.city.name
                ) == .orderedAscending
            }
            .prefix(max(1, limit))
            .map { $0.city }
    }

    // MARK: - Bundle Loading

    private nonisolated static func
        loadCitiesFromBundle()
        throws -> [WanderlustCity] {
        guard let url = locateCitiesFile() else {
            throw CityDataLoaderError
                .fileNotFound
        }

        if let cachedCities = WanderlustStaticDataCache.loadArray(
            cacheName: "cities15000-v1",
            sourceURL: url,
            as: WanderlustCity.self
        ), !cachedCities.isEmpty {
            return cachedCities
        }

        let data = try Data(
            contentsOf: url
        )

        guard !data.isEmpty else {
            throw CityDataLoaderError
                .emptyFile
        }

        let cities: [WanderlustCity]

        if isJSONArray(data) {
            cities = try decodeJSONArray(
                data
            )
        } else if isJSONObject(data) {
            cities = try decodeJSONCatalog(
                data
            )
        } else {
            cities = try decodeJSONLines(
                data
            )
        }

        let validCities = sanitize(
            cities
        )

        guard !validCities.isEmpty else {
            throw CityDataLoaderError
                .noValidCities
        }

        WanderlustStaticDataCache.saveArray(
            validCities,
            cacheName: "cities15000-v1",
            sourceURL: url
        )

        return validCities
    }

    private nonisolated static func loadCitiesFromBundle(countryCode: String) throws -> [WanderlustCity] {
        guard let url = locateCitiesFile() else {
            throw CityDataLoaderError.fileNotFound
        }

        let normalizedCountry = countryCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalizedCountry.isEmpty else {
            return []
        }

        if let cachedCities = WanderlustStaticDataCache.loadArray(
            cacheName: "cities-\(normalizedCountry)-v1",
            sourceURL: url,
            as: WanderlustCity.self
        ) {
            return cachedCities
        }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CityDataLoaderError.invalidTextEncoding
        }

        let cities = try decodeCountryCities(
            from: text,
            countryCode: normalizedCountry
        )
        let validCities = sanitize(cities)

        WanderlustStaticDataCache.saveArray(
            validCities,
            cacheName: "cities-\(normalizedCountry)-v1",
            sourceURL: url
        )

        return validCities
    }

    private nonisolated static func decodeCountryCities(
        from text: String,
        countryCode: String
    ) throws -> [WanderlustCity] {
        let countryPattern = "\"countryISO2\":\"\(countryCode)\""
        guard let firstCountryRange = text.range(of: countryPattern) else {
            return []
        }

        var searchIndex = objectStartIndex(before: firstCountryRange.lowerBound, in: text)
        var objectTexts: [Substring] = []

        while let objectRange = nextJSONObjectRange(startingAt: searchIndex, in: text) {
            let objectText = text[objectRange]
            guard objectText.contains(countryPattern) else {
                if !objectTexts.isEmpty {
                    break
                }
                searchIndex = objectRange.upperBound
                continue
            }

            objectTexts.append(objectText)
            searchIndex = objectRange.upperBound
        }

        guard !objectTexts.isEmpty else {
            return []
        }

        let arrayText = "[\(objectTexts.joined(separator: ","))]"
        guard let arrayData = arrayText.data(using: .utf8) else {
            throw CityDataLoaderError.invalidTextEncoding
        }

        return try decodeJSONArray(arrayData)
    }

    private nonisolated static func objectStartIndex(
        before index: String.Index,
        in text: String
    ) -> String.Index {
        var current = index
        while current > text.startIndex {
            current = text.index(before: current)
            if text[current] == "{" {
                return current
            }
        }
        return text.startIndex
    }

    private nonisolated static func nextJSONObjectRange(
        startingAt startIndex: String.Index,
        in text: String
    ) -> Range<String.Index>? {
        guard let objectStart = text[startIndex...].firstIndex(of: "{") else {
            return nil
        }

        var index = objectStart
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return objectStart..<text.index(after: index)
                    }
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private nonisolated static func
        locateCitiesFile() -> URL? {
        let possibleNames = [
            "cities15000",
            "cities",
            "worldCities",
            "world_cities"
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
        ) throws -> [WanderlustCity] {
        do {
            return try JSONDecoder()
                .decode(
                    [WanderlustCity].self,
                    from: data
                )
        } catch {
            throw CityDataLoaderError
                .invalidJSONArray(
                    error.localizedDescription
                )
        }
    }

    private nonisolated static func
        decodeJSONCatalog(
            _ data: Data
        ) throws -> [WanderlustCity] {
        do {
            return try JSONDecoder()
                .decode(
                    CityCatalogPayload.self,
                    from: data
                )
                .cities
        } catch {
            throw CityDataLoaderError
                .invalidJSONArray(
                    error.localizedDescription
                )
        }
    }

    // MARK: - JSON Lines

    private nonisolated static func
        decodeJSONLines(
            _ data: Data
        ) throws -> [WanderlustCity] {
        guard let text = String(
            data: data,
            encoding: .utf8
        ) else {
            throw CityDataLoaderError
                .invalidTextEncoding
        }

        let decoder = JSONDecoder()

        var decodedCities: [WanderlustCity] = []
        decodedCities.reserveCapacity(
            25_000
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
                let city =
                    try decoder.decode(
                        WanderlustCity.self,
                        from: lineData
                    )

                decodedCities.append(city)
            } catch {
                invalidLineCount += 1
            }
        }

        if invalidLineCount > 0 {
            WanderlustDiagnostics.warning("CityDataLoader skipped \(invalidLineCount) invalid lines", category: .performance)
        }

        return decodedCities
    }

    // MARK: - Sanitizing

    private nonisolated static func
        sanitize(
            _ rawCities: [WanderlustCity]
        ) -> [WanderlustCity] {
        var seenIDs = Set<Int>()

        return rawCities.filter { city in
            guard city.id > 0 else {
                return false
            }

            guard !city.displayName.isEmpty else {
                return false
            }

            guard !city
                .normalizedCountryCode
                .isEmpty else {
                return false
            }

            guard city.location.isValid else {
                return false
            }

            return seenIDs
                .insert(city.id)
                .inserted
        }
    }

    // MARK: - Helpers

    private nonisolated static func
        isJSONArray(
            _ data: Data
        ) -> Bool {
        guard let firstByte =
                data.first(
                    where: {
                        !CharacterSet
                            .whitespacesAndNewlines
                            .contains(
                                UnicodeScalar($0)
                            )
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
                    where: {
                        !CharacterSet
                            .whitespacesAndNewlines
                            .contains(
                                UnicodeScalar($0)
                            )
                    }
                ) else {
            return false
        }

        return firstByte ==
            Character("{")
                .asciiValue
    }

    private nonisolated static func normalize(
        _ text: String
    ) -> String {
        SearchNormalizer.normalize(text)
    }
}

// MARK: - Search Helper

private struct ScoredCity {
    let city: WanderlustCity
    let score: Int
}

private enum CityTravelDemandRank {
    nonisolated static func priority(
        for city: WanderlustCity
    ) -> Int {
        if let explicitPriority = explicitPriorities[city.id] {
            return explicitPriority
        }

        switch city.featureCode {
        case "PPLC":
            return 300
        case "PPLA":
            return 350
        case "PPLA2":
            return 450
        case "PPLA3":
            return 550
        default:
            return 700
        }
    }

    nonisolated private static let explicitPriorities: [Int: Int] = [
        // Japan major destinations
        1853909: 20, // Osaka
        1857910: 25, // Kyoto
        1848354: 30, // Yokohama
        2128295: 35, // Sapporo
        1863967: 40, // Fukuoka
        1856035: 45, // Naha
        1862415: 50, // Hiroshima
        1855612: 55, // Nara

        // Tokyo special wards and compact travel hubs
        11790353: 60, // Shinjuku
        11808021: 61, // Shibuya
        13353696: 62, // Minato
        11749713: 63, // Chiyoda
        13353695: 64, // Chuo
        11790369: 65, // Taito
        900100002: 66, // Shinagawa
        900100001: 67, // Koto
        900100003: 68, // Nerima

        // Curated small travel destinations
        900200001: 80, // Hakone
        900200002: 81, // Niseko
        900200003: 82, // Biei
        900200004: 83, // Toyako
        900200005: 84, // Onna
        900200006: 85, // Naoshima
        900200007: 86, // Shirakawa
        // International arrivals-based travel anchors
        1609350: 101, // Bangkok
        1819729: 102, // Hong Kong
        2643743: 103, // London
        1821274: 104, // Macau
        745044: 105, // Istanbul
        292223: 106, // Dubai
        104515: 107, // Makkah
        323777: 108, // Antalya
        2988507: 109, // Paris
        1735161: 110, // Kuala Lumpur
        1880252: 111, // Singapore
        1273294: 112, // Delhi
        1795565: 113, // Shenzhen
        1275339: 114, // Mumbai
        1151254: 115, // Phuket
        3169070: 116, // Rome
        1668341: 119, // Taipei
        1809858: 121, // Guangzhou
        3067696: 122, // Prague
        109223: 123, // Madinah
        1835848: 124, // Seoul
        2759794: 125, // Amsterdam
        1279259: 126, // Agra
        4164138: 127, // Miami
        5368361: 129, // Los Angeles
        1796236: 130, // Shanghai
        1566083: 131, // Ho Chi Minh City
        1645528: 132, // Denpasar
        3128760: 133, // Barcelona
        5506956: 134, // Las Vegas
        3173435: 135, // Milan
        2761369: 137, // Vienna
        2950159: 141, // Berlin
        360630: 142, // Cairo
        264371: 143, // Athens
        4167147: 144, // Orlando
        3164603: 146, // Venice
        3117735: 147, // Madrid
        3176959: 151, // Florence
        1581130: 152, // Hanoi
        6167865: 153, // Toronto
        2147714: 155, // Sydney
        2867714: 156, // Munich
        1816670: 158, // Beijing
        2800866: 160, // Brussels
        3054643: 162, // Budapest
        2267057: 163, // Lisbon
        6173331: 169, // Vancouver
        1153671: 170, // Chiang Mai
        2618425: 171, // Copenhagen
        5391959: 172, // San Francisco
        2158177: 173, // Melbourne
        2542997: 175, // Marrakesh
        2193733: 178, // Auckland
        5856195: 181, // Honolulu
        2925533: 187, // Frankfurt
        2673730: 188, // Stockholm
        1583992: 190, // Da Nang
        292968: 194, // Abu Dhabi
        1846266: 195, // Jeju
        2735943: 196, // Porto
        3451190: 198, // Rio de Janeiro
        1152633: 199, // Krabi

        // Curated small travel destinations
        252919: 220, // Santorini
        257055: 221, // Mykonos
        900300001: 222, // Positano
        900300002: 223, // Amalfi
        900300003: 224, // Cinque Terre
        900300004: 225, // Interlaken
        900300005: 226, // Zermatt
        900300006: 227, // Hallstatt
        900300007: 228, // Banff
        900300008: 229, // Whistler
        6204696: 230, // Queenstown
        6241325: 231, // Rotorua
        1622846: 232, // Ubud
        1822214: 233, // Siem Reap
        1580541: 234, // Hoi An
        900300009: 235, // Goreme
        2553455: 236, // Chefchaouen
        5128581: 237 // New York
    ]
}

private struct LoadedCityData: Sendable {
    let cities: [WanderlustCity]
    let citiesByID: [Int: WanderlustCity]
    let citiesByCountryCode: [String: [WanderlustCity]]
    let citySearchPrefixIndex: [String: [WanderlustCity]]
}

private struct CityCatalogPayload: Decodable {
    let cities: [WanderlustCity]

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cities = try container.decode([WanderlustCity].self, forKey: .cities)
    }

    private enum CodingKeys: String, CodingKey {
        case cities
    }
}

// MARK: - Errors

enum CityDataLoaderError:
    LocalizedError
{
    case fileNotFound
    case emptyFile
    case invalidTextEncoding
    case invalidJSONArray(String)
    case noValidCities

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return """
            cities15000.json was not found in the app bundle.
            Check Target Membership and Copy Bundle Resources.
            """

        case .emptyFile:
            return """
            The city data file is empty.
            """

        case .invalidTextEncoding:
            return """
            The city data file is not valid UTF-8 text.
            """

        case .invalidJSONArray(
            let message
        ):
            return """
            The city JSON array could not be decoded:
            \(message)
            """

        case .noValidCities:
            return """
            No valid city records were found in the city data file.
            """
        }
    }
}
