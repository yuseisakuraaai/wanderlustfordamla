import Foundation

@MainActor
final class CitySearchService {
    static let shared = CitySearchService(loader: CityDataLoader.shared)

    private let loader: CityDataLoader

    init(loader: CityDataLoader) {
        self.loader = loader
    }

    func search(
        query: String,
        countryISO2: String?,
        excluding existingCities: [VisitedCity],
        limit: Int = 10
    ) async -> [WanderlustCity] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedQuery.count >= 1 else {
            return []
        }

        let cleanedCountry = countryISO2?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard let cleanedCountry, !cleanedCountry.isEmpty else {
            return []
        }

        let existingGeonameIDs = Set(existingCities.compactMap(\.geonameID))
        let existingFallbackKeys = Set(
            existingCities.map {
                "\($0.name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current).lowercased())|\($0.countryCode.uppercased())"
            }
        )

        do {
            let sqliteResults = try await WanderlustStaticDataStore.shared.searchCities(
                query: cleanedQuery,
                countryCode: cleanedCountry,
                excluding: existingGeonameIDs,
                limit: max(limit * 4, limit)
            )
            .filter { city in
                let fallbackKey = "\(city.name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current).lowercased())|\(city.normalizedCountryCode)"
                return !existingFallbackKeys.contains(fallbackKey)
            }
            let cleanedSQLiteResults = JapaneseCitySearchCandidateFilter.cleanedResults(
                sqliteResults,
                limit: limit
            )
            if !cleanedSQLiteResults.isEmpty {
                return cleanedSQLiteResults
            }
        } catch {
            WanderlustDiagnostics.warning(
                "SQLite city search unavailable: \(error.localizedDescription)",
                category: .search
            )
        }

        let fallbackResults = await loader.searchOffMain(
            query: cleanedQuery,
            countryCode: cleanedCountry,
            limit: limit * 6
        )
        let filteredFallbackResults = fallbackResults.filter { city in
            if existingGeonameIDs.contains(city.id) {
                return false
            }
            let fallbackKey = "\(city.name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current).lowercased())|\(city.normalizedCountryCode)"
            return !existingFallbackKeys.contains(fallbackKey)
        }
        return JapaneseCitySearchCandidateFilter.cleanedResults(
            filteredFallbackResults,
            limit: limit
        )
    }
}

@MainActor
private enum JapaneseCitySearchCandidateFilter {
    static func cleanedResults(
        _ cities: [WanderlustCity],
        limit: Int
    ) -> [WanderlustCity] {
        var selectedByDisplayKey: [String: WanderlustCity] = [:]
        var orderedKeys: [String] = []

        for city in cities where !isSuppressed(city) {
            let key = displayKey(for: city)
            if let current = selectedByDisplayKey[key] {
                if shouldReplace(current, with: city) {
                    selectedByDisplayKey[key] = city
                }
            } else {
                selectedByDisplayKey[key] = city
                orderedKeys.append(key)
            }
        }

        return orderedKeys
            .compactMap { selectedByDisplayKey[$0] }
            .prefix(max(1, limit))
            .map { $0 }
    }

    private static func displayKey(
        for city: WanderlustCity
    ) -> String {
        guard city.normalizedCountryCode == "JP" else {
            return "\(city.localizedDisplayName)|\(city.normalizedCountryCode)"
        }

        return [
            city.localizedDisplayName,
            city.stateCode
        ]
        .joined(separator: "|")
    }

    private static func isSuppressed(
        _ city: WanderlustCity
    ) -> Bool {
        if availableTokyoWardIDs.contains(city.id) {
            return false
        }

        if isNumericCityArea(city) {
            return true
        }

        switch city.featureCode {
        case "PPLX":
            return true
        case "PPLH", "PPLL":
            return true
        default:
            if city.id == 1850147 {
                return true
            }
            return suppressedJapaneseCityIDs.contains(city.id)
        }
    }

    private static func isNumericCityArea(
        _ city: WanderlustCity
    ) -> Bool {
        guard city.normalizedCountryCode == "FR" else {
            return false
        }

        let names = [city.name, city.localizedDisplayName]
        return names.contains { name in
            let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleanedName.range(
                of: #"^(Paris|Marseille) \d{2}(?:\b|$)"#,
                options: .regularExpression
            ) != nil
        }
    }

    private static func shouldReplace(
        _ current: WanderlustCity,
        with candidate: WanderlustCity
    ) -> Bool {
        let currentRank = featureRank(current.featureCode)
        let candidateRank = featureRank(candidate.featureCode)
        if currentRank != candidateRank {
            return candidateRank > currentRank
        }

        if current.population != candidate.population {
            return candidate.population > current.population
        }

        return candidate.id < current.id
    }

    private static func featureRank(
        _ featureCode: String
    ) -> Int {
        switch featureCode {
        case "PPLC":
            return 7
        case "PPLA":
            return 6
        case "PPLA2":
            return 5
        case "PPLA3":
            return 4
        case "PPL":
            return 3
        case "PPLX":
            return 2
        default:
            return 1
        }
    }

    private static let availableTokyoWardIDs: Set<Int> = [
        11790342, // Setagaya
        11071717, // Edogawa
        10987897, // Adachi
        11836117, // Suginami
        1861321, // Itabashi
        11790353, // Shinjuku
        8572994, // Toshima
        11790374, // Meguro
        1851454, // Sumida
        11790632, // Bunkyo
        11808021, // Shibuya
        10968247, // Arakawa
        11790369, // Taito
        11749713, // Chiyoda
        13353695, // Chuo
        13353696, // Minato
        8469289, // Ota
        8469284, // Katsushika
        8715035, // Nakano
        8469285, // Kita
        900100001, // Koto
        900100002, // Shinagawa
        900100003 // Nerima
    ]

    private static let suppressedJapaneseCityIDs: Set<Int> = [
        11209896,
        1852139,
        1860704,
        1857144,
        1907301,
        1864031,
        1853008,
        1848445,
        2112312,
        1848382,
        1857470,
        1848254,
        1850152,
        8125829,
        1850693,
        2112899,
        1850872,
        1855410,
        1861699,
        1852347,
        1849414,
        2111859,
        2112077,
        1860122,
        1862612,
        2112624,
        2111568,
        1863023,
        1907242,
        1849306,
        1854807,
        1854018,
        1853354,
        1861223,
        1862389,
        1855540,
        1856881,
        1907190,
        1856560,
        1863279,
        2112802,
        2112521,
        1848482,
        2129766,
        1926116,
        2110743,
        1860211,
        1855891,
        8572879,
        1849647,
        1857357,
        1857651,
        2110586,
        1862098,
        2112940,
        1860648,
        1852358,
        2110518,
        1858249,
        1850472,
        1849367,
        1861410,
        1860772,
        1861454,
        1862130,
        1856476,
        1848991,
        1849817,
        1858283,
        2111425,
        1863997,
        2129324,
        1861586,
        2128147,
        2111429,
        1858041,
        2111677,
        1848194,
        1848210,
        1861825,
        1864180,
        1859436,
        1861261,
        1861406,
        1848976,
        2112692,
        1853193,
        1861383,
        1851282,
        2111461,
        1861799,
        1857260,
        1851622,
        1851936,
        1850307,
        1860750,
        2127383,
        2128025,
        1859998,
        1858591,
        1849584,
        2111725,
        8572880,
        2111704,
        1848498,
        1852102,
        1860563,
        2110538,
        2112963,
        1926150,
        1852192,
        2128205,
        2112182,
        1926143,
        1862026,
        1863611,
        2112019,
        1860742,
        2129218,
        2112583,
        1849073,
        2112354,
        1862201,
        1864098,
        1860271,
        6696932,
        1848825,
        1848933,
        1856392,
        1896102,
        2111943,
        1865209,
        1861225,
        8561397,
        1849154,
        1859882,
        8312260,
        2128645
    ]
}
