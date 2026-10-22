import Foundation
import CoreLocation

@MainActor
enum WanderlustNameResolver {
    // Country オブジェクトを直接受け取るオーバーロード（GeoJSONLoader.shared の再アクセスを避ける）
    static func countryName(for country: Country) -> String {
        localizedCountryName(country, fallback: country.iso2)
    }

    static func countryName(
        for countryCode: String,
        fallback: String = ""
    ) -> String {
        let cleanedCode = normalizedCountryCode(
            countryCode,
            fallback: fallback
        )

        if let country = GeoJSONLoader.shared.country(withISOCode: cleanedCode) {
            return localizedCountryName(country, fallback: fallback)
        }

        if let country = GeoJSONLoader.shared.country(named: countryCode) {
            return localizedCountryName(country, fallback: fallback)
        }

        if let country = GeoJSONLoader.shared.country(named: fallback) {
            return localizedCountryName(country, fallback: fallback)
        }

        if !cleanedCode.isEmpty, cleanedCode.count == 2 {
            return WanderlustL10n.countryName(iso2: cleanedCode)
        }

        let cleanedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedFallback.isEmpty ? cleanedCode : cleanedFallback
    }

    static func countryCode(
        from value: String,
        fallback: String = ""
    ) -> String {
        let normalizedAlias = normalizedCountryCode(value, fallback: fallback)
        if !normalizedAlias.isEmpty,
           GeoJSONLoader.shared.country(withISOCode: normalizedAlias) != nil {
            return normalizedAlias
        }

        let candidates = [value, fallback]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for candidate in candidates {
            if let country = GeoJSONLoader.shared.country(withISOCode: candidate) ?? GeoJSONLoader.shared.country(named: candidate) {
                return country.isoCode
            }
        }

        return ""
    }

    nonisolated static func normalizedCountryCode(
        _ value: String,
        fallback: String = ""
    ) -> String {
        let candidates = [value, fallback]
            .map { normalize($0) }
            .filter { !$0.isEmpty }

        let aliasMap: [String: String] = [
            "uk": "GB",
            "gb": "GB",
            "gbr": "GB",
            "united kingdom": "GB",
            "great britain": "GB",
            "britain": "GB",
            "england": "GB",
            "scotland": "GB",
            "wales": "GB",
            "northern ireland": "GB",
            "vereinigtes konigreich": "GB",
            "vereinigtes koenigreich": "GB",
            "イギリス": "GB",
            "英国": "GB",
            "bosnia and herzegovina": "BA",
            "bosnia": "BA",
            "brunei": "BN",
            "brunei darussalam": "BN",
            "cape verde": "CV",
            "cabo verde": "CV",
            "czech republic": "CZ",
            "czechia": "CZ",
            "china (people's republic of)": "CN",
            "china people's republic of": "CN",
            "people s republic of china": "CN",
            "democratic people's republic of korea": "KP",
            "democratic people s republic of korea": "KP",
            "korea, democratic people's republic of": "KP",
            "korea democratic people s republic of": "KP",
            "north korea": "KP",
            "republic of korea": "KR",
            "korea, republic of": "KR",
            "korea republic of": "KR",
            "south korea": "KR",
            "iran, islamic republic of": "IR",
            "iran islamic republic of": "IR",
            "lao pdr": "LA",
            "moldova, republic of": "MD",
            "moldova republic of": "MD",
            "russia": "RU",
            "russian federation": "RU",
            "syria": "SY",
            "syrian arab republic": "SY",
            "taiwan": "TW",
            "taiwan province of china": "TW",
            "tanzania": "TZ",
            "tanzania, united republic of": "TZ",
            "united republic of tanzania": "TZ",
            "hong kong (sar), china": "HK",
            "macao (sar), china": "MO",
            "macau": "MO",
            "chinese taipei": "TW",
            "new caledonia": "NC",
            "guadeloupe": "GP",
            "greenland": "GL",
            "cook islands": "CK",
            "french polynesia": "PF",
            "canadian territories": "CA",
            "faroe islands": "FO",
            "turkey": "TR",
            "turkiye": "TR",
            "bermuda": "BM",
            "cayman islands": "KY",
            "turks and caicos islands": "TC",
            "saint barthélemy": "BL",
            "saint barthelemy": "BL",
            "st barthelemy": "BL",
            "netherlands antilles": "SX",
            "aruba": "AW",
            "usa": "US",
            "united states": "US",
            "united states of america": "US",
            "america": "US",
            "venezuela": "VE",
            "bolivarian republic of venezuela": "VE"
        ]

        for candidate in candidates {
            if let alias = aliasMap[candidate] {
                return alias
            }
        }

        let rawCode = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if rawCode.count == 2 || rawCode.count == 3 {
            return rawCode
        }

        return fallback
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    static func cityName(
        for cityID: Int?,
        fallback: String = ""
    ) -> String {
        if let cityID {
            return WanderlustL10n.cityName(
                id: String(cityID),
                fallback: fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let cleanedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedFallback
    }

    static func cityName(
        for city: WanderlustCity,
        fallback: String = ""
    ) -> String {
        WanderlustL10n.cityName(
            id: city.localizationID,
            fallback: cityFallbackName(for: city, fallback: fallback)
        )
    }

    static func resolveCityID(
        name: String,
        countryCode: String,
        latitude: Double,
        longitude: Double
    ) -> Int? {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let candidates: [WanderlustCity]
        if !normalizedCode.isEmpty {
            candidates = CityDataLoader.shared.cities(inCountryCode: normalizedCode)
        } else {
            candidates = CityDataLoader.shared.cities
        }

        if latitude != 0 || longitude != 0 {
            let coordinate = CLLocation(latitude: latitude, longitude: longitude)
            let nearby = candidates.min { first, second in
                let firstDistance = coordinate.distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude))
                let secondDistance = coordinate.distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
                return firstDistance < secondDistance
            }

            if let nearby {
                let distance = coordinate.distance(from: CLLocation(latitude: nearby.latitude, longitude: nearby.longitude))
                if distance < 25_000 || namesMatch(cleanedName, city: nearby) {
                    return nearby.id
                }
            }
        }

        return candidates.first { namesMatch(cleanedName, city: $0) }?.id
    }

    private static func localizedCountryName(
        _ country: Country,
        fallback: String
    ) -> String {
        let cleanedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCode = country.iso2.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedCode.isEmpty else {
            return cleanedFallback
        }
        return WanderlustL10n.countryName(iso2: cleanedCode)
    }

    private static func namesMatch(_ name: String, city: WanderlustCity) -> Bool {
        let normalizedName = normalize(name)
        guard !normalizedName.isEmpty else { return false }
        return city.searchableNames.contains {
            normalize($0) == normalizedName
        }
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
    }

    private static func cityFallbackName(for city: WanderlustCity, fallback: String) -> String {
        let canonical = city.displayName
        if !canonical.isEmpty { return canonical }

        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
