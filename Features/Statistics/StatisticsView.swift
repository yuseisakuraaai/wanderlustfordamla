import SwiftUI
import Charts

// MARK: - Statistics View

struct StatisticsView: View {
    @ObservedObject var tripStore: TripStore
    @State private var snapshot = StatisticsSnapshot.empty

    private var trips: [Trip] {
        tripStore.trips
    }

    private var statisticsFingerprint: StatisticsFingerprint {
        StatisticsFingerprint(trips: trips, tripGroups: tripStore.tripGroups)
    }

    var body: some View {
        Group {
            if trips.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: WanderlustSpacing.xLarge) {
                        statsGrid
                        if snapshot.hasHighlights {
                            highlightsCard
                        }
                        if !snapshot.tripsPerYear.isEmpty {
                            tripsChartCard
                        }
                        averagesCard
                    }
                    // iPad / 横向きで本文が横に伸びきらないようにする。
                    .wanderlustReadableWidth()
                    .padding(.horizontal, WanderlustSpacing.large)
                    .padding(.top, WanderlustSpacing.xLarge)
                    .padding(.bottom, WanderlustSpacing.xLarge)
                }
            }
        }
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
        .navigationTitle(WanderlustL10n.string("Statistics", table: .statistics))
        .toolbarTitleDisplayMode(.large)
        .task(id: statisticsFingerprint) {
            await rebuildSnapshot()
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            NavigationLink {
                StatisticsCountriesList(countries: snapshot.uniqueCountryRows)
            } label: {
                HealthStatCard(title: String(localized: "Countries"), value: "\(snapshot.uniqueCountryNames.count)", icon: "globe", color: .blue, showsChevron: true)
            }
            NavigationLink {
                StatisticsCitiesList(cities: snapshot.uniqueCities)
            } label: {
                HealthStatCard(title: statisticCardTitle(.city), value: "\(snapshot.uniqueCityCount)", icon: "building.2.fill", color: .green, showsChevron: true)
            }
            NavigationLink {
                StatisticsTripsList(tripStore: tripStore)
            } label: {
                HealthStatCard(title: statisticCardTitle(.trip), value: "\(snapshot.journeyCount)", icon: "suitcase.fill", color: .orange, showsChevron: true)
            }
            NavigationLink {
                StatisticsFlightsTripList(tripStore: tripStore)
            } label: {
                HealthStatCard(title: statisticCardTitle(.flight), value: "\(snapshot.totalFlights)", icon: "airplane.departure", color: .purple, showsChevron: true)
            }
            NavigationLink {
                StatisticsContinentsList(groups: snapshot.continentGroups)
            } label: {
                HealthStatCard(title: WanderlustL10n.string("Continents", table: .statistics), value: "\(snapshot.continentCount)", icon: "map.fill", color: .teal, showsChevron: true)
            }
            HealthStatCard(title: WanderlustL10n.string("World", table: .world), value: WanderlustNumberFormatter.percentageText(min(snapshot.worldCompletion, 1) * 100), icon: "globe.americas.fill", color: .red)
        }
        .buttonStyle(.plain)
    }

    private enum StatisticCardKind {
        case city
        case trip
        case flight
    }

    private func statisticCardTitle(_ kind: StatisticCardKind) -> String {
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        switch (kind, languageCode) {
        case (.city, "ja"):
            return "都市"
        case (.trip, "ja"):
            return "旅行"
        case (.flight, "ja"):
            return "フライト"
        case (.city, "de"):
            return "Städte"
        case (.trip, "de"):
            return "Reisen"
        case (.flight, "de"):
            return "Flüge"
        case (.city, _):
            return "Cities"
        case (.trip, _):
            return "Trips"
        case (.flight, _):
            return "Flights"
        }
    }

    // MARK: - Chart

    private var tripsChartCard: some View {
        VStack(alignment: .leading, spacing: WanderlustSpacing.medium) {
            WanderlustSectionHeader(title: WanderlustL10n.string("Trips Per Year", table: .statistics))

            Chart(snapshot.tripsPerYear, id: \.year) { item in
                BarMark(
                    x: .value(String(localized: "Year"), String(item.year)),
                    y: .value(WanderlustSortL10n.trips, item.count)
                )
                .foregroundStyle(.blue.gradient)
                // `.cornerRadius(_:)` は iOS 17 以降非推奨
                .clipShape(.rect(cornerRadius: 6))
            }
            .frame(height: 160)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .wanderlustCard(radius: WanderlustRadius.xLarge, padding: WanderlustSpacing.large)
    }

    // MARK: - Highlights

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            WanderlustSectionHeader(title: WanderlustL10n.string("Highlights", table: .statistics))
                .padding(.bottom, WanderlustSpacing.medium)

            if let (name, flag, count) = snapshot.mostVisitedCountry {
                HighlightRow(
                    icon: flag,
                    isEmoji: true,
                    color: .blue,
                    label: WanderlustL10n.string("Most Visited Country", table: .statistics),
                    title: name,
                    detail: PluralizationFormatter.visits(count)
                )
                Divider().padding(.leading, 56)
            }

            if let (name, _, flag, count) = snapshot.mostVisitedCity {
                HighlightRow(
                    icon: flag,
                    isEmoji: true,
                    color: .green,
                    label: WanderlustL10n.string("Most Visited City", table: .statistics),
                    title: name,
                    detail: PluralizationFormatter.visits(count)
                )
                Divider().padding(.leading, 56)
            }

            if let (trip, days, flag) = snapshot.longestTrip {
                HighlightRow(
                    icon: flag,
                    isEmoji: true,
                    color: .orange,
                    label: WanderlustL10n.string("Longest Trip", table: .statistics),
                    title: StatisticsSnapshot.monthRange(start: trip.startDate, end: trip.endDate),
                    detail: PluralizationFormatter.days(days)
                )
                Divider().padding(.leading, 56)
            }

            HighlightRow(
                icon: "calendar",
                isEmoji: false,
                color: .yellow,
                label: WanderlustL10n.string("Total Trip Days", table: .statistics),
                title: PluralizationFormatter.days(snapshot.totalTravelDays),
                detail: ""
            )
        }
        .wanderlustCard(radius: WanderlustRadius.xLarge, padding: WanderlustSpacing.large)
    }

    // MARK: - Averages

    private var averagesCard: some View {
        VStack(alignment: .leading, spacing: WanderlustSpacing.medium) {
            WanderlustSectionHeader(title: WanderlustL10n.string("Averages", table: .statistics))

            // 横 3 列だと値とラベルが窮屈になるため、常に縦積みにする。
            VStack(spacing: WanderlustSpacing.medium) {
                averageCards
            }
        }
        .wanderlustCard(radius: WanderlustRadius.xLarge, padding: WanderlustSpacing.large)
    }

    private func averageUnit(_ key: String, fallback: String) -> String {
        WanderlustL10n.string(key, table: .statistics, fallback: fallback)
    }

    private func localizedAverageUnit(japanese: String, english: String, german: String) -> String {
        switch Bundle.main.preferredLocalizations.first?.split(separator: "-").first {
        case "ja": return japanese
        case "de": return german
        default: return english
        }
    }

    @ViewBuilder
    private var averageCards: some View {
        AverageStatCard(
            title: WanderlustL10n.string("Trips / Year", table: .statistics),
            value: snapshot.tripsPerYearAvg,
            unit: averageUnit("Trips per year unit", fallback: localizedAverageUnit(japanese: "回", english: "trips", german: "Reisen"))
        )
        AverageStatCard(
            title: WanderlustL10n.string("Days / Trip", table: .statistics),
            value: snapshot.avgTripDays,
            unit: averageUnit("Days unit", fallback: localizedAverageUnit(japanese: "日", english: "days", german: "Tage"))
        )
        AverageStatCard(
            title: WanderlustL10n.string("Cities / Trip", table: .statistics),
            value: snapshot.avgCitiesPerTrip,
            unit: averageUnit("Cities unit", fallback: localizedAverageUnit(japanese: "都市", english: "cities", german: "Städte"))
        )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        WanderlustEmptyStateView(
            systemImage: "chart.bar.xaxis",
            title: WanderlustL10n.string("No Data Yet", table: .statistics),
            message: WanderlustL10n.string("Add your first trip to see your travel statistics here.", table: .statistics)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, WanderlustSpacing.xLarge)
    }

    // MARK: - Snapshot

    private func rebuildSnapshot() async {
        let trips = trips
        let tripGroups = tripStore.tripGroups
        let lookup = CountryLookup()
        guard !Task.isCancelled else { return }
        let rebuilt = await Task.detached(priority: .userInitiated) {
            StatisticsSnapshot.make(from: trips, tripGroups: tripGroups, lookup: lookup)
        }.value
        guard !Task.isCancelled else { return }
        snapshot = rebuilt
    }

}

private struct StatisticsFingerprint: Hashable {
    let tripCount: Int
    let tripGroupCount: Int
    let cityCount: Int
    let flightCount: Int
    let latestUpdate: TimeInterval

    init(trips: [Trip], tripGroups: [TripGroup]) {
        tripCount = trips.count
        tripGroupCount = tripGroups.count
        cityCount = trips.reduce(0) { $0 + $1.cities.count }
        flightCount = trips.reduce(0) { $0 + $1.flights.count }
        latestUpdate = max(
            trips.map(\.updatedAt.timeIntervalSinceReferenceDate).max() ?? 0,
            tripGroups.map(\.updatedAt.timeIntervalSinceReferenceDate).max() ?? 0
        )
    }
}

private struct CountryLookup: Sendable {
    struct Info: Sendable {
        let displayName: String
        let flagEmoji: String
        let continent: String
    }

    private let byISO: [String: Info]
    private let byName: [String: Info]

    @MainActor
    init() {
        var byISO: [String: Info] = [:]
        var byName: [String: Info] = [:]
        for country in GeoJSONLoader.shared.countries {
            let info = Info(
                displayName: country.displayName,
                flagEmoji: country.flagEmoji,
                continent: country.continent
            )
            byISO[country.iso2] = info
            byName[country.displayName.lowercased()] = info
        }
        self.byISO = byISO
        self.byName = byName
    }

    nonisolated func lookup(isoCode code: String) -> Info? { byISO[code.uppercased()] }
    nonisolated func lookup(named name: String) -> Info? { byName[name.lowercased()] }
}

private struct StatisticsCountryRow: Identifiable, Hashable {
    let id: String
    let name: String
    let flag: String
    let tripCount: Int
    let cityCount: Int
    let lastVisited: Date?
}

private struct StatisticsCityRow: Identifiable, Hashable {
    let id: String
    let name: String
    let countryName: String
    let countryFlag: String
    let visitCount: Int
    let lastVisited: Date?
}

private struct StatisticsContinentGroup: Identifiable, Hashable {
    var id: String { continent }
    let continent: String
    let countries: [StatisticsCountryRow]
}

private struct StatisticsTripRow: Identifiable, Hashable {
    let id: UUID
    let displayTitle: String
    let startDate: Date
    let endDate: Date
    let dateRangeText: String
    let countryName: String
    let countryFlag: String
    let cityNames: String
    let cityCount: Int
    let flightCount: Int
}

private struct StatisticsSelectedTrip: Identifiable, Hashable {
    let id: UUID
}

private enum StatisticsCountrySortOption: String, CaseIterable, Identifiable {
    case nameAscending
    case nameDescending
    case tripCountDescending
    case tripCountAscending
    case cityCountDescending
    case cityCountAscending
    case lastVisitedDescending
    case lastVisitedAscending

    var id: String { rawValue }

    var accessibilityTitle: String {
        switch self {
        case .nameAscending: return String(localized: "Name, A to Z")
        case .nameDescending: return String(localized: "Name, Z to A")
        case .tripCountDescending: return String(localized: "Trips, Most First")
        case .tripCountAscending: return String(localized: "Trips, Fewest First")
        case .cityCountDescending: return String(localized: "Cities, Most First")
        case .cityCountAscending: return String(localized: "Cities, Fewest First")
        case .lastVisitedDescending: return String(localized: "Last Visited, Newest First")
        case .lastVisitedAscending: return String(localized: "Last Visited, Oldest First")
        }
    }
}

private enum StatisticsSortDirection: String {
    case ascending
    case descending
}

private enum StatisticsCitySortOption: String, CaseIterable, Identifiable {
    case countryAscending
    case countryDescending
    case cityNameAscending
    case cityNameDescending
    case visitCountDescending
    case visitCountAscending
    case lastVisitedDescending
    case lastVisitedAscending

    var id: String { rawValue }

    var accessibilityTitle: String {
        switch self {
        case .countryAscending, .countryDescending:
            return self == .countryAscending ? String(localized: "Country, A to Z") : String(localized: "Country, Z to A")
        case .cityNameAscending, .cityNameDescending:
            return self == .cityNameAscending ? String(localized: "City Name, A to Z") : String(localized: "City Name, Z to A")
        case .visitCountDescending, .visitCountAscending:
            return self == .visitCountDescending ? String(localized: "Visits, Most First") : String(localized: "Visits, Fewest First")
        case .lastVisitedDescending, .lastVisitedAscending:
            return self == .lastVisitedDescending ? String(localized: "Last Visited, Newest First") : String(localized: "Last Visited, Oldest First")
        }
    }
}

private enum StatisticsTripSortOption: String, CaseIterable, Identifiable {
    case dateDescending
    case dateAscending
    case countryAscending
    case countryDescending
    case durationDescending
    case durationAscending
    case cityCountDescending
    case cityCountAscending
    case flightCountDescending
    case flightCountAscending

    var id: String { rawValue }

    var accessibilityTitle: String {
        switch self {
        case .dateDescending: return String(localized: "Date, Newest First")
        case .dateAscending: return String(localized: "Date, Oldest First")
        case .countryAscending: return String(localized: "Country, A to Z")
        case .countryDescending: return String(localized: "Country, Z to A")
        case .durationDescending: return String(localized: "Duration, Longest First")
        case .durationAscending: return String(localized: "Duration, Shortest First")
        case .cityCountDescending: return String(localized: "Cities, Most First")
        case .cityCountAscending: return String(localized: "Cities, Fewest First")
        case .flightCountDescending: return String(localized: "Flights, Most First")
        case .flightCountAscending: return String(localized: "Flights, Fewest First")
        }
    }
}

private enum StatisticsFlightTripSortOption: String, CaseIterable, Identifiable {
    case dateDescending
    case dateAscending
    case countryAscending
    case countryDescending
    case flightCountDescending
    case flightCountAscending

    var id: String { rawValue }

    var accessibilityTitle: String {
        switch self {
        case .dateDescending: return String(localized: "Date, Newest First")
        case .dateAscending: return String(localized: "Date, Oldest First")
        case .countryAscending: return String(localized: "Country, A to Z")
        case .countryDescending: return String(localized: "Country, Z to A")
        case .flightCountDescending: return String(localized: "Flights, Most First")
        case .flightCountAscending: return String(localized: "Flights, Fewest First")
        }
    }
}

private enum StatisticsFlightSortOption: String, CaseIterable, Identifiable {
    case departureAscending
    case departureDescending
    case routeAscending
    case routeDescending
    case airlineAscending
    case airlineDescending

    var id: String { rawValue }

    var accessibilityTitle: String {
        switch self {
        case .departureAscending: return String(localized: "Departure, Oldest First")
        case .departureDescending: return String(localized: "Departure, Newest First")
        case .routeAscending: return String(localized: "Route, A to Z")
        case .routeDescending: return String(localized: "Route, Z to A")
        case .airlineAscending: return String(localized: "Airline, A to Z")
        case .airlineDescending: return String(localized: "Airline, Z to A")
        }
    }
}

private enum StatisticsContinentSortOption: String, CaseIterable, Identifiable {
    case nameAscending
    case nameDescending
    case countryCountDescending
    case countryCountAscending
    case tripCountDescending
    case tripCountAscending

    var id: String { rawValue }

    var accessibilityTitle: String {
        switch self {
        case .nameAscending: return String(localized: "Name, A to Z")
        case .nameDescending: return String(localized: "Name, Z to A")
        case .countryCountDescending: return String(localized: "Countries, Most First")
        case .countryCountAscending: return String(localized: "Countries, Fewest First")
        case .tripCountDescending: return String(localized: "Trips, Most First")
        case .tripCountAscending: return String(localized: "Trips, Fewest First")
        }
    }
}

private struct StatisticsSnapshot {
    var uniqueCountryNames: [String]
    var uniqueCountryRows: [StatisticsCountryRow]
    var uniqueCities: [StatisticsCityRow]
    var totalFlights: Int
    var continentCount: Int
    var worldCompletion: Double
    var mostVisitedCountry: (name: String, flag: String, count: Int)?
    var mostVisitedCity: (name: String, country: String, flag: String, count: Int)?
    var longestTrip: (trip: Trip, days: Int, flag: String)?
    var totalTravelDays: Int
    var journeyCount: Int
    var tripsPerYear: [(year: Int, count: Int)]
    var tripsPerYearAvg: String
    var avgTripDays: String
    var avgCitiesPerTrip: String
    var countriesByContinent: [(continent: String, countries: [String])]
    var continentGroups: [StatisticsContinentGroup]
    var tripRows: [StatisticsTripRow]

    var uniqueCityCount: Int { uniqueCities.count }
    var hasHighlights: Bool { mostVisitedCountry != nil || mostVisitedCity != nil || longestTrip != nil }

    static let empty = StatisticsSnapshot(
        uniqueCountryNames: [],
        uniqueCountryRows: [],
        uniqueCities: [],
        totalFlights: 0,
        continentCount: 0,
        worldCompletion: 0,
        mostVisitedCountry: nil,
        mostVisitedCity: nil,
        longestTrip: nil,
        totalTravelDays: 0,
        journeyCount: 0,
        tripsPerYear: [],
        tripsPerYearAvg: "—",
        avgTripDays: "—",
        avgCitiesPerTrip: "—",
        countriesByContinent: [],
        continentGroups: [],
        tripRows: []
    )

    nonisolated static func make(from trips: [Trip], tripGroups: [TripGroup], lookup: CountryLookup) -> StatisticsSnapshot {
        // 訪問国の数え方は VisitedCountryAggregator を唯一の正とする。
        // （以前はここで独自に Set を組み立てていたため World / Passport と件数がズレていた）
        let uniqueCountryNames = VisitedCountryAggregator
            .countryKeys(in: trips)
            .map(\.rawValue)
            .sorted()
        let journeys = statisticsJourneys(from: tripGroups, trips: trips)

        var countryTripIDs: [String: Set<UUID>] = [:]
        var countryCityKeys: [String: Set<String>] = [:]
        var countryLastVisited: [String: Date] = [:]
        var citiesByKey: [String: (city: VisitedCity, tripIDs: Set<UUID>, lastVisited: Date)] = [:]

        for trip in trips {
            let countryKeys = VisitedCountryAggregator.countryKeys(in: [trip]).map(\.rawValue)
            for key in countryKeys {
                countryTripIDs[key, default: []].insert(trip.id)
                countryLastVisited[key] = max(countryLastVisited[key] ?? .distantPast, trip.endDate)
            }

            var seenCityKeysInTrip: Set<String> = []
            for city in trip.cities {
                let countryKey = WanderlustNameResolver.normalizedCountryCode(
                    city.countryCode,
                    fallback: city.countryName
                )
                let cityKey = city.geonameID.map { "g\($0)" } ?? "\(city.name)|\(countryKey)"
                countryCityKeys[countryKey, default: []].insert(cityKey)

                let cityLastVisited = city.periods.map(\.endDate).max() ?? trip.endDate
                var cityEntry = citiesByKey[cityKey] ?? (city, [], cityLastVisited)
                if seenCityKeysInTrip.insert(cityKey).inserted {
                    cityEntry.tripIDs.insert(trip.id)
                }
                cityEntry.lastVisited = max(cityEntry.lastVisited, cityLastVisited)
                citiesByKey[cityKey] = cityEntry
            }
        }

        let uniqueCountryRows = uniqueCountryNames.map {
            makeCountryRow(
                $0,
                lookup: lookup,
                tripCount: countryTripIDs[$0]?.count ?? 0,
                cityCount: countryCityKeys[$0]?.count ?? 0,
                lastVisited: countryLastVisited[$0]
            )
        }

        let uniqueCities = citiesByKey.map { key, value in
            let countryCode = WanderlustNameResolver.normalizedCountryCode(
                value.city.countryCode,
                fallback: value.city.countryName
            )
            let info = lookup.lookup(isoCode: countryCode) ?? lookup.lookup(named: value.city.countryName)
            return StatisticsCityRow(
                id: key,
                name: localizedCityName(value.city),
                countryName: info?.displayName ?? value.city.countryName,
                countryFlag: info?.flagEmoji ?? flagEmoji(countryCode: countryCode),
                visitCount: value.tripIDs.count,
                lastVisited: value.lastVisited
            )
        }
        .sorted {
            if $0.countryName != $1.countryName {
                return $0.countryName.localizedCaseInsensitiveCompare($1.countryName) == .orderedAscending
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let totalFlights = trips.reduce(0) { $0 + $1.flights.count }
        let totalTravelDays = trips.reduce(0) {
            $0 + tripDurationDays($1)
        }

        var yearCounts: [Int: Int] = [:]
        for journey in journeys {
            yearCounts[Calendar.current.component(.year, from: journey.startDate), default: 0] += 1
        }
        let tripsPerYear = yearCounts
            .map { (year: $0.key, count: $0.value) }
            .sorted { $0.year < $1.year }

        let mostVisitedCountry = makeMostVisitedCountry(from: trips, lookup: lookup)
        let mostVisitedCity = makeMostVisitedCity(from: trips, lookup: lookup)
        let longestTrip = trips
            .compactMap { trip -> (Trip, Int)? in
                let days = tripDurationDays(trip)
                return days > 0 ? (trip, days) : nil
            }
            .max(by: { $0.1 < $1.1 })
            .map { (trip, days) in
                (trip, days, countryFlag(for: trip, lookup: lookup))
            }

        let continents = uniqueCountryNames.compactMap {
            lookup.lookup(isoCode: $0)?.continent ??
            lookup.lookup(named: $0)?.continent
        }
        let countriesByContinent = Dictionary(grouping: uniqueCountryNames) { name in
            let info = lookup.lookup(isoCode: name) ?? lookup.lookup(named: name)
            return WanderlustL10n.continentName(info?.continent ?? WanderlustL10n.string("Other", table: .statistics))
        }
        .map { (continent: $0.key, countries: $0.value.sorted()) }
        .sorted(by: { left, right in
            left.continent.localizedCaseInsensitiveCompare(right.continent) == ComparisonResult.orderedAscending
        })
        let continentGroups = countriesByContinent.map { group in
            StatisticsContinentGroup(
                continent: group.continent,
                countries: group.countries.map {
                    makeCountryRow(
                        $0,
                        lookup: lookup,
                        tripCount: countryTripIDs[$0]?.count ?? 0,
                        cityCount: countryCityKeys[$0]?.count ?? 0,
                        lastVisited: countryLastVisited[$0]
                    )
                }
            )
        }
        let tripRows = trips
            .sorted { $0.startDate > $1.startDate }
            .map { makeTripRow($0, lookup: lookup) }

        let tripsPerYearAvg = tripsPerYear.isEmpty
            ? "—"
            : WanderlustNumberFormatter.oneDecimalOrInteger(Double(journeys.count) / Double(tripsPerYear.count))
        let avgTripDays = trips.isEmpty
            ? "—"
            : WanderlustNumberFormatter.oneDecimalOrInteger(Double(totalTravelDays) / Double(trips.count))
        let cityTotal = trips.reduce(0) { $0 + $1.cities.count }
        let avgCitiesPerTrip = trips.isEmpty
            ? "—"
            : WanderlustNumberFormatter.oneDecimalOrInteger(Double(cityTotal) / Double(trips.count))

        return StatisticsSnapshot(
            uniqueCountryNames: uniqueCountryNames,
            uniqueCountryRows: uniqueCountryRows,
            uniqueCities: uniqueCities,
            totalFlights: totalFlights,
            continentCount: Set(continents.filter { !$0.isEmpty }).count,
            worldCompletion: Double(uniqueCountryNames.count) / 197.0,
            mostVisitedCountry: mostVisitedCountry,
            mostVisitedCity: mostVisitedCity,
            longestTrip: longestTrip,
            totalTravelDays: totalTravelDays,
            journeyCount: journeys.count,
            tripsPerYear: tripsPerYear,
            tripsPerYearAvg: tripsPerYearAvg,
            avgTripDays: avgTripDays,
            avgCitiesPerTrip: avgCitiesPerTrip,
            countriesByContinent: countriesByContinent,
            continentGroups: continentGroups,
            tripRows: tripRows
        )
    }

    nonisolated private static func statisticsJourneys(from tripGroups: [TripGroup], trips: [Trip]) -> [(startDate: Date, endDate: Date)] {
        let tripsByID = Dictionary(uniqueKeysWithValues: trips.map { ($0.id, $0) })
        let groupedJourneys = tripGroups.compactMap { group -> (startDate: Date, endDate: Date)? in
            let groupTrips = group.tripIDs.compactMap { tripsByID[$0] }
            guard !groupTrips.isEmpty else { return nil }
            return (
                groupTrips.map(\.startDate).min() ?? group.createdAt,
                groupTrips.map(\.endDate).max() ?? group.updatedAt
            )
        }

        if !groupedJourneys.isEmpty {
            return groupedJourneys
        }

        return trips.map { trip in
            (startDate: trip.startDate, endDate: trip.endDate)
        }
    }

    nonisolated private static func makeCountryRow(
        _ name: String,
        lookup: CountryLookup,
        tripCount: Int,
        cityCount: Int,
        lastVisited: Date?
    ) -> StatisticsCountryRow {
        let info = lookup.lookup(isoCode: name) ?? lookup.lookup(named: name)
        return StatisticsCountryRow(
            id: name,
            name: info?.displayName ?? name,
            flag: info?.flagEmoji ?? flagEmoji(countryCode: name),
            tripCount: tripCount,
            cityCount: cityCount,
            lastVisited: lastVisited
        )
    }

    nonisolated private static func makeTripRow(_ trip: Trip, lookup: CountryLookup) -> StatisticsTripRow {
        let city = trip.cities.first
        let code = WanderlustNameResolver.normalizedCountryCode(
            city?.countryCode ?? "",
            fallback: city?.countryName ?? ""
        )
        let info = lookup.lookup(isoCode: code) ?? lookup.lookup(named: city?.countryName ?? "")
        return StatisticsTripRow(
            id: trip.id,
            displayTitle: monthYear(trip.startDate),
            startDate: trip.startDate,
            endDate: trip.endDate,
            dateRangeText: dateRange(start: trip.startDate, end: trip.endDate),
            countryName: info?.displayName ?? city?.countryName ?? "",
            countryFlag: info?.flagEmoji ?? flagEmoji(countryCode: code),
            cityNames: trip.cities.map(localizedCityName).joined(separator: "・"),
            cityCount: trip.cities.count,
            flightCount: trip.flights.count
        )
    }

    nonisolated private static func tripDurationDays(_ trip: Trip) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: trip.startDate)
        let end = calendar.startOfDay(for: trip.endDate)
        return max((calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1, 1)
    }

    nonisolated private static func countryFlag(for trip: Trip, lookup: CountryLookup) -> String {
        let city = trip.cities.first
        let code = WanderlustNameResolver.normalizedCountryCode(
            city?.countryCode ?? "",
            fallback: city?.countryName ?? ""
        )
        let info = lookup.lookup(isoCode: code) ?? lookup.lookup(named: city?.countryName ?? "")
        return info?.flagEmoji ?? flagEmoji(countryCode: code)
    }

    nonisolated private static func localizedCityName(_ city: VisitedCity) -> String {
        if let geonameID = city.geonameID {
            return WanderlustL10n.cityName(
                id: String(geonameID),
                fallback: city.name
            )
        }

        return WanderlustL10n.cityName(
            countryCode: city.countryCode,
            name: city.name,
            fallback: city.name
        )
    }

    nonisolated private static func flagEmoji(countryCode: String) -> String {
        let code = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2 else { return "🌍" }
        return code.unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value).map(String.init)
        }.joined()
    }

    nonisolated static func monthRange(start: Date, end: Date) -> String {
        if isSingleMonth(start: start, end: end) {
            return monthYear(start)
        }

        return "\(monthYear(start)) – \(monthYear(end))"
    }

    nonisolated static func isSingleMonth(start: Date, end: Date) -> Bool {
        Calendar.current.isDate(start, equalTo: end, toGranularity: .month)
    }

    nonisolated private static func monthYear(_ date: Date) -> String {
        switch Locale.current.language.languageCode?.identifier {
        case "en", "de":
            return date.formatted(.dateTime.month(.abbreviated).year())
        default:
            return date.formatted(.dateTime.month(.wide).year())
        }
    }

    nonisolated private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    nonisolated private static func dateRange(start: Date, end: Date) -> String {
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return dateText(start)
        }
        return "\(dateText(start)) – \(dateText(end))"
    }

    nonisolated private static func makeMostVisitedCountry(from trips: [Trip], lookup: CountryLookup) -> (name: String, flag: String, count: Int)? {
        // 以前は `trip.cities.first` だけを見ていたため、複数国をまたぐ旅行では
        // 2 国目以降が集計から丸ごと落ちていた。旅行ごとに「訪問国の集合」を数える。
        var stats: [String: (count: Int, lastVisit: Date)] = [:]
        for trip in trips {
            let keysInTrip = Set(
                trip.cities.compactMap { VisitedCountryAggregator.key(for: $0)?.rawValue }
            )
            for key in keysInTrip {
                let existing = stats[key] ?? (0, .distantPast)
                stats[key] = (existing.count + 1, max(existing.lastVisit, trip.endDate))
            }
        }
        // 同数のときは最終訪問日が新しい方を優先し、並びを安定させる。
        guard let top = stats.max(by: { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            if lhs.value.lastVisit != rhs.value.lastVisit { return lhs.value.lastVisit < rhs.value.lastVisit }
            return lhs.key > rhs.key
        }), top.value.count > 1 else { return nil }
        let info = lookup.lookup(isoCode: top.key) ?? lookup.lookup(named: top.key)
        return (
            info?.displayName ?? top.key,
            info?.flagEmoji ?? "🌍",
            top.value.count
        )
    }

    nonisolated private static func makeMostVisitedCity(from trips: [Trip], lookup: CountryLookup) -> (name: String, country: String, flag: String, count: Int)? {
        var counts: [String: (VisitedCity, Int)] = [:]
        for trip in trips {
            for city in trip.cities {
                let key = city.geonameID.map { "g\($0)" } ?? "\(city.name)|\(city.countryCode)"
                if let (currentCity, count) = counts[key] {
                    counts[key] = (currentCity, count + 1)
                } else {
                    counts[key] = (city, 1)
                }
            }
        }
        guard let top = counts.values.max(by: { $0.1 < $1.1 }), top.1 > 1 else { return nil }
        let cityName = localizedCityName(top.0)
        let countryCode = WanderlustNameResolver.normalizedCountryCode(top.0.countryCode, fallback: top.0.countryName)
        let info = lookup.lookup(isoCode: countryCode) ?? lookup.lookup(named: top.0.countryName)
        let countryDisplay = info?.displayName
            ?? WanderlustL10n.countryName(iso2: countryCode)
        let countryFlag = info?.flagEmoji ?? flagEmoji(countryCode: countryCode)
        return (cityName, countryDisplay, countryFlag, top.1)
    }
}

// MARK: - Health Stat Card

struct HealthStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var showsChevron: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                // SF Symbol は字形ごとに縦横比が違うため、`font(size:)` だけだと
                // 見た目の大きさが揃わない（globe と airplane.departure が顕著）。
                // resizable + scaledToFit で外接ボックスを固定して光学サイズを揃える。
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22, alignment: .center)
                    .foregroundStyle(color)
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .wanderlustFont(11, relativeTo: .caption2, weight: .semibold)
                        .frame(width: 14, height: 22, alignment: .center)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            Text(value)
                .wanderlustFont(26, relativeTo: .title, weight: .bold, design: .rounded)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 110,
            maxHeight: 110,
            alignment: .topLeading
        )
        .wanderlustCard(radius: WanderlustRadius.xLarge, padding: WanderlustSpacing.large)
    }
}

private func statisticsSortMenuItem(
    id: String,
    title: String,
    isSelected: Bool,
    subtitle: String,
    action: @escaping @MainActor () -> Void
) -> WanderlustSortMenuItem {
    WanderlustSortMenuItem(
        id: id,
        title: title,
        subtitle: subtitle,
        isSelected: isSelected,
        action: action
    )
}

private func statisticsApplyWithoutAnimation(_ update: () -> Void) {
    var transaction = Transaction()
    transaction.animation = nil
    withTransaction(transaction) {
        update()
    }
}

private func statisticsLastVisitedText(_ date: Date?) -> String {
    guard let date else { return String(localized: "No visits") }
    return WanderlustDateFormatter.date(date)
}

private struct StatisticsCountriesList: View {
    let countries: [StatisticsCountryRow]
    @AppStorage("Statistics.countriesSortOption") private var sortOption: StatisticsCountrySortOption = .nameAscending
    @AppStorage("Statistics.countriesLastNameDirection") private var lastNameSortDirection: StatisticsSortDirection = .ascending
    @AppStorage("Statistics.countriesLastTripsDirection") private var lastTripsSortDirection: StatisticsSortDirection = .descending
    @AppStorage("Statistics.countriesLastCitiesDirection") private var lastCitiesSortDirection: StatisticsSortDirection = .descending
    @AppStorage("Statistics.countriesLastVisitedDirection") private var lastVisitedSortDirection: StatisticsSortDirection = .descending

    private var sortedCountries: [StatisticsCountryRow] {
        countries.sorted { lhs, rhs in
            switch sortOption {
            case .nameAscending:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .nameDescending:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            case .tripCountDescending:
                if lhs.tripCount != rhs.tripCount { return lhs.tripCount > rhs.tripCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .tripCountAscending:
                if lhs.tripCount != rhs.tripCount { return lhs.tripCount < rhs.tripCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .cityCountDescending:
                if lhs.cityCount != rhs.cityCount { return lhs.cityCount > rhs.cityCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .cityCountAscending:
                if lhs.cityCount != rhs.cityCount { return lhs.cityCount < rhs.cityCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .lastVisitedDescending:
                if lhs.lastVisited != rhs.lastVisited { return (lhs.lastVisited ?? .distantPast) > (rhs.lastVisited ?? .distantPast) }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .lastVisitedAscending:
                if lhs.lastVisited != rhs.lastVisited { return (lhs.lastVisited ?? .distantFuture) < (rhs.lastVisited ?? .distantFuture) }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        List(sortedCountries) { country in
            HStack(spacing: 12) {
                Text(country.flag)
                    .font(.title2)
                    .frame(width: 34)
                Text(country.name)
                    .font(.headline)
                Spacer(minLength: 12)
                if let detail = countrySortDetail(country) {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle(String(localized: "Countries"))
        .toolbarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                countriesSortMenu
            }
        }
    }

    private var countriesSortMenu: some View {
        WanderlustSortMenuButton(
            accessibilityLabel: WanderlustSortL10n.button,
            items: [
                statisticsSortMenuItem(id: "name", title: WanderlustSortL10n.name, isSelected: isNameSelected, subtitle: nameSubtitle, action: toggleNameSort),
                statisticsSortMenuItem(id: "trips", title: WanderlustSortL10n.trips, isSelected: isTripsSelected, subtitle: tripsSubtitle, action: toggleTripsSort),
                statisticsSortMenuItem(id: "cities", title: WanderlustSortL10n.cities, isSelected: isCitiesSelected, subtitle: citiesSubtitle, action: toggleCitiesSort),
                statisticsSortMenuItem(id: "lastVisited", title: WanderlustSortL10n.lastVisited, isSelected: isLastVisitedSelected, subtitle: lastVisitedSubtitle, action: toggleLastVisitedSort)
            ]
        )
    }

    private var isNameSelected: Bool { sortOption == .nameAscending || sortOption == .nameDescending }
    private var isTripsSelected: Bool { sortOption == .tripCountDescending || sortOption == .tripCountAscending }
    private var isCitiesSelected: Bool { sortOption == .cityCountDescending || sortOption == .cityCountAscending }
    private var isLastVisitedSelected: Bool { sortOption == .lastVisitedDescending || sortOption == .lastVisitedAscending }
    private var nameSubtitle: String { sortOption == .nameDescending ? WanderlustSortL10n.descending : WanderlustSortL10n.ascending }
    private var tripsSubtitle: String { sortOption == .tripCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most }
    private var citiesSubtitle: String { sortOption == .cityCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most }
    private var lastVisitedSubtitle: String { sortOption == .lastVisitedAscending ? WanderlustSortL10n.oldest : WanderlustSortL10n.newest }

    private func countrySortDetail(_ country: StatisticsCountryRow) -> String? {
        switch sortOption {
        case .nameAscending, .nameDescending:
            return nil
        case .tripCountDescending, .tripCountAscending:
            return PluralizationFormatter.compactTrips(country.tripCount)
        case .cityCountDescending, .cityCountAscending:
            return PluralizationFormatter.compactCities(country.cityCount)
        case .lastVisitedDescending, .lastVisitedAscending:
            return statisticsLastVisitedText(country.lastVisited)
        }
    }

    private func applySortOption(_ newOption: StatisticsCountrySortOption) {
        statisticsApplyWithoutAnimation { sortOption = newOption }
    }

    private func toggleNameSort() {
        switch sortOption {
        case .nameAscending:
            lastNameSortDirection = .descending
            applySortOption(.nameDescending)
        case .nameDescending:
            lastNameSortDirection = .ascending
            applySortOption(.nameAscending)
        default:
            applySortOption(lastNameSortDirection == .descending ? .nameDescending : .nameAscending)
        }
    }

    private func toggleTripsSort() {
        switch sortOption {
        case .tripCountDescending:
            lastTripsSortDirection = .ascending
            applySortOption(.tripCountAscending)
        case .tripCountAscending:
            lastTripsSortDirection = .descending
            applySortOption(.tripCountDescending)
        default:
            applySortOption(lastTripsSortDirection == .ascending ? .tripCountAscending : .tripCountDescending)
        }
    }

    private func toggleCitiesSort() {
        switch sortOption {
        case .cityCountDescending:
            lastCitiesSortDirection = .ascending
            applySortOption(.cityCountAscending)
        case .cityCountAscending:
            lastCitiesSortDirection = .descending
            applySortOption(.cityCountDescending)
        default:
            applySortOption(lastCitiesSortDirection == .ascending ? .cityCountAscending : .cityCountDescending)
        }
    }

    private func toggleLastVisitedSort() {
        switch sortOption {
        case .lastVisitedDescending:
            lastVisitedSortDirection = .ascending
            applySortOption(.lastVisitedAscending)
        case .lastVisitedAscending:
            lastVisitedSortDirection = .descending
            applySortOption(.lastVisitedDescending)
        default:
            applySortOption(lastVisitedSortDirection == .ascending ? .lastVisitedAscending : .lastVisitedDescending)
        }
    }
}

private struct StatisticsCitiesList: View {
    let cities: [StatisticsCityRow]
    @AppStorage("Statistics.citiesSortOption") private var sortOption: StatisticsCitySortOption = .countryAscending
    @AppStorage("Statistics.citiesLastCountryDirection") private var lastCountrySortDirection: StatisticsSortDirection = .ascending
    @AppStorage("Statistics.citiesLastNameDirection") private var lastNameSortDirection: StatisticsSortDirection = .ascending
    @AppStorage("Statistics.citiesLastVisitsDirection") private var lastVisitsSortDirection: StatisticsSortDirection = .descending
    @AppStorage("Statistics.citiesLastVisitedDirection") private var lastVisitedSortDirection: StatisticsSortDirection = .descending

    private var sortedCities: [StatisticsCityRow] {
        cities.sorted { lhs, rhs in
            switch sortOption {
            case .countryAscending:
                if lhs.countryName != rhs.countryName {
                    return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .countryDescending:
                if lhs.countryName != rhs.countryName {
                    return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedDescending
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .cityNameAscending:
                if lhs.name != rhs.name {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
            case .cityNameDescending:
                if lhs.name != rhs.name {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
                }
                return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
            case .visitCountDescending:
                if lhs.visitCount != rhs.visitCount { return lhs.visitCount > rhs.visitCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .visitCountAscending:
                if lhs.visitCount != rhs.visitCount { return lhs.visitCount < rhs.visitCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .lastVisitedDescending:
                if lhs.lastVisited != rhs.lastVisited { return (lhs.lastVisited ?? .distantPast) > (rhs.lastVisited ?? .distantPast) }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .lastVisitedAscending:
                if lhs.lastVisited != rhs.lastVisited { return (lhs.lastVisited ?? .distantFuture) < (rhs.lastVisited ?? .distantFuture) }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private var groupedCities: [(title: String, cities: [StatisticsCityRow])] {
        let sortedCities = cities.sorted { lhs, rhs in
            switch sortOption {
            case .countryAscending:
                if lhs.countryName != rhs.countryName {
                    return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .countryDescending:
                if lhs.countryName != rhs.countryName {
                    return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedDescending
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .cityNameAscending:
                if lhs.name != rhs.name {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
            case .cityNameDescending:
                if lhs.name != rhs.name {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
                }
                return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
            case .visitCountDescending, .visitCountAscending, .lastVisitedDescending, .lastVisitedAscending:
                return false
            }
        }

        return Dictionary(grouping: sortedCities) { city in
            switch sortOption {
            case .countryAscending, .countryDescending:
                return city.countryName
            case .cityNameAscending, .cityNameDescending:
                return String(city.name.prefix(1)).uppercased()
            case .visitCountDescending, .visitCountAscending, .lastVisitedDescending, .lastVisitedAscending:
                return ""
            }
        }
        .map { (title: $0.key, cities: $0.value) }
        .sorted {
            switch sortOption {
            case .countryDescending, .cityNameDescending:
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending
            case .countryAscending, .cityNameAscending:
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            case .visitCountDescending, .visitCountAscending, .lastVisitedDescending, .lastVisitedAscending:
                return false
            }
        }
    }

    var body: some View {
        List {
            if usesSections {
                ForEach(groupedCities, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.cities) { city in
                            cityRow(city)
                        }
                    }
                }
            } else {
                ForEach(sortedCities) { city in
                    cityRow(city)
                }
            }
        }
        .navigationTitle(WanderlustSortL10n.cities)
        .toolbarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                citiesSortMenu
            }
        }
    }

    @ViewBuilder
    private func cityRow(_ city: StatisticsCityRow) -> some View {
        HStack(spacing: 12) {
            Text(city.countryFlag)
                .font(.title2)
                .frame(width: 34)
            Text(city.name)
                .font(.headline)
            Spacer(minLength: 12)
            if let detail = citySortDetail(city) {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 4)
    }

    private var usesSections: Bool {
        switch sortOption {
        case .countryAscending, .countryDescending, .cityNameAscending, .cityNameDescending:
            return true
        case .visitCountDescending, .visitCountAscending, .lastVisitedDescending, .lastVisitedAscending:
            return false
        }
    }

    private var citiesSortMenu: some View {
        WanderlustSortMenuButton(
            accessibilityLabel: WanderlustSortL10n.button,
            items: [
                statisticsSortMenuItem(id: "country", title: WanderlustSortL10n.country, isSelected: isCountrySelected, subtitle: countrySubtitle, action: toggleCountrySort),
                statisticsSortMenuItem(id: "cityName", title: WanderlustSortL10n.cityName, isSelected: isCityNameSelected, subtitle: cityNameSubtitle, action: toggleNameSort),
                statisticsSortMenuItem(id: "visits", title: WanderlustSortL10n.visits, isSelected: isVisitsSelected, subtitle: visitsSubtitle, action: toggleVisitsSort),
                statisticsSortMenuItem(id: "lastVisited", title: WanderlustSortL10n.lastVisited, isSelected: isLastVisitedSelected, subtitle: lastVisitedSubtitle, action: toggleLastVisitedSort)
            ]
        )
    }

    private var isCountrySelected: Bool { sortOption == .countryAscending || sortOption == .countryDescending }
    private var isCityNameSelected: Bool { sortOption == .cityNameAscending || sortOption == .cityNameDescending }
    private var isVisitsSelected: Bool { sortOption == .visitCountDescending || sortOption == .visitCountAscending }
    private var isLastVisitedSelected: Bool { sortOption == .lastVisitedDescending || sortOption == .lastVisitedAscending }
    private var countrySubtitle: String { sortOption == .countryDescending ? WanderlustSortL10n.descending : WanderlustSortL10n.ascending }
    private var cityNameSubtitle: String { sortOption == .cityNameDescending ? WanderlustSortL10n.descending : WanderlustSortL10n.ascending }
    private var visitsSubtitle: String { sortOption == .visitCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most }
    private var lastVisitedSubtitle: String { sortOption == .lastVisitedAscending ? WanderlustSortL10n.oldest : WanderlustSortL10n.newest }

    private func citySortDetail(_ city: StatisticsCityRow) -> String? {
        switch sortOption {
        case .countryAscending, .countryDescending, .cityNameAscending, .cityNameDescending:
            return nil
        case .visitCountDescending, .visitCountAscending:
            return PluralizationFormatter.visits(city.visitCount)
        case .lastVisitedDescending, .lastVisitedAscending:
            return statisticsLastVisitedText(city.lastVisited)
        }
    }

    private func applySortOption(_ newOption: StatisticsCitySortOption) {
        statisticsApplyWithoutAnimation { sortOption = newOption }
    }

    private func toggleCountrySort() {
        switch sortOption {
        case .countryAscending:
            lastCountrySortDirection = .descending
            applySortOption(.countryDescending)
        case .countryDescending:
            lastCountrySortDirection = .ascending
            applySortOption(.countryAscending)
        default:
            applySortOption(lastCountrySortDirection == .descending ? .countryDescending : .countryAscending)
        }
    }

    private func toggleNameSort() {
        switch sortOption {
        case .cityNameAscending:
            lastNameSortDirection = .descending
            applySortOption(.cityNameDescending)
        case .cityNameDescending:
            lastNameSortDirection = .ascending
            applySortOption(.cityNameAscending)
        default:
            applySortOption(lastNameSortDirection == .descending ? .cityNameDescending : .cityNameAscending)
        }
    }

    private func toggleVisitsSort() {
        switch sortOption {
        case .visitCountDescending:
            lastVisitsSortDirection = .ascending
            applySortOption(.visitCountAscending)
        case .visitCountAscending:
            lastVisitsSortDirection = .descending
            applySortOption(.visitCountDescending)
        default:
            applySortOption(lastVisitsSortDirection == .ascending ? .visitCountAscending : .visitCountDescending)
        }
    }

    private func toggleLastVisitedSort() {
        switch sortOption {
        case .lastVisitedDescending:
            lastVisitedSortDirection = .ascending
            applySortOption(.lastVisitedAscending)
        case .lastVisitedAscending:
            lastVisitedSortDirection = .descending
            applySortOption(.lastVisitedDescending)
        default:
            applySortOption(lastVisitedSortDirection == .ascending ? .lastVisitedAscending : .lastVisitedDescending)
        }
    }

    private func flagEmoji(countryCode: String) -> String {
        let code = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2 else { return "🌍" }
        return code.unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value).map(String.init)
        }.joined()
    }
}

private struct StatisticsTripsList: View {
    @ObservedObject var tripStore: TripStore
    @State private var selectedTrip: StatisticsSelectedTrip?
    @AppStorage("Statistics.tripsSortOption") private var sortOption: StatisticsTripSortOption = .dateDescending
    @AppStorage("Statistics.tripsLastDateDirection") private var lastDateSortDirection: StatisticsSortDirection = .descending
    @AppStorage("Statistics.tripsLastCountryDirection") private var lastCountrySortDirection: StatisticsSortDirection = .ascending
    @AppStorage("Statistics.tripsLastDurationDirection") private var lastDurationSortDirection: StatisticsSortDirection = .descending
    @AppStorage("Statistics.tripsLastCitiesDirection") private var lastCitiesSortDirection: StatisticsSortDirection = .descending
    @AppStorage("Statistics.tripsLastFlightsDirection") private var lastFlightsSortDirection: StatisticsSortDirection = .descending

    private var rows: [StatisticsTripRow] {
        StatisticsSnapshot.make(from: tripStore.trips, tripGroups: tripStore.tripGroups, lookup: CountryLookup()).tripRows
    }

    private var sortedRows: [StatisticsTripRow] {
        rows.sorted { lhs, rhs in
            switch sortOption {
            case .dateDescending:
                if lhs.startDate != rhs.startDate { return lhs.startDate > rhs.startDate }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            case .dateAscending:
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            case .countryAscending:
                if lhs.countryName != rhs.countryName {
                    return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
                }
                return lhs.startDate > rhs.startDate
            case .countryDescending:
                if lhs.countryName != rhs.countryName {
                    return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedDescending
                }
                return lhs.startDate > rhs.startDate
            case .durationDescending:
                let lhsDays = tripDurationDays(lhs)
                let rhsDays = tripDurationDays(rhs)
                if lhsDays != rhsDays { return lhsDays > rhsDays }
                return lhs.startDate > rhs.startDate
            case .durationAscending:
                let lhsDays = tripDurationDays(lhs)
                let rhsDays = tripDurationDays(rhs)
                if lhsDays != rhsDays { return lhsDays < rhsDays }
                return lhs.startDate > rhs.startDate
            case .cityCountDescending:
                if lhs.cityCount != rhs.cityCount { return lhs.cityCount > rhs.cityCount }
                return lhs.startDate > rhs.startDate
            case .cityCountAscending:
                if lhs.cityCount != rhs.cityCount { return lhs.cityCount < rhs.cityCount }
                return lhs.startDate > rhs.startDate
            case .flightCountDescending:
                if lhs.flightCount != rhs.flightCount { return lhs.flightCount > rhs.flightCount }
                return lhs.startDate > rhs.startDate
            case .flightCountAscending:
                if lhs.flightCount != rhs.flightCount { return lhs.flightCount < rhs.flightCount }
                return lhs.startDate > rhs.startDate
            }
        }
    }

    var body: some View {
        List(sortedRows) { row in
            Button {
                selectedTrip = StatisticsSelectedTrip(id: row.id)
            } label: {
                StatisticsTripRowView(row: row)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(WanderlustSortL10n.trips)
        .toolbarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                tripsSortMenu
            }
        }
        .navigationDestination(item: $selectedTrip) { selection in
            TripDetailView(tripID: selection.id, tripStore: tripStore)
        }
    }

    private func tripDurationDays(_ row: StatisticsTripRow) -> Int {
        max(Calendar.current.dateComponents([.day], from: row.startDate, to: row.endDate).day ?? 0, 0)
    }

    private func toggleDateSort() {
        switch sortOption {
        case .dateDescending:
            lastDateSortDirection = .ascending
            applySortOption(.dateAscending)
        case .dateAscending:
            lastDateSortDirection = .descending
            applySortOption(.dateDescending)
        default:
            applySortOption(lastDateSortDirection == .ascending ? .dateAscending : .dateDescending)
        }
    }

    private var tripsSortMenu: some View {
        WanderlustSortMenuButton(
            accessibilityLabel: WanderlustSortL10n.button,
            items: [
                statisticsSortMenuItem(id: "date", title: WanderlustSortL10n.date, isSelected: sortOption == .dateDescending || sortOption == .dateAscending, subtitle: sortOption == .dateAscending ? WanderlustSortL10n.oldest : WanderlustSortL10n.newest, action: toggleDateSort),
                statisticsSortMenuItem(id: "country", title: WanderlustSortL10n.country, isSelected: sortOption == .countryAscending || sortOption == .countryDescending, subtitle: sortOption == .countryDescending ? WanderlustSortL10n.descending : WanderlustSortL10n.ascending, action: toggleCountrySort),
                statisticsSortMenuItem(id: "duration", title: WanderlustSortL10n.duration, isSelected: sortOption == .durationDescending || sortOption == .durationAscending, subtitle: sortOption == .durationAscending ? WanderlustSortL10n.shortest : WanderlustSortL10n.longest, action: toggleDurationSort),
                statisticsSortMenuItem(id: "cities", title: WanderlustSortL10n.cities, isSelected: sortOption == .cityCountDescending || sortOption == .cityCountAscending, subtitle: sortOption == .cityCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most, action: toggleCitiesSort),
                statisticsSortMenuItem(id: "flights", title: WanderlustSortL10n.flights, isSelected: sortOption == .flightCountDescending || sortOption == .flightCountAscending, subtitle: sortOption == .flightCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most, action: toggleFlightsSort)
            ]
        )
    }

    private func applySortOption(_ newOption: StatisticsTripSortOption) {
        statisticsApplyWithoutAnimation { sortOption = newOption }
    }

    private func toggleCountrySort() {
        switch sortOption {
        case .countryAscending:
            lastCountrySortDirection = .descending
            applySortOption(.countryDescending)
        case .countryDescending:
            lastCountrySortDirection = .ascending
            applySortOption(.countryAscending)
        default:
            applySortOption(lastCountrySortDirection == .descending ? .countryDescending : .countryAscending)
        }
    }

    private func toggleDurationSort() {
        switch sortOption {
        case .durationDescending:
            lastDurationSortDirection = .ascending
            applySortOption(.durationAscending)
        case .durationAscending:
            lastDurationSortDirection = .descending
            applySortOption(.durationDescending)
        default:
            applySortOption(lastDurationSortDirection == .ascending ? .durationAscending : .durationDescending)
        }
    }

    private func toggleCitiesSort() {
        switch sortOption {
        case .cityCountDescending:
            lastCitiesSortDirection = .ascending
            applySortOption(.cityCountAscending)
        case .cityCountAscending:
            lastCitiesSortDirection = .descending
            applySortOption(.cityCountDescending)
        default:
            applySortOption(lastCitiesSortDirection == .ascending ? .cityCountAscending : .cityCountDescending)
        }
    }

    private func toggleFlightsSort() {
        switch sortOption {
        case .flightCountDescending:
            lastFlightsSortDirection = .ascending
            applySortOption(.flightCountAscending)
        case .flightCountAscending:
            lastFlightsSortDirection = .descending
            applySortOption(.flightCountDescending)
        default:
            applySortOption(lastFlightsSortDirection == .ascending ? .flightCountAscending : .flightCountDescending)
        }
    }
}

private struct StatisticsTripRowView: View {
    let row: StatisticsTripRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if !row.countryName.isEmpty {
                    HStack(spacing: 8) {
                        Text(row.countryFlag)
                            .font(.title3)
                            .accessibilityHidden(true)
                        Text(row.countryName)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                    }
                }

                Text(row.dateRangeText)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)

                if !row.cityNames.isEmpty {
                    Text(row.cityNames)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    WanderlustInlineCount(
                        systemImage: "building.2",
                        text: PluralizationFormatter.compactCities(row.cityCount)
                    )
                    if row.flightCount > 0 {
                        WanderlustInlineCount(
                            systemImage: "airplane",
                            text: PluralizationFormatter.compactFlightSummary(row.flightCount)
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 90)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
    }
}

private struct StatisticsFlightsTripList: View {
    @ObservedObject var tripStore: TripStore
    @State private var selectedTrip: StatisticsSelectedTrip?
    @AppStorage("Statistics.flightTripsSortOption") private var sortOption: StatisticsFlightTripSortOption = .dateDescending
    @AppStorage("Statistics.flightTripsLastDateDirection") private var lastDateSortDirection: StatisticsSortDirection = .descending
    @AppStorage("Statistics.flightTripsLastCountryDirection") private var lastCountrySortDirection: StatisticsSortDirection = .ascending
    @AppStorage("Statistics.flightTripsLastFlightsDirection") private var lastFlightsSortDirection: StatisticsSortDirection = .descending

    private var tripsWithFlights: [Trip] {
        var seenTripIDs: Set<UUID> = []
        return tripStore.trips
            .filter { !$0.flights.isEmpty }
            .filter { trip in seenTripIDs.insert(trip.id).inserted }
    }

    private var sortedTripsWithFlights: [Trip] {
        tripsWithFlights.sorted { lhs, rhs in
            switch sortOption {
            case .dateDescending:
                if lhs.startDate != rhs.startDate { return lhs.startDate > rhs.startDate }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .dateAscending:
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .countryAscending:
                let lhsCountry = tripPrimaryCountry(lhs).name
                let rhsCountry = tripPrimaryCountry(rhs).name
                if lhsCountry != rhsCountry { return lhsCountry.localizedCaseInsensitiveCompare(rhsCountry) == .orderedAscending }
                return lhs.startDate > rhs.startDate
            case .countryDescending:
                let lhsCountry = tripPrimaryCountry(lhs).name
                let rhsCountry = tripPrimaryCountry(rhs).name
                if lhsCountry != rhsCountry { return lhsCountry.localizedCaseInsensitiveCompare(rhsCountry) == .orderedDescending }
                return lhs.startDate > rhs.startDate
            case .flightCountDescending:
                if lhs.flights.count != rhs.flights.count { return lhs.flights.count > rhs.flights.count }
                return lhs.startDate > rhs.startDate
            case .flightCountAscending:
                if lhs.flights.count != rhs.flights.count { return lhs.flights.count < rhs.flights.count }
                return lhs.startDate > rhs.startDate
            }
        }
    }

    var body: some View {
        Group {
            if tripsWithFlights.isEmpty {
                WanderlustEmptyStateView(
                    systemImage: "airplane",
                    title: WanderlustL10n.string("No Flights", table: .settings),
                    message: WanderlustL10n.string("No flights were added to your trips.", table: .settings, fallback: "No flights were added to your trips.")
                )
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sortedTripsWithFlights) { trip in
                    Button {
                        selectedTrip = StatisticsSelectedTrip(id: trip.id)
                    } label: {
                        let primaryCountry = tripPrimaryCountry(trip)
                        TripCardView(
                            trip: trip,
                            countryName: primaryCountry.name,
                            countryFlag: primaryCountry.flag,
                            showsCityCount: false,
                            showsFlightCount: true
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(WanderlustSortL10n.flights)
        .toolbarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                flightTripsSortMenu
            }
        }
        .navigationDestination(item: $selectedTrip) { selection in
            StatisticsTripFlightsList(tripID: selection.id, tripStore: tripStore)
        }
    }

    private func tripPrimaryCountry(_ trip: Trip) -> (name: String, flag: String) {
        guard let city = trip.cities.first else {
            return ("", "")
        }
        let code = WanderlustNameResolver.normalizedCountryCode(
            city.countryCode,
            fallback: city.countryName
        )
        let country = GeoJSONLoader.shared.country(withISOCode: code)
        return (
            country?.displayName ?? city.localizedCountryName,
            country?.flagEmoji ?? flagEmoji(countryCode: code)
        )
    }

    private func flagEmoji(countryCode: String) -> String {
        let code = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2 else { return "🌍" }
        return code.unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value).map(String.init)
        }.joined()
    }

    private func toggleDateSort() {
        switch sortOption {
        case .dateDescending:
            lastDateSortDirection = .ascending
            applySortOption(.dateAscending)
        case .dateAscending:
            lastDateSortDirection = .descending
            applySortOption(.dateDescending)
        default:
            applySortOption(lastDateSortDirection == .ascending ? .dateAscending : .dateDescending)
        }
    }

    private var flightTripsSortMenu: some View {
        WanderlustSortMenuButton(
            accessibilityLabel: WanderlustSortL10n.button,
            items: [
                statisticsSortMenuItem(id: "date", title: WanderlustSortL10n.date, isSelected: sortOption == .dateDescending || sortOption == .dateAscending, subtitle: sortOption == .dateAscending ? WanderlustSortL10n.oldest : WanderlustSortL10n.newest, action: toggleDateSort),
                statisticsSortMenuItem(id: "country", title: WanderlustSortL10n.country, isSelected: sortOption == .countryAscending || sortOption == .countryDescending, subtitle: sortOption == .countryDescending ? WanderlustSortL10n.descending : WanderlustSortL10n.ascending, action: toggleCountrySort),
                statisticsSortMenuItem(id: "flights", title: WanderlustSortL10n.flights, isSelected: sortOption == .flightCountDescending || sortOption == .flightCountAscending, subtitle: sortOption == .flightCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most, action: toggleFlightsSort)
            ]
        )
    }

    private func applySortOption(_ newOption: StatisticsFlightTripSortOption) {
        statisticsApplyWithoutAnimation { sortOption = newOption }
    }

    private func toggleCountrySort() {
        switch sortOption {
        case .countryAscending:
            lastCountrySortDirection = .descending
            applySortOption(.countryDescending)
        case .countryDescending:
            lastCountrySortDirection = .ascending
            applySortOption(.countryAscending)
        default:
            applySortOption(lastCountrySortDirection == .descending ? .countryDescending : .countryAscending)
        }
    }

    private func toggleFlightsSort() {
        switch sortOption {
        case .flightCountDescending:
            lastFlightsSortDirection = .ascending
            applySortOption(.flightCountAscending)
        case .flightCountAscending:
            lastFlightsSortDirection = .descending
            applySortOption(.flightCountDescending)
        default:
            applySortOption(lastFlightsSortDirection == .ascending ? .flightCountAscending : .flightCountDescending)
        }
    }
}

private struct StatisticsTripFlightsList: View {
    let tripID: UUID
    @ObservedObject var tripStore: TripStore
    @State private var selectedFlightPlayback: StatisticsFlightPlaybackSelection?
    @AppStorage("Statistics.tripFlightsSortOption") private var sortOption: StatisticsFlightSortOption = .departureAscending
    @AppStorage("Statistics.tripFlightsLastDepartureDirection") private var lastDepartureSortDirection: StatisticsSortDirection = .ascending
    @AppStorage("Statistics.tripFlightsLastRouteDirection") private var lastRouteSortDirection: StatisticsSortDirection = .ascending
    @AppStorage("Statistics.tripFlightsLastAirlineDirection") private var lastAirlineSortDirection: StatisticsSortDirection = .ascending

    private var trip: Trip? {
        tripStore.trips.first { $0.id == tripID }
    }

    private var flightGroups: [TripFlightGroup] {
        guard let trip else { return [] }
        return TripFlightGroupBuilder.groups(for: trip.flights)
    }

    var body: some View {
        List {
            if flightGroups.isEmpty {
                Section {
                    ContentUnavailableView(
                        WanderlustL10n.string("No Flights", table: .settings),
                        systemImage: "airplane",
                        description: Text(
                            WanderlustL10n.string("No flights were added to this trip.", table: .settings)
                        )
                    )
                } header: {
                    WanderlustSectionHeader(title: WanderlustSortL10n.flights)
                }
            } else {
                ForEach(Array(flightGroups.enumerated()), id: \.element.id) { index, group in
                    Section {
                        flightGroupButton(group)
                    } header: {
                        if let headerTitle = group.headerTitle {
                            WanderlustSectionHeader(title: headerTitle)
                        } else if index == 0 {
                            WanderlustSectionHeader(title: WanderlustSortL10n.flights)
                        }
                    }
                    .listSectionSpacing(14)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .sheet(item: $selectedFlightPlayback) { selection in
            FlightMapView(flights: selection.flights)
        }
    }

    private func flightGroupButton(_ group: TripFlightGroup) -> some View {
        Button {
            selectedFlightPlayback = StatisticsFlightPlaybackSelection(
                flights: group.flights
            )
        } label: {
            TripDetailFlightGroupRow(
                title: group.title,
                flights: group.flights
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityLabel(group.title)
    }

    private func toggleDepartureSort() {
        switch sortOption {
        case .departureAscending:
            lastDepartureSortDirection = .descending
            applySortOption(.departureDescending)
        case .departureDescending:
            lastDepartureSortDirection = .ascending
            applySortOption(.departureAscending)
        default:
            applySortOption(lastDepartureSortDirection == .descending ? .departureDescending : .departureAscending)
        }
    }

    private var flightSortMenu: some View {
        WanderlustSortMenuButton(
            accessibilityLabel: WanderlustSortL10n.button,
            items: [
                statisticsSortMenuItem(id: "departure", title: WanderlustSortL10n.departure, isSelected: sortOption == .departureAscending || sortOption == .departureDescending, subtitle: sortOption == .departureDescending ? WanderlustSortL10n.newest : WanderlustSortL10n.oldest, action: toggleDepartureSort),
                statisticsSortMenuItem(id: "route", title: WanderlustSortL10n.route, isSelected: sortOption == .routeAscending || sortOption == .routeDescending, subtitle: sortOption == .routeDescending ? WanderlustSortL10n.descending : WanderlustSortL10n.ascending, action: toggleRouteSort),
                statisticsSortMenuItem(id: "airline", title: WanderlustSortL10n.airline, isSelected: sortOption == .airlineAscending || sortOption == .airlineDescending, subtitle: sortOption == .airlineDescending ? WanderlustSortL10n.descending : WanderlustSortL10n.ascending, action: toggleAirlineSort)
            ]
        )
    }

    private func applySortOption(_ newOption: StatisticsFlightSortOption) {
        statisticsApplyWithoutAnimation { sortOption = newOption }
    }

    private func toggleRouteSort() {
        switch sortOption {
        case .routeAscending:
            lastRouteSortDirection = .descending
            applySortOption(.routeDescending)
        case .routeDescending:
            lastRouteSortDirection = .ascending
            applySortOption(.routeAscending)
        default:
            applySortOption(lastRouteSortDirection == .descending ? .routeDescending : .routeAscending)
        }
    }

    private func toggleAirlineSort() {
        switch sortOption {
        case .airlineAscending:
            lastAirlineSortDirection = .descending
            applySortOption(.airlineDescending)
        case .airlineDescending:
            lastAirlineSortDirection = .ascending
            applySortOption(.airlineAscending)
        default:
            applySortOption(lastAirlineSortDirection == .descending ? .airlineDescending : .airlineAscending)
        }
    }

    private struct StatisticsFlightPlaybackSelection: Identifiable {
        let id = UUID()
        let flights: [Flight]
    }
}

private struct StatisticsContinentsList: View {
    let groups: [StatisticsContinentGroup]
    @AppStorage("Statistics.continentsSortOption") private var sortOption: StatisticsContinentSortOption = .nameAscending
    @AppStorage("Statistics.continentsLastNameDirection") private var lastNameSortDirection: StatisticsSortDirection = .ascending
    @AppStorage("Statistics.continentsLastCountriesDirection") private var lastCountriesSortDirection: StatisticsSortDirection = .descending
    @AppStorage("Statistics.continentsLastTripsDirection") private var lastTripsSortDirection: StatisticsSortDirection = .descending

    private var sortedGroups: [StatisticsContinentGroup] {
        groups.sorted { lhs, rhs in
            switch sortOption {
            case .nameAscending:
                return lhs.continent.localizedCaseInsensitiveCompare(rhs.continent) == .orderedAscending
            case .nameDescending:
                return lhs.continent.localizedCaseInsensitiveCompare(rhs.continent) == .orderedDescending
            case .countryCountDescending:
                if lhs.countries.count != rhs.countries.count { return lhs.countries.count > rhs.countries.count }
                return lhs.continent.localizedCaseInsensitiveCompare(rhs.continent) == .orderedAscending
            case .countryCountAscending:
                if lhs.countries.count != rhs.countries.count { return lhs.countries.count < rhs.countries.count }
                return lhs.continent.localizedCaseInsensitiveCompare(rhs.continent) == .orderedAscending
            case .tripCountDescending:
                if continentTripCount(lhs) != continentTripCount(rhs) { return continentTripCount(lhs) > continentTripCount(rhs) }
                return lhs.continent.localizedCaseInsensitiveCompare(rhs.continent) == .orderedAscending
            case .tripCountAscending:
                if continentTripCount(lhs) != continentTripCount(rhs) { return continentTripCount(lhs) < continentTripCount(rhs) }
                return lhs.continent.localizedCaseInsensitiveCompare(rhs.continent) == .orderedAscending
            }
        }
    }

    var body: some View {
        List {
            ForEach(sortedGroups) { group in
                Section {
                    ForEach(group.countries) { country in
                        HStack(spacing: 12) {
                            Text(country.flag)
                                .font(.title2)
                                .frame(width: 34)
                            Text(country.name)
                                .font(.headline)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.continent)
                        Spacer(minLength: 12)
                        if let detail = continentSortDetail(group) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .navigationTitle(WanderlustL10n.string("Continents", table: .statistics))
        .toolbarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                continentsSortMenu
            }
        }
    }

    private var continentsSortMenu: some View {
        WanderlustSortMenuButton(
            accessibilityLabel: WanderlustSortL10n.button,
            items: [
                statisticsSortMenuItem(id: "name", title: WanderlustSortL10n.name, isSelected: sortOption == .nameAscending || sortOption == .nameDescending, subtitle: sortOption == .nameDescending ? WanderlustSortL10n.descending : WanderlustSortL10n.ascending, action: toggleNameSort),
                statisticsSortMenuItem(id: "countries", title: WanderlustSortL10n.countries, isSelected: sortOption == .countryCountDescending || sortOption == .countryCountAscending, subtitle: sortOption == .countryCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most, action: toggleCountriesSort),
                statisticsSortMenuItem(id: "trips", title: WanderlustSortL10n.trips, isSelected: sortOption == .tripCountDescending || sortOption == .tripCountAscending, subtitle: sortOption == .tripCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most, action: toggleTripsSort)
            ]
        )
    }

    private func continentTripCount(_ group: StatisticsContinentGroup) -> Int {
        group.countries.reduce(0) { $0 + $1.tripCount }
    }

    private func continentSortDetail(_ group: StatisticsContinentGroup) -> String? {
        switch sortOption {
        case .nameAscending, .nameDescending:
            return nil
        case .countryCountDescending, .countryCountAscending:
            return PluralizationFormatter.compactCountries(group.countries.count)
        case .tripCountDescending, .tripCountAscending:
            return PluralizationFormatter.compactTrips(continentTripCount(group))
        }
    }

    private func applySortOption(_ newOption: StatisticsContinentSortOption) {
        statisticsApplyWithoutAnimation { sortOption = newOption }
    }

    private func toggleNameSort() {
        switch sortOption {
        case .nameAscending:
            lastNameSortDirection = .descending
            applySortOption(.nameDescending)
        case .nameDescending:
            lastNameSortDirection = .ascending
            applySortOption(.nameAscending)
        default:
            applySortOption(lastNameSortDirection == .descending ? .nameDescending : .nameAscending)
        }
    }

    private func toggleCountriesSort() {
        switch sortOption {
        case .countryCountDescending:
            lastCountriesSortDirection = .ascending
            applySortOption(.countryCountAscending)
        case .countryCountAscending:
            lastCountriesSortDirection = .descending
            applySortOption(.countryCountDescending)
        default:
            applySortOption(lastCountriesSortDirection == .ascending ? .countryCountAscending : .countryCountDescending)
        }
    }

    private func toggleTripsSort() {
        switch sortOption {
        case .tripCountDescending:
            lastTripsSortDirection = .ascending
            applySortOption(.tripCountAscending)
        case .tripCountAscending:
            lastTripsSortDirection = .descending
            applySortOption(.tripCountDescending)
        default:
            applySortOption(lastTripsSortDirection == .ascending ? .tripCountAscending : .tripCountDescending)
        }
    }
}

// MARK: - Highlight Row

private struct HighlightRow: View {
    let icon: String
    let isEmoji: Bool
    let color: Color
    let label: String
    let title: String
    var titlePrefix: String? = nil
    var subtitle: String? = nil
    let detail: String
    var detailPlacement: DetailPlacement = .trailing

    enum DetailPlacement {
        case trailing
        case below
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        Color(
                            .tertiarySystemGroupedBackground
                        )
                    )
                    .frame(width: 40, height: 40)

                if isEmoji {
                    Text(icon)
                        .font(.system(size: 20))
                        .lineLimit(1)
                        .frame(width: 28, height: 20)
                        .clipped()
                } else {
                    Image(systemName: icon)
                        .wanderlustFont(16, relativeTo: .callout)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(color)
                }
            }

            HStack(alignment: .center, spacing: 5) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if detailPlacement == .below {
                        VStack(alignment: .leading, spacing: 8) {
                            titleLine

                            if !detail.isEmpty {
                                HStack {
                                    Spacer(minLength: 8)
                                    Text(detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        }
                    } else {
                        titleLine
                    }

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                if detailPlacement == .trailing, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private var titleLine: some View {
        HStack(spacing: 5) {
            if let titlePrefix, !titlePrefix.isEmpty {
                Text(titlePrefix)
                    .font(.headline)
                    .fixedSize()
            }

            Text(title)
                .font(.headline)
                .lineLimit(1)
                .allowsTightening(true)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }
}

// MARK: - Average Stat Card

private struct AverageStatCard: View {
    let title: String
    let value: String
    let unit: String

    private var accessibilityValueText: String {
        value == "—" ? value : "\(value) \(unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderlustSpacing.xSmall) {
            Text(value)
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValueText)
        .padding(.vertical, WanderlustSpacing.small)
        .padding(.leading, WanderlustSpacing.medium)
        .padding(.trailing, WanderlustSpacing.small)
        .background(
            Color(.tertiarySystemGroupedBackground),
            in: RoundedRectangle(
                cornerRadius: WanderlustRadius.medium,
                style: .continuous
            )
        )
    }
}
