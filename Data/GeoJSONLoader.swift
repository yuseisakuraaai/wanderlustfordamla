import Foundation
import CoreLocation
import Combine

@MainActor
final class GeoJSONLoader: ObservableObject {
    static let shared = GeoJSONLoader()

    @Published private(set)
    var countries: [Country] = []

    @Published private(set)
    var isLoading = false

    @Published private(set)
    var loadingError: String?

    private var countriesByISOCode:
        [String: Country] = [:]

    private var countriesByName:
        [String: Country] = [:]

    private var searchIndex:
        [CountrySearchEntry] = []

    private var hasLoaded = false
    private var loadTask: Task<[Country], Error>?

    private init() {}

    // MARK: - Loading

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }

        Task { await loadIfNeededAsync() }
    }

    func loadIfNeededAsync() async {
        guard !hasLoaded else {
            return
        }

        await load()
    }

    func reload() {
        hasLoaded = false
        countries = []
        countriesByISOCode = [:]
        countriesByName = [:]
        searchIndex = []
        loadTask = nil

        Task { await load() }
    }

    func releaseMemory() {
        loadTask?.cancel()
        loadTask = nil
        hasLoaded = false
        countries = []
        countriesByISOCode = [:]
        countriesByName = [:]
        searchIndex = []
        isLoading = false
        loadingError = nil
    }

    private func load() async {
        guard !isLoading else {
            if let loadTask {
                do {
                    applyLoadedCountries(try await loadTask.value)
                } catch {
                    applyLoadFailure(error)
                }
            }
            return
        }

        isLoading = true
        loadingError = nil
        #if DEBUG
        let loadStart = CFAbsoluteTimeGetCurrent()
        #endif

        let task = Task.detached(priority: .userInitiated) {
            try Self.loadCountriesFromBundle()
        }
        loadTask = task

        do {
            applyLoadedCountries(try await task.value)
        } catch {
            applyLoadFailure(error)
        }

        loadTask = nil
        #if DEBUG
        WanderlustDiagnostics.info(
            String(
                format: "GeoJSONLoader total %.1fms countries=%d",
                (CFAbsoluteTimeGetCurrent() - loadStart) * 1000,
                countries.count
            ),
            category: .performance
        )
        #endif
    }

    private func applyLoadedCountries(_ loadedCountries: [Country]) {
        countries = loadedCountries

        buildIndexes(
            from: loadedCountries
        )

        hasLoaded = true
        isLoading = false
        loadingError = nil

        WanderlustDiagnostics.info("GeoJSONLoader loaded \(loadedCountries.count) countries", category: .performance)
    }

    private func applyLoadFailure(_ error: Error) {
        countries = []
        countriesByISOCode = [:]
        countriesByName = [:]
        searchIndex = []

        loadingError =
            error.localizedDescription

        isLoading = false
        hasLoaded = false
        loadTask = nil

        WanderlustDiagnostics.error(error, category: .performance, message: "GeoJSONLoader failed")
    }

    // MARK: - Country Lookup

    func country(named nameOrCode: String) -> Country? {
        let cleaned =
            nameOrCode.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !cleaned.isEmpty else {
            return nil
        }

        let normalizedCode =
            cleaned.uppercased()

        if let country =
            countriesByISOCode[
                normalizedCode
            ] {
            return country
        }

        let normalizedName =
            normalize(cleaned)

        if let country =
            countriesByName[
                normalizedName
            ] {
            return country
        }

        return nil
    }

    func country(
        withISOCode code: String
    ) -> Country? {
        countriesByISOCode[
            code
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .uppercased()
        ]
    }

    func country(
        containing coordinate:
            CLLocationCoordinate2D
    ) -> Country? {
        countryForMapTap(at: coordinate)
    }

    func countryForMapTap(at coordinate: CLLocationCoordinate2D) -> Country? {
        exactCountry(containing: coordinate)
    }

    private func exactCountry(containing coordinate: CLLocationCoordinate2D) -> Country? {
        countries
            .filter { country in
                country.fullGeometryBounds?.contains(coordinate: coordinate) == true
            }
            .filter { country in
                country.contains(coordinate: coordinate)
            }
            .min { first, second in
                first.approximateArea < second.approximateArea
            }
    }

    func countryName(
        containing coordinate:
            CLLocationCoordinate2D
    ) -> String? {
        guard let country = country(
            containing: coordinate
        ) else {
            return nil
        }

        return WanderlustNameResolver.countryName(for: country)
    }

    func countryCode(
        containing coordinate:
            CLLocationCoordinate2D
    ) -> String? {
        country(
            containing: coordinate
        )?
        .isoCode
    }

    // MARK: - Visited Countries

    // NOTE: 旧 `visitedCountries(from:)` / `visitedCountryNames(from:)` は削除した。
    // 訪問国の同定は `VisitedCountryAggregator` に一本化している
    // （ここの実装は GeoJSON に一致した国だけを返すため、Statistics や
    //  Passport と件数が食い違う原因になっていた）。
    // 地図の塗り分け用の国一覧は
    // `VisitedCountryAggregator.mappableCountries(in:)` を使うこと。


    // MARK: - Search

    func searchCountries(
        query: String,
        limit: Int = 10
    ) -> [Country] {
        let normalizedQueries = Self.normalizedCountryQueries(for: query)

        guard !normalizedQueries.isEmpty else {
            return []
        }

        return Self.search(
            normalizedQueries: normalizedQueries,
            in: searchIndex,
            limit: limit
        )
    }

    func searchCountriesOffMain(
        query: String,
        limit: Int = 10
    ) async -> [Country] {
        let normalizedQueries = Self.normalizedCountryQueries(for: query)
        guard !normalizedQueries.isEmpty else {
            return []
        }
        let index = searchIndex
        return await Task.detached(priority: .userInitiated) {
            Self.search(
                normalizedQueries: normalizedQueries,
                in: index,
                limit: limit
            )
        }.value
    }

    private nonisolated static func normalizedCountryQueries(
        for query: String
    ) -> [String] {
        SearchNormalizer.queryVariants(for: query)
    }

    private nonisolated static func containsJapaneseKana(
        _ text: String
    ) -> Bool {
        text.contains { character in
            guard let scalar = character.unicodeScalars.first,
                  character.unicodeScalars.count == 1 else {
                return false
            }

            return (0x3040...0x309F).contains(Int(scalar.value)) ||
                (0x30A0...0x30FF).contains(Int(scalar.value))
        }
    }

    // MARK: - Indexes

    private func buildIndexes(
        from loadedCountries: [Country]
    ) {
        countriesByISOCode = [:]
        countriesByName = [:]

        for country in loadedCountries {
            let code =
                country.normalizedISOCode

            if !code.isEmpty {
                countriesByISOCode[
                    code
                ] = country
            }

            let names = countrySearchNames(for: country)
            for name in names {
                countriesByName[
                    normalize(name)
                ] = country
            }
        }

        addCommonAliases()
        searchIndex =
            loadedCountries.map {
                CountrySearchEntry(
                    country: $0,
                    localizedName: WanderlustNameResolver.countryName(for: $0)
                )
            }
    }

    private func countrySearchNames(for country: Country) -> Set<String> {
        var names: Set<String> = []

        let locales = [
            Locale.current,
            Locale(identifier: "en"),
            Locale(identifier: "ja")
        ]

        for locale in locales {
            if let name = locale.localizedString(forRegionCode: country.iso2) {
                let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    names.insert(cleaned)
                }
            }
        }

        names.insert(country.iso2)

        if !country.iso3.isEmpty {
            names.insert(country.iso3)
        }

        return names
    }

    private func addCommonAliases() {
        for (
            alias,
            isoCode
        ) in Self.commonCountryAliasesByName {
            guard let country =
                    countriesByISOCode[
                        isoCode
                    ] else {
                continue
            }

            countriesByName[
                normalize(alias)
            ] = country
        }
    }

    fileprivate nonisolated static func commonAliases(
        for iso2: String
    ) -> [String] {
        let normalizedISO2 = iso2.uppercased()
        return commonCountryAliasesByName.compactMap { alias, aliasISO2 in
            aliasISO2 == normalizedISO2 ? alias : nil
        }
    }

    private nonisolated static let commonCountryAliasesByName: [String: String] = [
        "usa": "US",
        "united states of america": "US",
        "america": "US",

        "uk": "GB",
        "united kingdom": "GB",
        "great britain": "GB",
        "britain": "GB",
        "england": "GB",
        "vereinigtes konigreich": "GB",
        "vereinigtes koenigreich": "GB",
        "イギリス": "GB",
        "英国": "GB",

        "south korea": "KR",
        "republic of korea": "KR",

        "north korea": "KP",
        "democratic people s republic of korea": "KP",

        "russia": "RU",
        "russian federation": "RU",

        "turkey": "TR",
        "turkiye": "TR",
        "türkiye": "TR",

        "czech republic": "CZ",
        "czechia": "CZ",

        "ivory coast": "CI",
        "cote d ivoire": "CI",
        "côte d’ivoire": "CI",

        "vatican": "VA",
        "vatican city": "VA",

        "taiwan": "TW",

        "laos": "LA",

        "syria": "SY",

        "iran": "IR",

        "venezuela": "VE",

        "bolivia": "BO",

        "tanzania": "TZ",

        "moldova": "MD",

        "brunei": "BN",

        "cape verde": "CV",
        "cabo verde": "CV"
    ]

    // MARK: - Bundle Loading

    private nonisolated static func
        loadCountriesFromBundle()
        throws -> [Country] {
        #if DEBUG
        let start = CFAbsoluteTimeGetCurrent()
        #endif
        guard let url =
                locateGeoJSONFile() else {
            throw GeoJSONLoaderError
                .fileNotFound
        }

        if let cachedPayload = WanderlustStaticDataCache.loadPayload(
            cacheName: "countries-geojson-v1",
            sourceURL: url,
            as: CachedCountryPayload.self
        ) {
            let cachedCountries = cachedPayload.decodedCountries
            if !cachedCountries.isEmpty {
                return cachedCountries
            }
        }

        let data = try Data(
            contentsOf: url
        )

        guard !data.isEmpty else {
            throw GeoJSONLoaderError
                .emptyFile
        }

        let rootObject =
            try JSONSerialization
                .jsonObject(
                    with: data
                )

        guard let root =
                rootObject
                    as? [String: Any] else {
            throw GeoJSONLoaderError
                .invalidRootObject
        }

        guard let features =
                root["features"]
                    as? [[String: Any]]
        else {
            throw GeoJSONLoaderError
                .missingFeatures
        }

        var loadedCountries:
            [Country] = []

        loadedCountries.reserveCapacity(
            features.count
        )

        for feature in features {
            guard let country =
                    decodeCountry(
                        from: feature
                    ) else {
                continue
            }

            loadedCountries.append(
                country
            )
        }

        let sanitized =
            sanitize(
                loadedCountries
            )

        guard !sanitized.isEmpty else {
            throw GeoJSONLoaderError
                .noValidCountries
        }

        let sortedCountries = sanitized.sorted {
            $0.iso2 < $1.iso2
        }

        WanderlustStaticDataCache.savePayload(
            CachedCountryPayload(countries: sortedCountries),
            cacheName: "countries-geojson-v1",
            sourceURL: url
        )

        #if DEBUG
        print(String(format: "[WanderlustPerformance] countries.geojson %.1fms %d countries", (CFAbsoluteTimeGetCurrent() - start) * 1000, sortedCountries.count))
        #endif

        return sortedCountries
    }

    private nonisolated static func
        locateGeoJSONFile() -> URL? {
        let possibleNames = [
            "countries",
            "countries_simplified",
            "world_countries",
            "worldCountries"
        ]

        let possibleExtensions = [
            "geojson",
            "json"
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

    // MARK: - Country Decoding

    private nonisolated static func
        decodeCountry(
            from feature: [String: Any]
        ) -> Country? {
        guard let geometry =
                feature["geometry"]
                    as? [String: Any]
        else {
            return nil
        }

        guard let geometryType =
                geometry["type"]
                    as? String
        else {
            return nil
        }

        guard let rawCoordinates =
                geometry["coordinates"]
        else {
            return nil
        }

        let properties =
            feature["properties"]
                as? [String: Any] ?? [:]

        let iso2 = validISO2Code(
            in: properties
        )

        guard !iso2.isEmpty else {
            return nil
        }

        let iso3 = firstString(
            in: properties,
            keys: [
                "iso_a3"
            ]
        )
        .uppercased()

        let continent = firstString(
            in: properties,
            keys: [
                "continent"
            ]
        )

        let polygonParts: [CountryPolygon]

        switch geometryType {
        case "Polygon":
            if let polygon =
                decodePolygon(rawCoordinates) {
                polygonParts = [polygon]
            } else {
                polygonParts = []
            }

        case "MultiPolygon":
            polygonParts =
                decodeMultiPolygon(
                    rawCoordinates
                )

        default:
            polygonParts = []
        }

        guard !polygonParts.isEmpty else {
            return nil
        }

        return Country(
            iso2: iso2,
            iso3: iso3,
            continent: continent,
            polygonParts: polygonParts
        )
    }

    private nonisolated static func
        validISO2Code(
            in properties:
                [String: Any]
        ) -> String {
        guard let value = properties["iso_a2"] as? String else {
            return ""
        }

        let cleaned =
            value
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .uppercased()

        guard cleaned.count == 2,
              cleaned != "-99",
              supportedCountryISO2Codes.contains(cleaned)
        else {
            return ""
        }

        return cleaned
    }

    private nonisolated static func
        firstString(
            in dictionary:
                [String: Any],
            keys: [String]
        ) -> String {
        for key in keys {
            guard let value =
                    dictionary[key]
                    as? String else {
                continue
            }

            let cleaned =
                value
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )

            if !cleaned.isEmpty,
               cleaned != "-99" {
                return cleaned
            }
        }

        return ""
    }

    // MARK: - Polygon Decoding

    private nonisolated static func
        decodePolygon(
            _ value: Any
        ) -> CountryPolygon? {
        guard let rings =
                value as? [[[Double]]],
              !rings.isEmpty else {
            return nil
        }

        let exterior =
            rings[0].compactMap {
                coordinate(from: $0)
            }

        guard exterior.count >= 3 else {
            return nil
        }

        let holes =
            rings.dropFirst()
                .map { ring in
                    ring.compactMap {
                        coordinate(from: $0)
                    }
                }
                .filter { $0.count >= 3 }

        return CountryPolygon(
            exterior: exterior,
            holes: holes
        )
    }

    private nonisolated static func
        decodeMultiPolygon(
            _ value: Any
        ) -> [CountryPolygon] {
        guard let rawPolygons =
                value as? [[[[Double]]]]
        else {
            return []
        }

        var polygons: [CountryPolygon] = []

        polygons.reserveCapacity(
            rawPolygons.count
        )

        for rawPolygon in rawPolygons {
            guard !rawPolygon.isEmpty else {
                continue
            }

            let exterior =
                rawPolygon[0].compactMap {
                    coordinate(from: $0)
                }

            guard exterior.count >= 3 else {
                continue
            }

            let holes =
                rawPolygon.dropFirst()
                    .map { ring in
                        ring.compactMap {
                            coordinate(from: $0)
                        }
                    }
                    .filter { $0.count >= 3 }

            polygons.append(
                CountryPolygon(
                    exterior: exterior,
                    holes: holes
                )
            )
        }

        return polygons
    }

    private nonisolated static func
        coordinate(
            from pair: [Double]
        ) -> CLLocationCoordinate2D? {
        guard pair.count >= 2 else {
            return nil
        }

        let longitude = pair[0]
        let latitude = pair[1]

        guard (-90...90)
            .contains(latitude),
              (-180...180)
                .contains(longitude)
        else {
            return nil
        }

        return CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }

    // MARK: - Sanitizing

    private nonisolated static func
        sanitize(
            _ rawCountries: [Country]
        ) -> [Country] {
        var uniqueCountries:
            [String: Country] = [:]

        for country in rawCountries {
            guard supportedCountryISO2Codes.contains(country.normalizedISOCode) else {
                continue
            }

            guard !country.polygonParts.isEmpty else {
                continue
            }

            let key = country.normalizedISOCode

            guard !key.isEmpty else {
                continue
            }

            if uniqueCountries[key] != nil {
                #if DEBUG
                print("GeoJSONLoader duplicate ISO2 ignored: \(key)")
                #endif
                continue
            }

            uniqueCountries[key] = country
        }

        if let japan = uniqueCountries["JP"] {
            uniqueCountries["JP"] = countryWithSupplementalGeometry(
                japan,
                rawCountries: rawCountries
            )
        }

        return Array(
            uniqueCountries.values
        )
    }

    private nonisolated static func countryWithSupplementalGeometry(
        _ country: Country,
        rawCountries: [Country]
    ) -> Country {
        return Country(
            iso2: country.iso2,
            iso3: country.iso3,
            continent: country.continent,
            polygonParts: country.polygonParts + supplementalJapanPolygons(from: rawCountries)
        )
    }

    private nonisolated static func supplementalJapanPolygons(
        from rawCountries: [Country]
    ) -> [CountryPolygon] {
        rawCountries.flatMap { sourceCountry in
            sourceCountry.polygonParts.filter { polygon in
                guard let bounds = polygon.boundingBox else {
                    return false
                }

                switch sourceCountry.normalizedISOCode {
                case "KR":
                    return boundsAreContained(
                        bounds,
                        minimumLatitude: 37.20,
                        maximumLatitude: 37.27,
                        minimumLongitude: 131.82,
                        maximumLongitude: 131.89
                    )

                case "RU":
                    return boundsAreContained(
                        bounds,
                        minimumLatitude: 43.30,
                        maximumLatitude: 45.60,
                        minimumLongitude: 145.00,
                        maximumLongitude: 149.00
                    )

                default:
                    return false
                }
            }
        }
    }

    private nonisolated static func boundsAreContained(
        _ bounds: CountryBoundingBox,
        minimumLatitude: Double,
        maximumLatitude: Double,
        minimumLongitude: Double,
        maximumLongitude: Double
    ) -> Bool {
        bounds.minimumLatitude >= minimumLatitude &&
            bounds.maximumLatitude <= maximumLatitude &&
            bounds.minimumLongitude >= minimumLongitude &&
            bounds.maximumLongitude <= maximumLongitude
    }

    private nonisolated static let supportedCountryISO2Codes: Set<String> = [
        "AD", "AE", "AF", "AG", "AL", "AM", "AO", "AR", "AT", "AU",
        "AZ", "BA", "BB", "BD", "BE", "BF", "BG", "BH", "BI", "BJ",
        "BN", "BO", "BR", "BS", "BT", "BW", "BY", "BZ", "CA", "CD",
        "CF", "CG", "CH", "CI", "CL", "CM", "CN", "CO", "CR", "CU",
        "CV", "CY", "CZ", "DE", "DJ", "DK", "DM", "DO", "DZ", "EC",
        "EE", "EG", "ER", "ES", "ET", "FI", "FJ", "FM", "FR", "GA",
        "GB", "GD", "GE", "GH", "GM", "GN", "GQ", "GR", "GT", "GW",
        "GY", "HN", "HR", "HT", "HU", "ID", "IE", "IL", "IN", "IQ",
        "IR", "IS", "IT", "JM", "JO", "JP", "KE", "KG", "KH", "KI",
        "KM", "KN", "KP", "KR", "KW", "KZ", "LA", "LB", "LC", "LI",
        "LK", "LR", "LS", "LT", "LU", "LV", "LY", "MA", "MC", "MD",
        "ME", "MG", "MH", "MK", "ML", "MM", "MN", "MR", "MT", "MU",
        "MV", "MW", "MX", "MY", "MZ", "NA", "NE", "NG", "NI", "NL",
        "NO", "NP", "NR", "NZ", "OM", "PA", "PE", "PG", "PH", "PK",
        "PL", "PS", "PT", "PW", "PY", "QA", "RO", "RS", "RU", "RW",
        "SA", "SB", "SC", "SD", "SE", "SG", "SI", "SK", "SL", "SM",
        "SN", "SO", "SR", "SS", "ST", "SV", "SY", "SZ", "TD", "TG",
        "TH", "TJ", "TL", "TM", "TN", "TO", "TR", "TT", "TV", "TW",
        "TZ", "UA", "UG", "US", "UY", "UZ", "VA", "VC", "VE", "VN",
        "VU", "WS", "XK", "YE", "ZA", "ZM", "ZW"
    ]

    private func normalize(
        _ text: String
    ) -> String {
        Self.normalizeSearchText(text)
    }

    nonisolated static func normalizeSearchText(
        _ text: String
    ) -> String {
        SearchNormalizer.normalize(text)
    }

    private nonisolated static func search(
        normalizedQueries: [String],
        in index: [CountrySearchEntry],
        limit: Int
    ) -> [Country] {
        index
            .compactMap { entry -> ScoredCountry? in
                guard let score = entry.score(for: normalizedQueries) else {
                    return nil
                }

        return ScoredCountry(
            country: entry.country,
            score: score,
            localizedName: entry.localizedName
        )
            }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                let firstRank = CountrySearchRank.priority(for: $0.country.iso2)
                let secondRank = CountrySearchRank.priority(for: $1.country.iso2)
                if firstRank != secondRank {
                    return firstRank < secondRank
                }
                return $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending
            }
            .prefix(max(1, limit))
            .map(\.country)
    }
}

// MARK: - Search Helper

private struct ScoredCountry {
    let country: Country
    let score: Int
    let localizedName: String
}

private struct CountrySearchEntry: Sendable {
    let country: Country
    let englishName: String
    let japaneseName: String
    let localizedName: String
    let iso2: String
    let iso3: String
    let searchCandidate: SearchCandidate<Country>

    init(
        country: Country,
        localizedName: String
    ) {
        self.country = country
        englishName = Locale(identifier: "en").localizedString(forRegionCode: country.iso2) ?? country.iso2
        japaneseName = Locale(identifier: "ja").localizedString(forRegionCode: country.iso2) ?? country.iso2
        self.localizedName = localizedName
        iso2 = country.iso2
        iso3 = country.iso3
        searchCandidate = SearchCandidate(
            item: country,
            tokens: Self.searchTokens(
                country: country,
                englishName: englishName,
                japaneseName: japaneseName,
                localizedName: localizedName,
                iso2: iso2,
                iso3: iso3
            )
        )
    }

    nonisolated func score(
        for normalizedQueries: [String]
    ) -> Int? {
        searchCandidate.score(
            for: normalizedQueries,
            containsJapaneseKana: normalizedQueries.contains {
                SearchNormalizer.containsJapaneseKana($0)
            }
        )
    }

    private static func searchTokens(
        country: Country,
        englishName: String,
        japaneseName: String,
        localizedName: String,
        iso2: String,
        iso3: String
    ) -> [SearchToken] {
        let tokens = [
            SearchToken(kind: .localizedName, value: localizedName),
            SearchToken(kind: .officialName, value: japaneseName),
            SearchToken(kind: .officialName, value: englishName),
            SearchToken(kind: .code, value: iso2),
            SearchToken(kind: .code, value: iso3)
        ] +
        JapaneseCountryReadingAliases.aliases(for: country.iso2).map {
            SearchToken(kind: .reading, value: $0)
        } +
        GeoJSONLoader.commonAliases(for: country.iso2).map {
            SearchToken(kind: .alias, value: $0)
        }

        var seen = Set<String>()
        return tokens.filter { token in
            let key = "\(token.kind)-\(SearchNormalizer.normalize(token.value))"
            return !token.value.isEmpty && seen.insert(key).inserted
        }
    }

}

// MARK: - Country Cache

nonisolated private struct CachedCountryPayload: Codable {
    let countries: [CachedCountry]

    init(countries: [Country]) {
        self.countries = countries.map(CachedCountry.init)
    }

    var decodedCountries: [Country] {
        countries.map(\.country)
    }
}

nonisolated private struct CachedCountry: Codable {
    let iso2: String
    let iso3: String
    let continent: String
    let polygonParts: [CachedCountryPolygon]

    init(_ country: Country) {
        iso2 = country.iso2
        iso3 = country.iso3
        continent = country.continent
        polygonParts = country.polygonParts.map(CachedCountryPolygon.init)
    }

    var country: Country {
        Country(
            iso2: iso2,
            iso3: iso3,
            continent: continent,
            polygonParts: polygonParts.map(\.polygon)
        )
    }
}

nonisolated private struct CachedCountryPolygon: Codable {
    let id: String
    let exterior: [CachedCoordinate]
    let holes: [[CachedCoordinate]]

    init(_ polygon: CountryPolygon) {
        id = polygon.id
        exterior = polygon.exterior.map(CachedCoordinate.init)
        holes = polygon.holes.map { $0.map(CachedCoordinate.init) }
    }

    var polygon: CountryPolygon {
        CountryPolygon(
            id: id,
            exterior: exterior.map(\.coordinate),
            holes: holes.map { $0.map(\.coordinate) }
        )
    }
}

nonisolated private struct CachedCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Errors

enum GeoJSONLoaderError:
    LocalizedError
{
    case fileNotFound
    case emptyFile
    case invalidRootObject
    case missingFeatures
    case noValidCountries

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return """
            countries.geojson was not found in the app bundle.
            Check Target Membership and Copy Bundle Resources.
            """

        case .emptyFile:
            return """
            countries.geojson is empty.
            """

        case .invalidRootObject:
            return """
            The GeoJSON root object is invalid.
            """

        case .missingFeatures:
            return """
            The GeoJSON file does not contain a features array.
            """

        case .noValidCountries:
            return """
            No valid country polygons were found in countries.geojson.
            """
        }
    }
}
