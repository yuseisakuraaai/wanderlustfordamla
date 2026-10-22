import Foundation
import CoreLocation

// MARK: - Airport

struct Airport: Identifiable, Codable, Hashable, Sendable {
    let id: String

    let ident: String
    let type: String
    let name: String

    let latitude: Double
    let longitude: Double

    let elevationFeet: Int?

    let continent: String
    let countryCode: String
    let regionCode: String

    let municipality: String
    let cityID: Int?

    let scheduledService: Bool

    let gpsCode: String
    let iataCode: String
    let localCode: String

    let timezone: String

    nonisolated init(
        id: String = UUID().uuidString,
        ident: String = "",
        type: String = "",
        name: String,
        latitude: Double,
        longitude: Double,
        elevationFeet: Int? = nil,
        continent: String = "",
        countryCode: String = "",
        regionCode: String = "",
        municipality: String = "",
        cityID: Int? = nil,
        scheduledService: Bool = false,
        gpsCode: String = "",
        iataCode: String = "",
        localCode: String = "",
        timezone: String = ""
    ) {
        self.id = id
        self.ident = ident
        self.type = type
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.elevationFeet = elevationFeet
        self.continent = continent
        self.countryCode = countryCode
        self.regionCode = regionCode
        self.municipality = municipality
        self.cityID = cityID
        self.scheduledService = scheduledService
        self.gpsCode = gpsCode
        self.iataCode = iataCode
        self.localCode = localCode
        self.timezone = timezone
    }

    // MARK: - Coordinate

    nonisolated var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    nonisolated var isCoordinateValid: Bool {
        (-90.0...90.0).contains(latitude) &&
        (-180.0...180.0).contains(longitude)
    }

    // MARK: - Codes

    nonisolated var normalizedIATACode: String {
        cleaned(iataCode).uppercased()
    }

    nonisolated var normalizedICAOCode: String {
        let value = gpsCode.isEmpty ? ident : gpsCode
        return cleaned(value).uppercased()
    }

    nonisolated var normalizedCountryCode: String {
        cleaned(countryCode).uppercased()
    }

    nonisolated var bestCode: String {
        if !normalizedIATACode.isEmpty { return normalizedIATACode }
        if !normalizedICAOCode.isEmpty { return normalizedICAOCode }
        return cleaned(ident).uppercased()
    }

    // MARK: - Display

    nonisolated var displayName: String {
        WanderlustL10n.airportName(
            iataCode: bestCode,
            fallback: cleaned(name)
        )
    }

    nonisolated var displayMunicipality: String {
        let fallback = cleaned(municipality)

        if let localized = Self.localizedMunicipalityAlias(
            countryCode: normalizedCountryCode,
            municipality: fallback
        ) {
            return localized
        }

        if let cityID {
            let localizedByID = WanderlustL10n.cityName(
                id: String(cityID),
                fallback: fallback
            )
            if localizedByID != fallback {
                return localizedByID
            }
        }

        return WanderlustL10n.cityName(
            countryCode: normalizedCountryCode,
            name: fallback,
            fallback: fallback
        )
    }

    nonisolated private static func localizedMunicipalityAlias(
        countryCode: String,
        municipality: String
    ) -> String? {
        guard countryCode == "JP" else { return nil }
        return japaneseMunicipalityAliases[normalize(municipality)]
    }

    nonisolated private static let japaneseMunicipalityAliases: [String: String] = [
        "aguni": "粟国",
        "akita": "秋田",
        "amagi": "天城",
        "amakusa": "天草",
        "amami": "奄美",
        "aomori": "青森",
        "fukuoka": "福岡",
        "goto": "五島",
        "hachijo-machi": "八丈町",
        "hakodate": "函館",
        "hanamaki": "花巻",
        "higashikagura": "東神楽",
        "higashine": "東根",
        "hiroshima": "広島",
        "iki": "壱岐",
        "ishigaki": "石垣",
        "iwakuni": "岩国",
        "izu oshima": "伊豆大島",
        "izumo": "出雲",
        "kagoshima": "鹿児島",
        "kanazawa": "金沢",
        "kikai": "喜界",
        "kitaakita": "北秋田",
        "kitadaitojima": "北大東島",
        "kitakyushu": "北九州",
        "kobe": "神戸",
        "kumamoto": "熊本",
        "kumejima": "久米島",
        "kushiro": "釧路",
        "makinohara / shimada": "牧之原 / 島田",
        "masuda": "益田",
        "matsumoto": "松本",
        "matsuyama": "松山",
        "minamidaito": "南大東",
        "misawa": "三沢",
        "miyakejima": "三宅島",
        "miyakojima": "宮古島",
        "miyazaki": "宮崎",
        "monbetsu": "紋別",
        "nagasaki": "長崎",
        "nagoya": "名古屋",
        "naha": "那覇",
        "nakashibetsu": "中標津",
        "nankoku": "南国",
        "narita": "成田",
        "natori": "名取",
        "niigata": "新潟",
        "obihiro": "帯広",
        "oita": "大分",
        "okayama": "岡山",
        "okinoshima": "隠岐の島",
        "okushiri island": "奥尻島",
        "omitama": "小美玉",
        "osaka": "大阪",
        "rishiri": "利尻",
        "sado": "佐渡",
        "saga": "佐賀",
        "sapporo": "札幌",
        "shirahama": "白浜",
        "shonai": "庄内",
        "sukagawa": "須賀川",
        "takamatsu": "高松",
        "tanegashima": "種子島",
        "tarama": "多良間",
        "tokoname": "常滑",
        "tokushima": "徳島",
        "tokyo": "東京",
        "tottori": "鳥取",
        "toyama": "富山",
        "toyooka": "豊岡",
        "tsushima": "対馬",
        "ube": "宇部",
        "wadomari": "和泊",
        "wajima": "輪島",
        "wakkanai": "稚内",
        "yakushima": "屋久島",
        "yonago": "米子",
        "yonaguni": "与那国",
        "yoron": "与論",
        "ozora": "大空"
    ]

    nonisolated var displayTitle: String {
        guard !bestCode.isEmpty else { return displayName }
        return "\(bestCode) · \(displayName)"
    }

    nonisolated var displaySubtitle: String {
        [displayMunicipality, normalizedCountryCode]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    @MainActor var resolvedTimeZoneIdentifier: String {
        let cleanedTimeZone = cleaned(timezone)
        if !cleanedTimeZone.isEmpty {
            return cleanedTimeZone
        }

        if let cityID,
           let city = CityDataLoader.shared.city(withID: cityID),
           !city.timezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return city.timezone
        }

        return "UTC"
    }

    nonisolated var flagEmoji: String {
        let code = normalizedCountryCode
        guard code.count == 2 else { return "🌍" }
        let scalars = code.unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value)
        }
        guard scalars.count == 2 else { return "🌍" }
        return String(String.UnicodeScalarView(scalars))
    }

    // MARK: - Airport Type

    nonisolated var isLargeAirport: Bool { normalizedType == "large_airport" }
    nonisolated var isMediumAirport: Bool { normalizedType == "medium_airport" }
    nonisolated var isSmallAirport: Bool { normalizedType == "small_airport" }
    nonisolated var isHeliport: Bool { normalizedType == "heliport" }
    nonisolated var isClosed: Bool { normalizedType == "closed" }

    nonisolated var isCommercialAirport: Bool {
        scheduledService || isLargeAirport || isMediumAirport || !normalizedIATACode.isEmpty
    }

    nonisolated private var normalizedType: String {
        cleaned(type).lowercased()
    }

    // MARK: - Search

    nonisolated var searchableValues: [String] {
        localizedAirportNameVariants +
        JapaneseSearchReadingAliases.airportAliases(
            code: bestCode
        ) + [
            displayMunicipality,
            cleaned(municipality),
            cleaned(name),
            normalizedIATACode, normalizedICAOCode,
            cleaned(ident), cleaned(localCode), normalizedCountryCode
        ].filter { !$0.isEmpty }
    }

    private nonisolated var localizedAirportNameVariants: [String] {
        WanderlustL10n.localizedVariants(
            key: "airport.\(bestCode)",
            table: .airports,
            fallback: cleaned(name)
        )
    }

    nonisolated func matchesLocalizedAirportNamePrefix(
        for normalizedQueries: [String]
    ) -> Bool {
        localizedAirportNameVariants.contains { value in
            let normalizedValue = Self.normalize(value)
            return normalizedQueries.contains { query in
                normalizedValue.hasPrefix(query)
            }
        }
    }

    nonisolated func matches(query: String) -> Bool {
        let queryContainsJapaneseKana = JapaneseKanaRomajiSearch
            .containsJapaneseKana(query)
        let normalizedQueries = JapaneseKanaRomajiSearch.normalizedQueryVariants(
            query,
            normalizer: Self.normalize,
            includeRomajiForKana: !queryContainsJapaneseKana
        )

        guard !normalizedQueries.isEmpty else { return false }

        return searchableValues.contains { value in
            let normalizedValue = Self.normalize(value)
            return normalizedQueries.contains {
                normalizedValue == $0 ||
                    normalizedValue.hasPrefix($0) ||
                    (!queryContainsJapaneseKana &&
                        Self.hasWordPrefix(normalizedValue, query: $0))
            }
        }
    }

    nonisolated func searchScore(for query: String) -> Int {
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

        let normalizedIATA = Self.normalize(
            normalizedIATACode
        )

        let normalizedICAO = Self.normalize(
            normalizedICAOCode
        )

        let normalizedNameVariants = localizedAirportNameVariants
            .map(Self.normalize)
            .filter { !$0.isEmpty }

        let normalizedAliasVariants = JapaneseSearchReadingAliases.airportAliases(
            code: bestCode
        )
        .flatMap {
            JapaneseKanaRomajiSearch.normalizedQueryVariants(
                $0,
                normalizer: Self.normalize
            )
        }
        .filter { !$0.isEmpty }

        let normalizedMunicipality = Self.normalize(
            displayMunicipality
        )

        if normalizedQueries.contains(normalizedIATA) {
            return 20_000
        }

        if normalizedQueries.contains(normalizedICAO) {
            return 19_000
        }

        if normalizedQueries.contains(where: { query in
            normalizedAliasVariants.contains(query)
        }) {
            return 18_500
        }

        if normalizedQueries.contains(where: { query in
            normalizedNameVariants.contains(query)
        }) {
            return 18_000
        }

        if normalizedQueries.contains(normalizedMunicipality) {
            return 17_000
        }

        if normalizedQueries.contains(where: { query in
            normalizedNameVariants.contains { $0.hasPrefix(query) }
        }) {
            return 16_000
        }

        if normalizedQueries.contains(where: { query in
            normalizedAliasVariants.contains { $0.hasPrefix(query) }
        }) {
            return 15_500
        }

        if normalizedQueries.contains(where: { normalizedMunicipality.hasPrefix($0) }) {
            return 15_000
        }

        if !queryContainsJapaneseKana,
           normalizedQueries.contains(where: { query in
               normalizedNameVariants.contains {
                   Self.hasWordPrefix($0, query: query)
               }
           }) {
            return 14_000
        }

        if !queryContainsJapaneseKana,
           normalizedQueries.contains(where: { Self.hasWordPrefix(normalizedMunicipality, query: $0) }) {
            return 13_000
        }

        if normalizedQueries.contains(where: { normalizedIATA.hasPrefix($0) }) {
            return 12_000
        }

        if normalizedQueries.contains(where: { normalizedICAO.hasPrefix($0) }) {
            return 11_000
        }

        if searchableValues.contains(
            where: {
                let normalizedValue = Self.normalize($0)
                return normalizedQueries.contains {
                    normalizedValue == $0 || normalizedValue.hasPrefix($0)
                }
            }
        ) {
            return 10_000
        }

        if !queryContainsJapaneseKana,
           searchableValues.contains(where: {
               let normalizedValue = Self.normalize($0)
               return normalizedQueries.contains {
                   Self.hasWordPrefix(normalizedValue, query: $0)
               }
           }) {
            return 9_000
        }

        return 0
    }

    private nonisolated static func hasWordPrefix(
        _ candidate: String,
        query: String
    ) -> Bool {
        let escapedQuery = NSRegularExpression.escapedPattern(
            for: query
        )

        return candidate.range(
            of: "(^|[\\s\\-/・.])\(escapedQuery)",
            options: .regularExpression
        ) != nil
    }

    // MARK: - Encoding

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ident, forKey: .ident)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(latitude, forKey: .latitudeDeg)
        try container.encode(longitude, forKey: .longitudeDeg)
        try container.encodeIfPresent(elevationFeet, forKey: .elevationFeet)
        try container.encode(continent, forKey: .continent)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(regionCode, forKey: .regionCode)
        try container.encode(municipality, forKey: .municipality)
        try container.encodeIfPresent(cityID, forKey: .cityID)
        try container.encode(scheduledService, forKey: .scheduledService)
        try container.encode(gpsCode, forKey: .gpsCode)
        try container.encode(iataCode, forKey: .iataCode)
        try container.encode(localCode, forKey: .localCode)
        try container.encode(timezone, forKey: .timezone)
    }

    // MARK: - Codable Keys

    private enum CodingKeys: String, CodingKey {
        case id
        case underscoreID = "_id"

        case ident
        case type
        case name
        case defaultName

        case latitudeDeg = "latitude_deg"
        case longitudeDeg = "longitude_deg"

        case latitude
        case longitude
        case lat
        case lon
        case lng

        case elevationFeet = "elevation_ft"
        case elevationFt
        case elevation

        case continent

        case isoCountry = "iso_country"
        case country
        case countryCode = "country_code"
        case countryISO2

        case isoRegion = "iso_region"
        case region
        case regionCode = "region_code"
        case regionCodeValue = "regionCode"

        case municipality
        case city
        case cityID

        case scheduledService = "scheduled_service"
        case scheduledServiceValue = "scheduledService"
        case scheduled

        case gpsCode = "gps_code"
        case gpsCodeValue = "gpsCode"

        case iataCode = "iata_code"
        case iataCodeValue = "iataCode"
        case iata

        case icaoCode = "icao_code"
        case icaoCodeValue = "icaoCode"
        case icao

        case localCode = "local_code"
        case localCodeValue = "localCode"

        case timezone
        case tz

        case location
    }

    // MARK: - Decoding

    nonisolated init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        let decodedLocation = try container.decodeIfPresent(
            AirportGeoPoint.self,
            forKey: .location
        )

        let decodedID = Self.decodeString(
            from: container,
            keys: [
                .id,
                .underscoreID
            ]
        )

        ident = Self.decodeString(
            from: container,
            keys: [
                .ident,
                .icaoCode,
                .icao
            ]
        )

        type = Self.decodeString(
            from: container,
            keys: [
                .type
            ]
        )

        name = Self.decodeString(
            from: container,
            keys: [
                .name,
                .defaultName
            ]
        )

        latitude = Self.decodeDouble(
            from: container,
            keys: [
                .latitudeDeg,
                .latitude,
                .lat
            ]
        ) ?? decodedLocation?.latitude ?? 0

        longitude = Self.decodeDouble(
            from: container,
            keys: [
                .longitudeDeg,
                .longitude,
                .lon,
                .lng
            ]
        ) ?? decodedLocation?.longitude ?? 0

        elevationFeet = Self.decodeInt(
            from: container,
            keys: [
                .elevationFeet,
                .elevationFt,
                .elevation
            ]
        )

        continent = Self.decodeString(
            from: container,
            keys: [
                .continent
            ]
        )

        countryCode = Self.decodeString(
            from: container,
            keys: [
                .isoCountry,
                .countryCode,
                .countryISO2,
                .country
            ]
        )

        regionCode = Self.decodeString(
            from: container,
            keys: [
                .isoRegion,
                .regionCode,
                .regionCodeValue,
                .region
            ]
        )

        municipality = Self.decodeString(
            from: container,
            keys: [
                .municipality,
                .city
            ]
        )

        cityID = Self.decodeInt(
            from: container,
            keys: [
                .cityID
            ]
        )

        scheduledService = Self.decodeBool(
            from: container,
            keys: [
                .scheduledService,
                .scheduledServiceValue,
                .scheduled
            ]
        )

        gpsCode = Self.decodeString(
            from: container,
            keys: [
                .gpsCode,
                .gpsCodeValue,
                .icaoCode,
                .icaoCodeValue,
                .icao
            ]
        )

        iataCode = Self.decodeString(
            from: container,
            keys: [
                .iataCode,
                .iataCodeValue,
                .iata
            ]
        )

        localCode = Self.decodeString(
            from: container,
            keys: [
                .localCode,
                .localCodeValue
            ]
        )

        timezone = Self.decodeString(
            from: container,
            keys: [
                .timezone,
                .tz
            ]
        )

        if !decodedID.isEmpty {
            id = decodedID
        } else if !ident.isEmpty {
            id = ident
        } else if !iataCode.isEmpty {
            id = iataCode
        } else {
            id = [
                name,
                String(latitude),
                String(longitude)
            ]
            .joined(separator: "|")
        }
    }

    // MARK: - Flexible Decoding

    nonisolated private static func decodeString(
        from container:
            KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> String {
        for key in keys {
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
                return value
                    ? "true"
                    : "false"
            }
        }

        return ""
    }

    nonisolated private static func decodeDouble(
        from container:
            KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Double? {
        for key in keys {
            if let value = try? container.decode(
                Double.self,
                forKey: key
            ) {
                return value
            }

            if let value = try? container.decode(
                Int.self,
                forKey: key
            ) {
                return Double(value)
            }

            if let value = try? container.decode(
                String.self,
                forKey: key
            ),
               let number = Double(
                   value.trimmingCharacters(
                       in: .whitespacesAndNewlines
                   )
               ) {
                return number
            }
        }

        return nil
    }

    nonisolated private static func decodeInt(
        from container:
            KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Int? {
        for key in keys {
            if let value = try? container.decode(
                Int.self,
                forKey: key
            ) {
                return value
            }

            if let value = try? container.decode(
                Double.self,
                forKey: key
            ) {
                return Int(value)
            }

            if let value = try? container.decode(
                String.self,
                forKey: key
            ) {
                let cleanedValue = value
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                if let integer = Int(cleanedValue) {
                    return integer
                }

                if let double = Double(cleanedValue) {
                    return Int(double)
                }
            }
        }

        return nil
    }

    nonisolated private static func decodeBool(
        from container:
            KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Bool {
        for key in keys {
            if let value = try? container.decode(
                Bool.self,
                forKey: key
            ) {
                return value
            }

            if let value = try? container.decode(
                Int.self,
                forKey: key
            ) {
                return value != 0
            }

            if let value = try? container.decode(
                Double.self,
                forKey: key
            ) {
                return value != 0
            }

            if let value = try? container.decode(
                String.self,
                forKey: key
            ) {
                switch value
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .lowercased() {
                case "yes",
                     "true",
                     "1",
                     "y":
                    return true

                default:
                    return false
                }
            }
        }

        return false
    }

    // MARK: - Helpers

    nonisolated private func cleaned(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func normalize(
        _ text: String
    ) -> String {
        SearchNormalizer.normalize(text)
    }
}

enum AirportSearchRank {
    nonisolated static func priority(for airport: Airport) -> Int {
        priority(for: airport.normalizedIATACode)
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

    private nonisolated static let prioritizedIATACodes: [String] = [
        "ATL", "DXB", "HND", "DFW", "PVG", "ORD", "LHR", "IST", "CAN", "DEN",
        "DEL", "ICN", "LAX", "CDG", "PEK", "SIN", "AMS", "MAD", "SZX", "KUL",
        "FRA", "BKK", "JFK", "HKG", "MCO", "BCN", "TFU", "BOM", "MIA", "LAS",
        "CGK", "SFO", "DOH", "CLT", "TPE", "SEA", "BOS", "YYZ", "YVR", "MUC",
        "ZRH", "VIE", "CPH", "ARN", "HEL", "FCO", "MXP", "VCE", "ORY", "AUH",
        "SYD", "MEL", "AKL", "DPS", "HNL",
        "NRT", "KIX", "FUK", "CTS", "ITM", "OKA", "NGO", "SDJ", "KOJ", "KMJ",
        "HIJ", "MYJ", "ISG", "TAK", "NGS", "KMQ", "OIT", "AOJ", "AXT", "OKJ"
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

// MARK: - Airport Geo Point

private struct AirportGeoPoint:
    Codable,
    Hashable
{
    let type: String?
    let coordinates: [Double]

    nonisolated var longitude: Double {
        guard coordinates.indices.contains(0) else {
            return 0
        }

        return coordinates[0]
    }

    nonisolated var latitude: Double {
        guard coordinates.indices.contains(1) else {
            return 0
        }

        return coordinates[1]
    }
}
