import Foundation
import SwiftUI

enum JapaneseStatisticsFormatter {
    static func visitedCountries(_ count: Int) -> String {
        "訪問国: \(count)ヶ国"
    }

    static func visitedCities(_ count: Int) -> String {
        "\(count)都市"
    }

    static func trips(_ count: Int) -> String {
        "\(count)回"
    }

    static func flights(_ count: Int) -> String {
        count == 0 ? "なし" : "\(count)便"
    }

    static func visitedContinents(_ count: Int) -> String {
        "訪問大陸: \(count)大陸"
    }

    static func days(_ count: Int) -> String {
        "\(count)日間"
    }
}

enum JapaneseCountFormatter {
    static func visitedCountries(_ count: Int) -> String { JapaneseStatisticsFormatter.visitedCountries(count) }
    static func visitedCities(_ count: Int) -> String { JapaneseStatisticsFormatter.visitedCities(count) }
    static func trips(_ count: Int) -> String { JapaneseStatisticsFormatter.trips(count) }
    static func flights(_ count: Int) -> String { JapaneseStatisticsFormatter.flights(count) }
    static func visitedContinents(_ count: Int) -> String { JapaneseStatisticsFormatter.visitedContinents(count) }
    static func days(_ count: Int) -> String { JapaneseStatisticsFormatter.days(count) }
}

enum WanderlustCountKind {
    case city
    case flight
    case trip
}

struct WanderlustInlineCount: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .accessibilityHidden(true)
            Text(text)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

enum PluralizationFormatter {
    static func compactCount(_ count: Int, kind: WanderlustCountKind) -> String {
        switch kind {
        case .city:
            return compactCities(count)
        case .flight:
            return compactFlights(count)
        case .trip:
            return compactTrips(count)
        }
    }

    static func compactCities(_ count: Int) -> String {
        switch currentLanguageCode {
        case "ja":
            return "\(count)都市"
        case "de":
            return "\(count) \(count == 1 ? "Stadt" : "Städte")"
        default:
            return "\(count) \(count == 1 ? "City" : "Cities")"
        }
    }

    static func compactCountries(_ count: Int) -> String {
        localizedCount("compact_countries_count", count)
    }

    static func compactFlights(_ count: Int) -> String {
        switch currentLanguageCode {
        case "ja":
            return "\(count)便"
        case "de":
            return "\(count) \(count == 1 ? "Flug" : "Flüge")"
        default:
            return "\(count) \(count == 1 ? "Flight" : "Flights")"
        }
    }

    static func compactTrips(_ count: Int) -> String {
        switch currentLanguageCode {
        case "ja":
            return "\(count)回"
        case "de":
            return "\(count) \(count == 1 ? "Reise" : "Reisen")"
        default:
            return "\(count) \(count == 1 ? "Trip" : "Trips")"
        }
    }

    static func compactFlightSummary(_ count: Int) -> String {
        guard count > 0 else {
            switch currentLanguageCode {
            case "ja":
                return "なし"
            case "de":
                return "Keine"
            default:
                return "None"
            }
        }
        return compactFlights(count)
    }

    static func trips(_ count: Int) -> String {
        let languageCode = currentLanguageCode
        switch languageCode {
        case "ja":
            return JapaneseCountFormatter.trips(count)
        case "de":
            return "\(count) \(count == 1 ? "Reise" : "Reisen")"
        default:
            return "\(count) \(count == 1 ? "Trip" : "Trips")"
        }
    }

    static func cities(_ count: Int) -> String {
        let languageCode = currentLanguageCode
        switch languageCode {
        case "ja":
            return JapaneseCountFormatter.visitedCities(count)
        case "de":
            return "\(count) \(count == 1 ? "Stadt" : "Städte")"
        default:
            return "\(count) \(count == 1 ? "City" : "Cities")"
        }
    }

    static func countries(_ count: Int) -> String {
        let languageCode = currentLanguageCode
        switch languageCode {
        case "ja":
            return JapaneseCountFormatter.visitedCountries(count)
        case "de":
            return "\(count) \(count == 1 ? "besuchtes Land" : "besuchte Länder")"
        default:
            return "\(count) \(count == 1 ? "Visited Country" : "Visited Countries")"
        }
    }

    static func flights(_ count: Int) -> String {
        let languageCode = currentLanguageCode
        switch languageCode {
        case "ja":
            return JapaneseCountFormatter.flights(count)
        case "de":
            return "\(count) \(count == 1 ? "Flug" : "Flüge")"
        default:
            return "\(count) \(count == 1 ? "Flight" : "Flights")"
        }
    }

    static func flightSummary(_ count: Int) -> String {
        if count == 0 {
            let languageCode = currentLanguageCode
            if languageCode == "ja" {
                return JapaneseCountFormatter.flights(0)
            }
            if languageCode == "de" {
                return "Keine Flüge"
            }
            return WanderlustL10n.string(
                "No Flights",
                table: .statistics,
                fallback: "No flights"
            )
        }

        return flights(count)
    }

    static func days(_ count: Int) -> String {
        let languageCode = currentLanguageCode
        switch languageCode {
        case "ja":
            return JapaneseCountFormatter.days(count)
        case "de":
            return "\(count) \(count == 1 ? "Tag" : "Tage")"
        default:
            return "\(count) \(count == 1 ? "Day" : "Days")"
        }
    }

    static func visits(_ count: Int) -> String {
        let languageCode = currentLanguageCode
        if languageCode == "en" {
            return "\(count) \(count == 1 ? "time" : "times")"
        }

        return localizedCount("visits_count", count)
    }

    static func countrySummary(cities: Int, trips: Int) -> String {
        String(
            format: localizedFormat("country_summary", table: .general),
            locale: Locale.current,
            self.cities(cities),
            self.trips(trips)
        )
    }

    static func homeCountryConfirmed(_ countryName: String) -> String {
        String(
            format: localizedFormat("home_country_confirmed", table: .account),
            locale: Locale.current,
            countryName
        )
    }

    static func searchCity(in countryName: String) -> String {
        String(
            format: localizedFormat("search_city_in_country", table: .world),
            locale: Locale.current,
            countryName
        )
    }

    static func noTripsRecorded(to countryName: String) -> String {
        String(
            format: localizedFormat("no_trips_to_country", table: .trips),
            locale: Locale.current,
            countryName
        )
    }

    static func cityAccessibilityLabel(city: String, country: String) -> String {
        String(
            format: localizedFormat("city_country_accessibility_label", table: .trips),
            locale: Locale.current,
            city,
            country
        )
    }

    static func additionalCities(_ count: Int) -> String {
        localizedCount("additional_cities_count", count)
    }

    static func cityBullet(_ cityName: String) -> String {
        String(
            format: localizedFormat("city_bullet", table: .trips),
            locale: Locale.current,
            cityName
        )
    }

    static func flightDuration(hours: Int, minutes: Int) -> String {
        if hours == 0 {
            return localizedCount("minutes_count", minutes)
        }
        if minutes == 0 {
            return localizedCount("hours_count", hours)
        }
        let format = localizedFormat("hours_minutes_count", table: .statistics)
        if format == "hours_minutes_count" {
            let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
            return languageCode == "ja" ? "\(hours)時間\(minutes)分" : "\(hours)h \(minutes)m"
        }
        return String(
            format: format,
            locale: Locale.current,
            hours,
            minutes
        )
    }

    private static func localizedCount(_ key: String, _ count: Int) -> String {
        let format = localizedFormat(key, table: .statistics)
        if format == key {
            return fallbackCount(key, count)
        }
        return String.localizedStringWithFormat(format, count)
    }

    private static func localizedFormat(_ key: String, table: WanderlustStringTable) -> String {
        WanderlustL10n.string(key, table: table)
    }

    private static func fallbackCount(_ key: String, _ count: Int) -> String {
        let languageCode = currentLanguageCode
        if languageCode == "ja" {
            switch key {
            case "trips_count":
                return JapaneseCountFormatter.trips(count)
            case "cities_count":
                return JapaneseCountFormatter.visitedCities(count)
            case "countries_count":
                return JapaneseCountFormatter.visitedCountries(count)
            case "compact_countries_count":
                return "\(count)か国"
            case "flights_count":
                return JapaneseCountFormatter.flights(count)
            case "days_count":
                return "\(count)日間"
            case "visits_count":
                return "\(count)回"
            case "additional_cities_count":
                return "ほか\(count)つの都市"
            case "minutes_count":
                return "\(count)分"
            case "hours_count":
                return "\(count)時間"
            default:
                return "\(count)"
            }
        }

        switch key {
        case "trips_count":
            return "\(count) \(count == 1 ? "Trip" : "Trips")"
        case "cities_count":
            return "\(count) \(count == 1 ? "City" : "Cities")"
        case "countries_count":
            return "\(count) \(count == 1 ? "Visited Country" : "Visited Countries")"
        case "compact_countries_count":
            if languageCode == "de" {
                return "\(count) \(count == 1 ? "Land" : "Länder")"
            }
            return "\(count) \(count == 1 ? "Country" : "Countries")"
        case "flights_count":
            return "\(count) \(count == 1 ? "Flight" : "Flights")"
        case "days_count":
            return "\(count) \(count == 1 ? "Day" : "Days")"
        case "visits_count":
            return "\(count) \(count == 1 ? "time" : "times")"
        case "additional_cities_count":
            return "\(count) more \(count == 1 ? "city" : "cities")"
        case "minutes_count":
            return "\(count)m"
        case "hours_count":
            return "\(count)h"
        default:
            return "\(count)"
        }
    }

    private static var currentLanguageCode: String {
        let rawCode = Bundle.main.preferredLocalizations.first
            ?? Bundle.main.developmentLocalization
            ?? "en"
        return rawCode
            .split(separator: "@", maxSplits: 1)
            .first?
            .split(whereSeparator: { $0 == "_" || $0 == "-" })
            .first?
            .lowercased() ?? "en"
    }
}

enum WanderlustNumberFormatter {
    nonisolated static func percentageText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    nonisolated static func oneDecimalOrInteger(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.000_001 {
            return "\(Int(rounded.rounded()))"
        }

        return String(format: "%.1f", locale: Locale.current, rounded)
    }
}
