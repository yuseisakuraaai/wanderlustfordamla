import Foundation
import SQLite3

private nonisolated(unsafe) let wanderlustSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor WanderlustStaticDataStore {
    static let shared = WanderlustStaticDataStore()

    private var database: OpaquePointer?

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func warmUp() throws {
        _ = try databaseConnection()
    }

    func searchCountries(query: String, limit: Int = 30) throws -> [Country] {
        guard !Task.isCancelled else { return [] }

        let queryContainsJapaneseKana = SearchNormalizer.containsJapaneseKana(query)
        let normalizedQueries = SearchNormalizer.queryVariants(for: query)
        guard !normalizedQueries.isEmpty else { return [] }

        var countries: [Country] = []
        var seenISO2Codes: Set<String> = []

        func append(_ matches: [Country]) {
            let rankedMatches = matches.sorted { first, second in
                let firstRank = CountrySearchRank.priority(for: first.iso2)
                let secondRank = CountrySearchRank.priority(for: second.iso2)
                if firstRank != secondRank {
                    return firstRank < secondRank
                }
                return first.iso2 < second.iso2
            }

            for country in rankedMatches {
                guard seenISO2Codes.insert(country.iso2).inserted else { continue }
                countries.append(country)
                if countries.count >= limit { break }
            }
        }

        let prefixSQL = """
            SELECT DISTINCT c.iso2, c.iso3, c.continent, s.priority
            FROM country_search_names s
            JOIN countries c ON c.iso2 = s.entity_id
            WHERE s.normalized_name = ?1 OR s.normalized_name LIKE ?2
            ORDER BY
                CASE
                    WHEN s.normalized_name = ?1 THEN 0
                    ELSE 2
                END,
                s.priority ASC,
                c.iso2 ASC
            LIMIT ?3
        """
        for normalizedQuery in normalizedQueries {
            guard !Task.isCancelled else { return countries }

            let matches = try withStatement(prefixSQL) { statement in
                try bind(statement, normalizedQuery, at: 1)
                try bind(statement, "\(normalizedQuery)%", at: 2)
                try bindInt(statement, limit + 20, at: 3)

                var matchedCountries: [Country] = []
                try forEachRow(in: statement) {
                    matchedCountries.append(
                        Country(
                            iso2: columnString(statement, 0),
                            iso3: columnString(statement, 1),
                            continent: columnString(statement, 2),
                            polygonParts: []
                        )
                    )
                }
                return matchedCountries
            }

            append(matches)
            if countries.count >= limit { break }
        }

        if countries.count < limit {
            let aliasMatches = try JapaneseCountryReadingAliases
                .matchingISO2Codes(for: normalizedQueries)
                .compactMap { iso2 in
                    try country(matchingISO2: iso2)
                }
            append(aliasMatches)
        }

        guard !queryContainsJapaneseKana else {
            return countries
        }

        let wordPrefixSQL = """
            SELECT DISTINCT c.iso2, c.iso3, c.continent, s.priority
            FROM country_search_names s
            JOIN countries c ON c.iso2 = s.entity_id
            WHERE s.normalized_name LIKE ?1
            ORDER BY
                s.priority ASC,
                c.iso2 ASC
            LIMIT ?2
        """
        for normalizedQuery in normalizedQueries where countries.count < limit && normalizedQuery.count >= 3 {
            guard !Task.isCancelled else { return countries }

            let matches = try withStatement(wordPrefixSQL) { statement in
                try bind(statement, "% \(normalizedQuery)%", at: 1)
                try bindInt(statement, limit + 20, at: 2)

                var matchedCountries: [Country] = []
                try forEachRow(in: statement) {
                    matchedCountries.append(
                        Country(
                            iso2: columnString(statement, 0),
                            iso3: columnString(statement, 1),
                            continent: columnString(statement, 2),
                            polygonParts: []
                        )
                    )
                }
                return matchedCountries
            }

            append(matches)
        }

        return countries
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

    private nonisolated static func containsMatchPattern(
        for normalizedQuery: String,
        containsJapaneseKana: Bool
    ) -> String {
        let minimumLength = containsJapaneseKana ? 2 : 3
        guard normalizedQuery.count >= minimumLength else {
            return "\u{0}"
        }

        return containsJapaneseKana
            ? "%\(normalizedQuery)%"
            : "% \(normalizedQuery)%"
    }

    func searchCities(
        query: String,
        countryCode: String?,
        excluding excludedIDs: Set<Int> = [],
        limit: Int = 30
    ) throws -> [WanderlustCity] {
        guard !Task.isCancelled else { return [] }

        let cities = try searchCitiesWithoutAliases(
            query: query,
            countryCode: countryCode,
            excluding: excludedIDs,
            limit: limit
        )

        let normalizedCountry = countryCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        var aliasCities: [WanderlustCity] = []
        var seenAliasCityIDs: Set<Int> = []
        for target in JapaneseSearchReadingAliases.matchingCityTargets(
            for: SearchNormalizer.queryVariants(
                for: query,
                includeRomajiForKana: true
            )
        ) where aliasCities.count < limit {
            guard !Task.isCancelled else { return mergeAliasCities(aliasCities, with: cities, limit: limit) }
            guard normalizedCountry.isEmpty || target.countryCode == normalizedCountry else {
                continue
            }

            let aliasMatches = try searchCitiesWithoutAliases(
                query: target.name,
                countryCode: target.countryCode,
                excluding: excludedIDs.union(seenAliasCityIDs),
                limit: limit
            )

            for city in aliasMatches {
                guard !excludedIDs.contains(city.id),
                      seenAliasCityIDs.insert(city.id).inserted else {
                    continue
                }
                aliasCities.append(city)
                if aliasCities.count >= limit { break }
            }
        }

        return mergeAliasCities(aliasCities, with: cities, limit: limit)
    }

    private func searchCitiesWithoutAliases(
        query: String,
        countryCode: String?,
        excluding excludedIDs: Set<Int>,
        limit: Int
    ) throws -> [WanderlustCity] {
        guard !Task.isCancelled else { return [] }

        let queryContainsJapaneseKana = Self.containsJapaneseKana(query)
        let normalizedQueries = SearchNormalizer.queryVariants(
            for: query,
            includeRomajiForKana: true
        )
        guard !normalizedQueries.isEmpty else { return [] }
        let normalizedCountry = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let prefixSQL = """
            SELECT DISTINCT c.id, c.name, c.ascii_name, c.country_iso2, c.admin1_code,
                c.latitude, c.longitude, c.population, c.timezone, c.feature_code,
                c.municipality_suffix, c.travel_demand_rank, s.priority
            FROM city_search_names s
            JOIN cities c ON c.id = CAST(s.entity_id AS INTEGER)
            WHERE s.normalized_name >= ?1
                AND s.normalized_name < ?2
                AND (?3 = '' OR c.country_iso2 = ?3)
            ORDER BY
                CASE
                    WHEN s.normalized_name = ?4 THEN 0
                    ELSE 2
                END,
                s.priority ASC,
                c.population DESC,
                c.name ASC
            LIMIT ?5
        """
        let containsSQL = """
            SELECT DISTINCT c.id, c.name, c.ascii_name, c.country_iso2, c.admin1_code,
                c.latitude, c.longitude, c.population, c.timezone, c.feature_code,
                c.municipality_suffix, c.travel_demand_rank, s.priority
            FROM city_search_names s
            JOIN cities c ON c.id = CAST(s.entity_id AS INTEGER)
            WHERE s.normalized_name LIKE ?1
                AND (?2 = '' OR c.country_iso2 = ?2)
            ORDER BY
                s.priority ASC,
                c.population DESC,
                c.name ASC
            LIMIT ?3
        """
        var cities: [WanderlustCity] = []
        var seenCityIDs: Set<Int> = []

        func fetchCities(
            sql: String,
            configure: (OpaquePointer) throws -> Void
        ) throws -> [WanderlustCity] {
            try withStatement(sql) { statement in
                try configure(statement)

                var matchedCities: [WanderlustCity] = []
                try forEachRow(in: statement) {
                    let id = Int(sqlite3_column_int(statement, 0))
                    if !excludedIDs.contains(id) {
                        matchedCities.append(
                            WanderlustCity(
                                id: id,
                                name: columnString(statement, 1),
                                countryCode: columnString(statement, 3),
                                stateCode: columnString(statement, 4),
                                timezone: columnString(statement, 8),
                                population: Int(sqlite3_column_int(statement, 7)),
                                featureCode: columnString(statement, 9),
                                municipalitySuffix: columnString(statement, 10),
                                travelDemandRank: Int(sqlite3_column_int(statement, 11)),
                                location: WanderlustGeoPoint(
                                    coordinates: [
                                        sqlite3_column_double(statement, 6),
                                        sqlite3_column_double(statement, 5)
                                    ]
                                ),
                                alternateNames: [columnString(statement, 2)]
                            )
                        )
                    }
                }
                return matchedCities
            }
        }

        func appendRanked(_ matches: [WanderlustCity], for normalizedQuery: String) {
            let rankedMatches = matches.sorted {
                let firstScore = $0.searchScore(for: normalizedQuery)
                let secondScore = $1.searchScore(for: normalizedQuery)
                if firstScore != secondScore {
                    return firstScore > secondScore
                }

                let firstDemandRank = StaticCityTravelDemandRank.priority(for: $0)
                let secondDemandRank = StaticCityTravelDemandRank.priority(for: $1)
                if firstDemandRank != secondDemandRank {
                    return firstDemandRank < secondDemandRank
                }

                if $0.population != $1.population {
                    return $0.population > $1.population
                }

                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            for city in rankedMatches {
                guard seenCityIDs.insert(city.id).inserted else { continue }
                cities.append(city)
                if cities.count >= limit { break }
            }
        }

        for normalizedQuery in normalizedQueries {
            guard !Task.isCancelled else { return cities }

            let prefixMatches = try fetchCities(sql: prefixSQL) { statement in
                try bind(statement, normalizedQuery, at: 1)
                try bind(statement, Self.prefixUpperBound(for: normalizedQuery), at: 2)
                try bind(statement, normalizedCountry, at: 3)
                try bind(statement, normalizedQuery, at: 4)
                try bindInt(statement, limit + excludedIDs.count + 20, at: 5)
            }
            appendRanked(prefixMatches, for: normalizedQuery)

            guard cities.count < limit else { break }

            let containsPattern = Self.containsMatchPattern(
                for: normalizedQuery,
                containsJapaneseKana: queryContainsJapaneseKana
            )
            guard containsPattern != "\u{0}" else { continue }

            let containsMatches = try fetchCities(sql: containsSQL) { statement in
                try bind(statement, containsPattern, at: 1)
                try bind(statement, normalizedCountry, at: 2)
                try bindInt(statement, limit + excludedIDs.count + 20, at: 3)
            }
            appendRanked(containsMatches, for: normalizedQuery)

            if cities.count >= limit { break }
        }

        return cities
    }

    func searchAirports(query: String, excluding excludedID: String? = nil, limit: Int = 30) throws -> [Airport] {
        guard !Task.isCancelled else { return [] }

        let queryContainsJapaneseKana = Self.containsJapaneseKana(query)
        let normalizedQueries = SearchNormalizer.queryVariants(
            for: query,
            includeRomajiForKana: !queryContainsJapaneseKana
        )
        guard !normalizedQueries.isEmpty else { return [] }
        let airportPassengerRankSQL = AirportSearchRank.sqliteCaseExpression(
            column: "a.iata_code"
        )
        let prefixSQL = """
            WITH route_counts AS (
                SELECT airport_code, COUNT(*) AS route_count
                FROM (
                    SELECT origin AS airport_code FROM routes
                    UNION ALL
                    SELECT destination AS airport_code FROM routes
                )
                WHERE airport_code IS NOT NULL AND airport_code != ''
                GROUP BY airport_code
            )
            SELECT DISTINCT a.id, a.ident, a.type, a.name, a.latitude, a.longitude,
                a.elevation_feet, a.continent, a.country_iso2, a.region_code, a.municipality,
                a.city_id, a.scheduled_service, a.gps_code, a.iata_code, a.icao_code,
                a.local_code, COALESCE(NULLIF(a.timezone, ''), NULLIF(c.timezone, ''), ''), s.priority
            FROM airport_search_names s
            JOIN airports a ON a.id = s.entity_id
            LEFT JOIN cities c ON c.id = a.city_id
            LEFT JOIN route_counts rc ON rc.airport_code = a.iata_code
            WHERE s.normalized_name = ?1 OR s.normalized_name LIKE ?2
            ORDER BY
                CASE
                    WHEN s.normalized_name = ?1 THEN 0
                    WHEN s.normalized_name LIKE ?2 THEN 1
                END,
                \(airportPassengerRankSQL) ASC,
                COALESCE(rc.route_count, 0) DESC,
                s.priority ASC,
                a.scheduled_service DESC,
                CASE a.type WHEN 'large_airport' THEN 0 WHEN 'medium_airport' THEN 1 ELSE 2 END,
                a.name ASC
            LIMIT ?3
        """
        let containsSQL = """
            WITH route_counts AS (
                SELECT airport_code, COUNT(*) AS route_count
                FROM (
                    SELECT origin AS airport_code FROM routes
                    UNION ALL
                    SELECT destination AS airport_code FROM routes
                )
                WHERE airport_code IS NOT NULL AND airport_code != ''
                GROUP BY airport_code
            )
            SELECT DISTINCT a.id, a.ident, a.type, a.name, a.latitude, a.longitude,
                a.elevation_feet, a.continent, a.country_iso2, a.region_code, a.municipality,
                a.city_id, a.scheduled_service, a.gps_code, a.iata_code, a.icao_code,
                a.local_code, COALESCE(NULLIF(a.timezone, ''), NULLIF(c.timezone, ''), ''), s.priority
            FROM airport_search_names s
            JOIN airports a ON a.id = s.entity_id
            LEFT JOIN cities c ON c.id = a.city_id
            LEFT JOIN route_counts rc ON rc.airport_code = a.iata_code
            WHERE s.normalized_name LIKE ?1
            ORDER BY
                \(airportPassengerRankSQL) ASC,
                COALESCE(rc.route_count, 0) DESC,
                s.priority ASC,
                a.scheduled_service DESC,
                CASE a.type WHEN 'large_airport' THEN 0 WHEN 'medium_airport' THEN 1 ELSE 2 END,
                a.name ASC
            LIMIT ?2
        """
        var airports: [Airport] = []
        var seenAirportIDs: Set<String> = []
        var seenIATACodes: Set<String> = []

        func appendAirports(_ matches: [Airport]) {
            for airport in matches {
                if airport.id == excludedID { continue }
                guard seenAirportIDs.insert(airport.id).inserted else { continue }
                let iata = airport.normalizedIATACode
                if !iata.isEmpty {
                    guard seenIATACodes.insert(iata).inserted else { continue }
                }
                airports.append(airport)
                if airports.count >= limit { break }
            }
        }

        func appendFilteredAirports(
            _ matches: [Airport],
            where isIncluded: (Airport) -> Bool
        ) {
            appendAirports(matches.filter(isIncluded))
        }

        func normalizedAirportNames(_ airport: Airport) -> [String] {
            [airport.displayName, airport.name]
                .map(SearchNormalizer.normalize)
                .filter { !$0.isEmpty }
        }

        func normalizedAirportMunicipalities(_ airport: Airport) -> [String] {
            [airport.displayMunicipality, airport.municipality]
                .map(SearchNormalizer.normalize)
                .filter { !$0.isEmpty }
        }

        func matchesCodeExact(_ airport: Airport) -> Bool {
            let codes = [
                airport.normalizedIATACode,
                airport.normalizedICAOCode
            ]
            .map(SearchNormalizer.normalize)
            return normalizedQueries.contains { codes.contains($0) }
        }

        func matchesNameExact(_ airport: Airport) -> Bool {
            let names = normalizedAirportNames(airport)
            return normalizedQueries.contains { names.contains($0) }
        }

        func matchesNamePrefix(_ airport: Airport) -> Bool {
            let names = normalizedAirportNames(airport)
            return normalizedQueries.contains { query in
                names.contains { $0.hasPrefix(query) }
            }
        }

        func matchesMunicipalityPrefix(_ airport: Airport) -> Bool {
            let municipalities = normalizedAirportMunicipalities(airport)
            return normalizedQueries.contains { query in
                municipalities.contains { $0.hasPrefix(query) }
            }
        }

        func matchesOtherPrefix(_ airport: Airport) -> Bool {
            [
                airport.normalizedIATACode,
                airport.normalizedICAOCode,
                airport.ident,
                airport.localCode
            ]
            .map(SearchNormalizer.normalize)
            .contains { value in
                normalizedQueries.contains { value.hasPrefix($0) }
            }
        }

        var prefixCandidates: [Airport] = []
        for normalizedQuery in normalizedQueries {
            guard !Task.isCancelled else { return airports }

            let matches = try withStatement(prefixSQL) { statement in
                try bind(statement, normalizedQuery, at: 1)
                try bind(statement, "\(normalizedQuery)%", at: 2)
                try bindInt(statement, limit + 40, at: 3)
                var matchedAirports: [Airport] = []
                try forEachRow(in: statement) {
                    matchedAirports.append(airportFromCurrentRow(statement))
                }
                return matchedAirports
            }

            prefixCandidates.append(contentsOf: matches)
        }

        let sortedPrefixCandidates = sortedAirportSearchMatches(prefixCandidates, normalizedQueries: normalizedQueries)

        appendFilteredAirports(sortedPrefixCandidates, where: matchesCodeExact)

        if airports.count < limit {
            appendAirportAliasMatches(
                for: normalizedQueries,
                match: .exact,
                to: &airports,
                seenAirportIDs: &seenAirportIDs,
                seenIATACodes: &seenIATACodes,
                excludedID: excludedID,
                limit: limit
            )
        }

        if airports.count < limit {
            appendFilteredAirports(sortedPrefixCandidates, where: matchesNameExact)
        }

        if airports.count < limit {
            appendFilteredAirports(sortedPrefixCandidates, where: matchesNamePrefix)
        }

        if airports.count < limit {
            appendAirportAliasMatches(
                for: normalizedQueries,
                match: .prefix,
                to: &airports,
                seenAirportIDs: &seenAirportIDs,
                seenIATACodes: &seenIATACodes,
                excludedID: excludedID,
                limit: limit
            )
        }

        if airports.count < limit {
            appendFilteredAirports(sortedPrefixCandidates, where: matchesMunicipalityPrefix)
        }

        if airports.count < limit {
            appendFilteredAirports(sortedPrefixCandidates, where: matchesOtherPrefix)
        }

        var containsCandidates: [Airport] = []
        for normalizedQuery in normalizedQueries where airports.count < limit {
            guard !Task.isCancelled else { return airports }

            let containsPattern = Self.containsMatchPattern(
                for: normalizedQuery,
                containsJapaneseKana: queryContainsJapaneseKana
            )
            guard containsPattern != "\u{0}" else { continue }

            let matches = try withStatement(containsSQL) { statement in
                try bind(statement, containsPattern, at: 1)
                try bindInt(statement, limit + 40, at: 2)
                var matchedAirports: [Airport] = []
                try forEachRow(in: statement) {
                    matchedAirports.append(airportFromCurrentRow(statement))
                }
                return matchedAirports
            }

            containsCandidates.append(contentsOf: matches)
        }

        if airports.count < limit {
            appendAirports(sortedAirportSearchMatches(containsCandidates, normalizedQueries: normalizedQueries))
        }

        return airports
    }

    private func appendAirportAliasMatches(
        for normalizedQueries: [String],
        match: JapaneseSearchReadingAliases.AliasMatch,
        to airports: inout [Airport],
        seenAirportIDs: inout Set<String>,
        seenIATACodes: inout Set<String>,
        excludedID: String?,
        limit: Int
    ) {
        for code in JapaneseSearchReadingAliases.matchingAirportCodes(
            for: normalizedQueries,
            match: match
        ) where airports.count < limit {
            guard !Task.isCancelled else { return }

            guard let airport = try? airport(matching: code),
                  airport.id != excludedID else {
                continue
            }
            guard seenAirportIDs.insert(airport.id).inserted else {
                continue
            }

            let iata = airport.normalizedIATACode
            if !iata.isEmpty {
                guard seenIATACodes.insert(iata).inserted else { continue }
            }
            airports.append(airport)
        }
    }

    private nonisolated func sortedAirportSearchMatches(
        _ matches: [Airport],
        normalizedQueries: [String]
    ) -> [Airport] {
        matches.sorted { first, second in
            let firstScore = normalizedQueries.map { first.searchScore(for: $0) }.max() ?? 0
            let secondScore = normalizedQueries.map { second.searchScore(for: $0) }.max() ?? 0
            if firstScore != secondScore {
                return firstScore > secondScore
            }

            let firstPriority = AirportSearchRank.priority(for: first)
            let secondPriority = AirportSearchRank.priority(for: second)
            if firstPriority != secondPriority {
                return firstPriority < secondPriority
            }

            return first.displayTitle.localizedCaseInsensitiveCompare(second.displayTitle) == .orderedAscending
        }
    }

    func airport(matching code: String) throws -> Airport? {
        let cleanedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanedCode.isEmpty else { return nil }
        let sql = """
            SELECT a.id, a.ident, a.type, a.name, a.latitude, a.longitude, a.elevation_feet,
                a.continent, a.country_iso2, a.region_code, a.municipality, a.city_id,
                a.scheduled_service, a.gps_code, a.iata_code, a.icao_code, a.local_code,
                COALESCE(NULLIF(a.timezone, ''), NULLIF(c.timezone, ''), '')
            FROM airports a
            LEFT JOIN cities c ON c.id = a.city_id
            WHERE a.iata_code = ?1 OR a.icao_code = ?1 OR a.ident = ?1 OR a.id = ?1
            ORDER BY a.scheduled_service DESC
            LIMIT 1
        """
        return try withStatement(sql) { statement in
            try bind(statement, cleanedCode, at: 1)
            guard try stepFirstRow(statement) else { return nil }
            return airportFromCurrentRow(statement)
        }
    }

    func searchAirlines(query: String, limit: Int = 30) throws -> [Airline] {
        guard !Task.isCancelled else { return [] }

        let queryContainsJapaneseKana = Self.containsJapaneseKana(query)
        let normalizedQueries = SearchNormalizer.queryVariants(
            for: query,
            includeRomajiForKana: !queryContainsJapaneseKana
        )
        guard !normalizedQueries.isEmpty else { return [] }
        let airlineSearchRankSQL = AirlineSearchRank.sqliteCaseExpression(
            column: "al.iata_code"
        )
        let sql = """
            SELECT DISTINCT al.id, al.name, al.alias, al.iata_code, al.icao_code,
                al.callsign, al.country, al.country_iso2, al.active, s.priority
            FROM airline_search_names s
            JOIN airlines al ON al.id = s.entity_id
            WHERE al.active = 1
                AND (s.normalized_name = ?1 OR s.normalized_name LIKE ?2)
            ORDER BY
                CASE
                    WHEN s.normalized_name = ?1 THEN 0
                    WHEN s.normalized_name LIKE ?2 THEN 1
                END,
                \(airlineSearchRankSQL) ASC,
                s.priority ASC,
                al.name ASC
            LIMIT ?3
        """
        var airlines: [Airline] = []
        var seenAirlineIDs: Set<String> = []

        var airlineCandidates: [Airline] = []
        for normalizedQuery in normalizedQueries {
            guard !Task.isCancelled else { return airlines }

            let matches = try withStatement(sql) { statement in
                try bind(statement, normalizedQuery, at: 1)
                try bind(statement, "\(normalizedQuery)%", at: 2)
                try bindInt(statement, limit + 40, at: 3)
                var matchedAirlines: [Airline] = []
                try forEachRow(in: statement) {
                    matchedAirlines.append(airlineFromCurrentRow(statement))
                }
                return matchedAirlines
            }

            airlineCandidates.append(contentsOf: matches)
        }

        for airline in sortedAirlineSearchMatches(airlineCandidates, normalizedQueries: normalizedQueries) {
            guard seenAirlineIDs.insert(airline.id).inserted else { continue }
            airlines.append(airline)
            if airlines.count >= limit { break }
        }

        if airlines.count < limit {
            appendAirlineAliasMatches(
                for: normalizedQueries,
                to: &airlines,
                seenAirlineIDs: &seenAirlineIDs,
                limit: limit
            )
        }

        return airlines
    }

    private func appendAirlineAliasMatches(
        for normalizedQueries: [String],
        to airlines: inout [Airline],
        seenAirlineIDs: inout Set<String>,
        limit: Int
    ) {
        for code in JapaneseSearchReadingAliases.matchingAirlineCodes(
            for: normalizedQueries
        ) where airlines.count < limit {
            guard !Task.isCancelled else { return }

            guard let airline = try? airline(matching: code) else {
                continue
            }
            guard seenAirlineIDs.insert(airline.id).inserted else {
                continue
            }
            airlines.append(airline)
        }
    }

    private nonisolated func sortedAirlineSearchMatches(
        _ matches: [Airline],
        normalizedQueries: [String]
    ) -> [Airline] {
        matches.sorted { first, second in
            let firstScore = normalizedQueries.map { first.searchScore(for: $0) }.max() ?? 0
            let secondScore = normalizedQueries.map { second.searchScore(for: $0) }.max() ?? 0
            if firstScore != secondScore {
                return firstScore > secondScore
            }

            let firstPriority = AirlineSearchRank.priority(for: first)
            let secondPriority = AirlineSearchRank.priority(for: second)
            if firstPriority != secondPriority {
                return firstPriority < secondPriority
            }

            return first.displayName.localizedCaseInsensitiveCompare(second.displayName) == .orderedAscending
        }
    }

    func airline(matching code: String) throws -> Airline? {
        let cleanedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanedCode.isEmpty else { return nil }
        let sql = """
            SELECT id, name, alias, iata_code, icao_code, callsign, country, country_iso2, active
            FROM airlines
            WHERE iata_code = ?1 OR icao_code = ?1 OR id = ?1
            ORDER BY active DESC
            LIMIT 1
        """
        return try withStatement(sql) { statement in
            try bind(statement, cleanedCode, at: 1)
            guard try stepFirstRow(statement) else { return nil }
            return airlineFromCurrentRow(statement)
        }
    }

    private func country(matchingISO2 iso2: String) throws -> Country? {
        let cleanedISO2 = iso2.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanedISO2.isEmpty else { return nil }
        let sql = """
            SELECT iso2, iso3, continent
            FROM countries
            WHERE iso2 = ?1
            LIMIT 1
        """
        return try withStatement(sql) { statement in
            try bind(statement, cleanedISO2, at: 1)
            guard try stepFirstRow(statement) else { return nil }
            return Country(
                iso2: columnString(statement, 0),
                iso3: columnString(statement, 1),
                continent: columnString(statement, 2),
                polygonParts: []
            )
        }
    }

    func directRoute(from origin: String, to destination: String) throws -> WanderlustRoute? {
        guard !Task.isCancelled else { return nil }

        let originCode = origin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let destinationCode = destination.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !originCode.isEmpty, !destinationCode.isEmpty else { return nil }
        let existsSQL = "SELECT 1 FROM routes WHERE origin = ?1 AND destination = ?2 LIMIT 1"
        let exists = try withStatement(existsSQL) { statement in
            try bind(statement, originCode, at: 1)
            try bind(statement, destinationCode, at: 2)
            return try stepFirstRow(statement)
        }
        guard exists else { return nil }

        let airlinesSQL = """
            SELECT airline_code FROM route_airlines
            WHERE origin = ?1 AND destination = ?2
            ORDER BY airline_code ASC
        """
        let airlineCodes = try withStatement(airlinesSQL) { statement in
            try bind(statement, originCode, at: 1)
            try bind(statement, destinationCode, at: 2)
            var codes: [String] = []
            try forEachRow(in: statement) {
                codes.append(columnString(statement, 0))
            }
            return codes
        }
        return WanderlustRoute(from: originCode, to: destinationCode, airlines: airlineCodes)
    }

    private func withStatement<Value>(_ sql: String, _ body: (OpaquePointer) throws -> Value) throws -> Value {
        let database = try databaseConnection()

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StaticDataStoreError.sqlite(message: lastErrorMessage(database))
        }
        guard let statement else {
            throw StaticDataStoreError.sqlite(message: "SQLite did not return a prepared statement.")
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func databaseConnection() throws -> OpaquePointer {
        if let database {
            return database
        }

        guard let url = Bundle.main.url(forResource: "WanderlustStaticData", withExtension: "sqlite") else {
            throw StaticDataStoreError.databaseNotFound
        }
        var openedDatabase: OpaquePointer?
        guard sqlite3_open_v2(url.path, &openedDatabase, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = openedDatabase.map(lastErrorMessage) ?? "Unable to open database."
            if let openedDatabase { sqlite3_close(openedDatabase) }
            throw StaticDataStoreError.sqlite(message: message)
        }
        guard let openedDatabase else {
            throw StaticDataStoreError.sqlite(message: "SQLite opened without returning a database handle.")
        }
        database = openedDatabase
        return openedDatabase
    }

    private func airportFromCurrentRow(_ statement: OpaquePointer) -> Airport {
        Airport(
            id: columnString(statement, 0),
            ident: columnString(statement, 1),
            type: columnString(statement, 2),
            name: columnString(statement, 3),
            latitude: sqlite3_column_double(statement, 4),
            longitude: sqlite3_column_double(statement, 5),
            elevationFeet: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 6)),
            continent: columnString(statement, 7),
            countryCode: columnString(statement, 8),
            regionCode: columnString(statement, 9),
            municipality: columnString(statement, 10),
            cityID: sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 11)),
            scheduledService: sqlite3_column_int(statement, 12) != 0,
            gpsCode: columnString(statement, 13),
            iataCode: columnString(statement, 14),
            localCode: columnString(statement, 16),
            timezone: columnString(statement, 17)
        )
    }

    private func airlineFromCurrentRow(_ statement: OpaquePointer) -> Airline {
        Airline(
            id: columnString(statement, 0),
            name: columnString(statement, 1),
            alias: columnString(statement, 2),
            iataCode: columnString(statement, 3),
            icaoCode: columnString(statement, 4),
            callsign: columnString(statement, 5),
            country: columnString(statement, 6),
            countryCode: columnString(statement, 7),
            active: sqlite3_column_int(statement, 8) == 0 ? "N" : "Y"
        )
    }

    private func bind(_ statement: OpaquePointer, _ value: String, at index: Int32) throws {
        let result = sqlite3_bind_text(statement, index, value, -1, wanderlustSQLiteTransient)
        try validateSQLiteResult(result, statement: statement)
    }

    private func bindInt(_ statement: OpaquePointer, _ value: Int, at index: Int32) throws {
        let boundedValue = min(max(value, Int(Int32.min)), Int(Int32.max))
        let result = sqlite3_bind_int(statement, index, Int32(boundedValue))
        try validateSQLiteResult(result, statement: statement)
    }

    private func stepFirstRow(_ statement: OpaquePointer) throws -> Bool {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw StaticDataStoreError.sqlite(message: lastErrorMessage(sqlite3_db_handle(statement)))
        }
    }

    private func forEachRow(in statement: OpaquePointer, _ body: () throws -> Void) throws {
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                try body()
            case SQLITE_DONE:
                return
            default:
                throw StaticDataStoreError.sqlite(message: lastErrorMessage(sqlite3_db_handle(statement)))
            }
        }
    }

    private func columnString(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    private func validateSQLiteResult(_ result: Int32, statement: OpaquePointer) throws {
        guard result == SQLITE_OK else {
            throw StaticDataStoreError.sqlite(message: lastErrorMessage(sqlite3_db_handle(statement)))
        }
    }

    private func lastErrorMessage(_ database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error."
        }
        return String(cString: message)
    }

    static func normalizedSearchText(_ value: String) -> String {
        SearchNormalizer.normalize(value)
    }

    private nonisolated func mergeAliasCities(
        _ aliasCities: [WanderlustCity],
        with baseCities: [WanderlustCity],
        limit: Int
    ) -> [WanderlustCity] {
        guard !aliasCities.isEmpty else {
            return Array(baseCities.prefix(limit))
        }

        var merged: [WanderlustCity] = []
        var seenCityIDs: Set<Int> = []
        for city in aliasCities + baseCities {
            guard seenCityIDs.insert(city.id).inserted else { continue }
            merged.append(city)
            if merged.count >= limit { break }
        }
        return merged
    }

    private nonisolated static func prefixUpperBound(for normalizedQuery: String) -> String {
        "\(normalizedQuery)\u{10FFFF}"
    }
}

enum StaticDataStoreError: LocalizedError {
    case databaseNotFound
    case sqlite(message: String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "WanderlustStaticData.sqlite was not found in the app bundle."
        case .sqlite(let message):
            return message
        }
    }
}

private enum StaticCityTravelDemandRank {
    nonisolated static func priority(
        for city: WanderlustCity
    ) -> Int {
        if city.normalizedCountryCode == "JP", city.travelDemandRank > 0 {
            return city.travelDemandRank
        }

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
        1853909: 20,
        1857910: 25,
        1848354: 30,
        2128295: 35,
        1863967: 40,
        1856035: 45,
        1862415: 50,
        1855612: 55,
        11790353: 60,
        11808021: 61,
        13353696: 62,
        11749713: 63,
        13353695: 64,
        11790369: 65,
        900100002: 66,
        900100001: 67,
        900100003: 68,
        900200001: 80,
        900200002: 81,
        900200003: 82,
        900200004: 83,
        900200005: 84,
        900200006: 85,
        900200007: 86,
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
        252919: 220,
        257055: 221,
        900300001: 222,
        900300002: 223,
        900300003: 224,
        900300004: 225,
        900300005: 226,
        900300006: 227,
        900300007: 228,
        900300008: 229,
        6204696: 230,
        6241325: 231,
        1622846: 232,
        1822214: 233,
        1580541: 234,
        900300009: 235,
        2553455: 236,
        5128581: 237
    ]
}
