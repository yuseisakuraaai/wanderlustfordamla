import Foundation

enum WanderlustStringTable: String {
    case general = "Localizable"
    case airlines = "Airlines"
    case airports = "Airports"
    case world = "World"
    case trips = "Trips"
    case passport = "Passport"
    case statistics = "Statistics"
    case settings = "Settings"
    case account = "Account"
    case countries = "Countries"
    case continents = "Continents"
    case cities = "Cities"
    case errors = "Errors"
    case sort = "Sort"
}

enum WanderlustSortL10n {
    // Button label
    static var button: String { WanderlustL10n.string("sort.button", table: .sort) }

    // Sort field titles
    static var dateVisited: String { WanderlustL10n.string("sort.date.visited", table: .sort) }
    static var date: String { WanderlustL10n.string("sort.date", table: .sort) }
    static var name: String { WanderlustL10n.string("sort.name", table: .sort) }
    static var trips: String { WanderlustL10n.string("sort.trips", table: .sort) }
    static var cities: String { WanderlustL10n.string("sort.cities", table: .sort) }
    static var duration: String { WanderlustL10n.string("sort.duration", table: .sort) }
    static var flights: String { WanderlustL10n.string("sort.flights", table: .sort) }
    static var country: String { WanderlustL10n.string("sort.country", table: .sort) }
    static var cityName: String { WanderlustL10n.string("sort.city_name", table: .sort) }
    static var visits: String { WanderlustL10n.string("sort.visits", table: .sort) }
    static var lastVisited: String { WanderlustL10n.string("sort.last_visited", table: .sort) }
    static var departure: String { WanderlustL10n.string("sort.departure", table: .sort) }
    static var route: String { WanderlustL10n.string("sort.route", table: .sort) }
    static var airline: String { WanderlustL10n.string("sort.airline", table: .sort) }
    static var countries: String { WanderlustL10n.string("sort.countries", table: .sort) }

    // Sort direction labels
    static var ascending: String { WanderlustL10n.string("sort.ascending", table: .sort) }
    static var descending: String { WanderlustL10n.string("sort.descending", table: .sort) }
    static var newest: String { WanderlustL10n.string("sort.newest", table: .sort) }
    static var oldest: String { WanderlustL10n.string("sort.oldest", table: .sort) }
    static var most: String { WanderlustL10n.string("sort.most", table: .sort) }
    static var fewest: String { WanderlustL10n.string("sort.fewest", table: .sort) }
    static var longest: String { WanderlustL10n.string("sort.longest", table: .sort) }
    static var shortest: String { WanderlustL10n.string("sort.shortest", table: .sort) }
}

enum WanderlustL10n {
    nonisolated(unsafe) static var bundle: Bundle = .main

    nonisolated static func string(
        _ key: String,
        table: WanderlustStringTable,
        fallback: String = ""
    ) -> String {
        localizedStringIfAvailable(key, table: table) ?? (fallback.isEmpty ? key : fallback)
    }

    nonisolated static func localizedVariants(
        key: String,
        table: WanderlustStringTable,
        fallback: String
    ) -> [String] {
        var variants: [String] = []
        var seen = Set<String>()

        func append(_ value: String) {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            let identity = cleaned
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                .lowercased()
            guard seen.insert(identity).inserted else { return }
            variants.append(cleaned)
        }

        append(fallback)
        append(string(key, table: table, fallback: fallback))

        for languageCode in ["en", "ja", "de"] {
            if let localized = localizedStringIfAvailable(
                key,
                table: table,
                languageCode: languageCode
            ) {
                append(localized)
            }
        }

        return variants
    }

    nonisolated static func countryName(iso2: String) -> String {
        let code = iso2.uppercased()
        return string(
            "country.\(code)",
            table: .countries,
            fallback: code
        )
    }

    nonisolated static func continentName(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return cleaned }

        let key = cleaned
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")

        return string(
            "continent.\(key)",
            table: .continents,
            fallback: cleaned
        )
    }

    nonisolated static func cityName(id: String, fallback: String) -> String {
        let cleanedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedID.isEmpty else {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let localized = localizedStringIfAvailable("city.\(cleanedID)", table: .cities) {
            return localized
        }

        let keyComponents = cleanedID.split(separator: ".")
        if keyComponents.count > 2 {
            let keyWithoutStableID = keyComponents.dropLast().joined(separator: ".")
            if let localized = localizedStringIfAvailable("city.\(keyWithoutStableID)", table: .cities) {
                return localized
            }
        }

        return fallback
    }

    nonisolated static func cityName(
        countryCode: String,
        name: String,
        fallback: String = ""
    ) -> String {
        let cleanedCountryCode = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let nameKey = catalogKeyComponent(name, fallback: "")
        guard !cleanedCountryCode.isEmpty, !nameKey.isEmpty else {
            return fallback.isEmpty ? name : fallback
        }

        return cityName(
            id: "\(cleanedCountryCode).\(nameKey)",
            fallback: fallback.isEmpty ? name : fallback
        )
    }

    nonisolated static func airlineName(code: String, fallback: String) -> String {
        let cleanedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !cleanedCode.isEmpty,
           let localized = localizedStringIfAvailable("airline.\(cleanedCode)", table: .airlines) {
            return localized
        }

        let fallbackKey = catalogKeyComponent(fallback, fallback: "")
        if !fallbackKey.isEmpty,
           let localized = localizedStringIfAvailable("airline.\(fallbackKey)", table: .airlines) {
            return localized
        }

        return fallback
    }

    nonisolated static func airportName(iataCode: String, fallback: String) -> String {
        let cleanedCode = iataCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !cleanedCode.isEmpty,
           let localized = localizedStringIfAvailable("airport.\(cleanedCode)", table: .airports) {
            return localized
        }

        let fallbackKey = catalogKeyComponent(fallback, fallback: "")
        if !fallbackKey.isEmpty,
           let localized = localizedStringIfAvailable("airport.\(fallbackKey)", table: .airports) {
            return localized
        }

        return fallback
    }

    private nonisolated static func localizedStringIfAvailable(
        _ key: String,
        table: WanderlustStringTable,
        languageCode: String? = nil
    ) -> String? {
        let lookupBundle: Bundle
        if let languageCode,
           let path = bundle.path(forResource: languageCode, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            lookupBundle = languageBundle
        } else {
            lookupBundle = bundle
        }

        let sentinel = "__ATLAS_MISSING__\(key)"
        let localized = NSLocalizedString(
            key,
            tableName: table.rawValue,
            bundle: lookupBundle,
            value: sentinel,
            comment: ""
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !localized.isEmpty, localized != sentinel else {
            return nil
        }

        return localized
    }

    private nonisolated static func catalogKeyComponent(
        _ value: String,
        fallback: String
    ) -> String {
        let folded = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .uppercased()

        let components = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let key = components.joined(separator: "_")
        return key.isEmpty ? fallback : key
    }
}
