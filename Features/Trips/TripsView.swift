import SwiftUI

// MARK: - Data Helpers

private struct CountryGroup: Identifiable {
    let id: String
    let countryName: String
    let flagEmoji: String
    let cityCount: Int
    let tripCount: Int
    let mostRecentDate: Date
    let trips: [Trip]
}

private enum TripsViewMode: String, CaseIterable, Identifiable {
    case countries
    case journeys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .journeys:
            return WanderlustL10n.string("Journeys", table: .trips, fallback: "Journeys")
        case .countries:
            return WanderlustL10n.string("Countries", table: .trips, fallback: "Countries")
        }
    }
}

private enum TripsCountrySortOption: String, CaseIterable, Identifiable {
    case recent
    case recentAscending
    case nameAscending
    case nameDescending
    case tripCount
    case tripCountAscending
    case cityCount
    case cityCountAscending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent, .recentAscending:
            return WanderlustL10n.string("Date", table: .trips, fallback: "Date")
        case .nameAscending:
            return String(localized: "Name")
        case .nameDescending:
            return String(localized: "Name")
        case .tripCount, .tripCountAscending:
            return String(localized: "Trips")
        case .cityCount, .cityCountAscending:
            return String(localized: "Cities")
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .recent:
            return String(localized: "Date, Newest First")
        case .recentAscending:
            return String(localized: "Date, Oldest First")
        case .nameAscending:
            return String(localized: "Name A-Z")
        case .nameDescending:
            return String(localized: "Name Z-A")
        case .tripCount:
            return String(localized: "Trips, Most First")
        case .tripCountAscending:
            return String(localized: "Trips, Fewest First")
        case .cityCount:
            return String(localized: "Cities, Most First")
        case .cityCountAscending:
            return String(localized: "Cities, Fewest First")
        }
    }
}

private enum TripsJourneySortOption: String, CaseIterable, Identifiable {
    case recent
    case recentAscending
    case nameAscending
    case nameDescending
    case countryCount
    case countryCountAscending
    case segmentCount
    case segmentCountAscending

    var id: String { rawValue }
}

private enum TripsNameSortDirection: String {
    case ascending
    case descending
}

private enum CountryTripSortOption: String, CaseIterable, Identifiable {
    case dateDescending
    case dateAscending
    case durationDescending
    case durationAscending
    case cityCountDescending
    case cityCountAscending
    case flightCountDescending
    case flightCountAscending

    var id: String { rawValue }

    var accessibilityTitle: String {
        switch self {
        case .dateDescending:
            return String(localized: "Date, Newest First")
        case .dateAscending:
            return String(localized: "Date, Oldest First")
        case .durationDescending:
            return String(localized: "Duration, Longest First")
        case .durationAscending:
            return String(localized: "Duration, Shortest First")
        case .cityCountDescending:
            return String(localized: "Cities, Most First")
        case .cityCountAscending:
            return String(localized: "Cities, Fewest First")
        case .flightCountDescending:
            return String(localized: "Flights, Most First")
        case .flightCountAscending:
            return String(localized: "Flights, Fewest First")
        }
    }
}

// MARK: - Trips View

struct TripsView: View {
    @ObservedObject var tripStore: TripStore
    @State private var showStartJourney = false
    @State private var editingJourneyGroup: TripGroup?
    @State private var deletingJourneyGroup: TripGroup?
    @AppStorage("Trips.viewMode") private var viewMode: TripsViewMode = .countries
    @AppStorage("Trips.countrySortOption") private var countrySortOption: TripsCountrySortOption = .recent
    @AppStorage("Trips.journeySortOption") private var journeySortOption: TripsJourneySortOption = .recent
    @AppStorage("Trips.lastDateSortDirection") private var lastDateSortDirection: TripsNameSortDirection = .descending
    @AppStorage("Trips.lastNameSortDirection") private var lastNameSortDirection: TripsNameSortDirection = .ascending
    @AppStorage("Trips.lastTripsSortDirection") private var lastTripsSortDirection: TripsNameSortDirection = .descending
    @AppStorage("Trips.lastCitiesSortDirection") private var lastCitiesSortDirection: TripsNameSortDirection = .descending
    @AppStorage("Trips.journeyLastDateDirection") private var journeyLastDateDirection: TripsNameSortDirection = .descending
    @AppStorage("Trips.journeyLastNameDirection") private var journeyLastNameDirection: TripsNameSortDirection = .ascending
    @AppStorage("Trips.journeyLastCountriesDirection") private var journeyLastCountriesDirection: TripsNameSortDirection = .descending
    @AppStorage("Trips.journeyLastSegmentsDirection") private var journeyLastSegmentsDirection: TripsNameSortDirection = .descending

    private var countryGroups: [CountryGroup] {
        Self.makeCountryGroups(from: tripStore.trips).sorted { lhs, rhs in
            switch countrySortOption {
            case .recent:
                if lhs.mostRecentDate != rhs.mostRecentDate { return lhs.mostRecentDate > rhs.mostRecentDate }
                return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
            case .recentAscending:
                if lhs.mostRecentDate != rhs.mostRecentDate { return lhs.mostRecentDate < rhs.mostRecentDate }
                return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
            case .nameAscending:
                return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
            case .nameDescending:
                return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedDescending
            case .tripCount:
                if lhs.tripCount != rhs.tripCount { return lhs.tripCount > rhs.tripCount }
                return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
            case .tripCountAscending:
                if lhs.tripCount != rhs.tripCount { return lhs.tripCount < rhs.tripCount }
                return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
            case .cityCount:
                if lhs.cityCount != rhs.cityCount { return lhs.cityCount > rhs.cityCount }
                return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
            case .cityCountAscending:
                if lhs.cityCount != rhs.cityCount { return lhs.cityCount < rhs.cityCount }
                return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
            }
        }
    }

    private var journeyGroups: [TripGroup] {
        let groupedTripIDs = Set(
            tripStore.tripGroups
                .filter { $0.tripIDs.count > 1 || !$0.transportItems.isEmpty }
                .flatMap(\.tripIDs)
        )
        let visibleGroups = tripStore.tripGroups.filter { group in
            group.tripIDs.count > 1 ||
            !group.transportItems.isEmpty ||
            !group.tripIDs.allSatisfy { groupedTripIDs.contains($0) }
        }

        return visibleGroups.sorted { lhs, rhs in
            switch journeySortOption {
            case .recent:
                let lhsDate = journeyStartDate(lhs)
                let rhsDate = journeyStartDate(rhs)
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return journeyTitle(lhs).localizedCaseInsensitiveCompare(journeyTitle(rhs)) == .orderedAscending
            case .recentAscending:
                let lhsDate = journeyStartDate(lhs)
                let rhsDate = journeyStartDate(rhs)
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return journeyTitle(lhs).localizedCaseInsensitiveCompare(journeyTitle(rhs)) == .orderedAscending
            case .nameAscending:
                return journeyTitle(lhs).localizedCaseInsensitiveCompare(journeyTitle(rhs)) == .orderedAscending
            case .nameDescending:
                return journeyTitle(lhs).localizedCaseInsensitiveCompare(journeyTitle(rhs)) == .orderedDescending
            case .countryCount:
                let lhsCount = journeyCountryCount(lhs)
                let rhsCount = journeyCountryCount(rhs)
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return journeyStartDate(lhs) > journeyStartDate(rhs)
            case .countryCountAscending:
                let lhsCount = journeyCountryCount(lhs)
                let rhsCount = journeyCountryCount(rhs)
                if lhsCount != rhsCount { return lhsCount < rhsCount }
                return journeyStartDate(lhs) > journeyStartDate(rhs)
            case .segmentCount:
                let lhsCount = journeySegmentCount(lhs)
                let rhsCount = journeySegmentCount(rhs)
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return journeyStartDate(lhs) > journeyStartDate(rhs)
            case .segmentCountAscending:
                let lhsCount = journeySegmentCount(lhs)
                let rhsCount = journeySegmentCount(rhs)
                if lhsCount != rhsCount { return lhsCount < rhsCount }
                return journeyStartDate(lhs) > journeyStartDate(rhs)
            }
        }
    }

    private var isDateSortSelected: Bool {
        countrySortOption == .recent || countrySortOption == .recentAscending
    }

    private var isNameSortSelected: Bool {
        countrySortOption == .nameAscending || countrySortOption == .nameDescending
    }

    private var isTripsSortSelected: Bool {
        countrySortOption == .tripCount || countrySortOption == .tripCountAscending
    }

    private var isCitiesSortSelected: Bool {
        countrySortOption == .cityCount || countrySortOption == .cityCountAscending
    }

    private var isJourneyDateSortSelected: Bool {
        journeySortOption == .recent || journeySortOption == .recentAscending
    }

    private var isJourneyNameSortSelected: Bool {
        journeySortOption == .nameAscending || journeySortOption == .nameDescending
    }

    private var isJourneyCountriesSortSelected: Bool {
        journeySortOption == .countryCount || journeySortOption == .countryCountAscending
    }

    private var isJourneySegmentsSortSelected: Bool {
        journeySortOption == .segmentCount || journeySortOption == .segmentCountAscending
    }

    private var activeDateDirectionTitle: String {
        countrySortOption == .recentAscending ? WanderlustSortL10n.oldest : WanderlustSortL10n.newest
    }

    private var activeNameDirectionTitle: String {
        countrySortOption == .nameDescending ? WanderlustSortL10n.descending : WanderlustSortL10n.ascending
    }

    private var activeTripsDirectionTitle: String {
        countrySortOption == .tripCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most
    }

    private var activeCitiesDirectionTitle: String {
        countrySortOption == .cityCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most
    }

    private var activeJourneyDateDirectionTitle: String {
        journeySortOption == .recentAscending ? WanderlustSortL10n.oldest : WanderlustSortL10n.newest
    }

    private var activeJourneyNameDirectionTitle: String {
        journeySortOption == .nameDescending ? WanderlustSortL10n.descending : WanderlustSortL10n.ascending
    }

    private var activeJourneyCountriesDirectionTitle: String {
        journeySortOption == .countryCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most
    }

    private var activeJourneySegmentsDirectionTitle: String {
        journeySortOption == .segmentCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most
    }

    private func journeyTitle(_ group: TripGroup) -> String {
        let title = group.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty else { return title }
        return WanderlustDateFormatter.dateRange(start: journeyStartDate(group), end: journeyEndDate(group))
    }

    private func journeyStartDate(_ group: TripGroup) -> Date {
        tripStore.trips(in: group).map(\.startDate).min() ?? group.createdAt
    }

    private func journeyEndDate(_ group: TripGroup) -> Date {
        tripStore.trips(in: group).map(\.endDate).max() ?? group.updatedAt
    }

    private func journeyCountryCount(_ group: TripGroup) -> Int {
        Set(
            tripStore.trips(in: group)
                .flatMap(\.cities)
                .map { city in
                    WanderlustNameResolver.normalizedCountryCode(city.countryCode, fallback: city.countryName)
                }
                .filter { !$0.isEmpty }
        ).count
    }

    private func journeySegmentCount(_ group: TripGroup) -> Int {
        group.tripIDs.count + group.transportItems.count
    }

    /// 国グループを組み立てる。国の同定は `VisitedCountryAggregator` へ委譲する。
    ///
    /// 以前はこれが computed property で、body 評価のたびに全旅行 × 全都市を
    /// 走査していた。さらに独自のキー生成をしていたため、World / Passport /
    /// Statistics と国数が食い違う原因にもなっていた。
    private static func makeCountryGroups(from trips: [Trip]) -> [CountryGroup] {
        let tripsByID = Dictionary(
            trips.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return VisitedCountryAggregator.visitedCountries(in: trips)
            .map { country in
                let groupTrips = country.tripIDs
                    .compactMap { tripsByID[$0] }
                    .sorted { $0.startDate > $1.startDate }

                return CountryGroup(
                    id: country.id,
                    countryName: country.displayName,
                    flagEmoji: country.flagEmoji,
                    cityCount: country.cityNames.count,
                    tripCount: groupTrips.count,
                    mostRecentDate: groupTrips.map(\.endDate).max() ?? country.lastVisit,
                    trips: groupTrips
                )
            }
            .sorted { $0.mostRecentDate > $1.mostRecentDate }
    }

    var body: some View {
        Group {
            if tripStore.trips.isEmpty {
                tripsEmptyState
            } else {
                tripsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WanderlustColor.background)
        .navigationTitle(WanderlustL10n.string("Trips", table: .trips))
        .toolbarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewMode == .journeys {
                    journeySortMenu
                } else {
                    countrySortMenu
                }
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                addTripButton
            }
        }
        .sheet(isPresented: $showStartJourney) {
            StartJourneyView(tripStore: tripStore)
        }
        .sheet(item: $editingJourneyGroup) { group in
            CreateTripGroupView(tripStore: tripStore, editingGroup: group)
        }
        .alert(
            WanderlustL10n.string("Delete this journey?", table: .trips, fallback: "Delete this journey?"),
            isPresented: Binding(
                get: { deletingJourneyGroup != nil },
                set: { if !$0 { deletingJourneyGroup = nil } }
            )
        ) {
            Button(WanderlustL10n.string("Delete Journey", table: .trips, fallback: "Delete Journey"), role: .destructive) {
                if let group = deletingJourneyGroup {
                    deleteJourney(group)
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                deletingJourneyGroup = nil
            }
        } message: {
            Text(WanderlustL10n.string("This deletes the trips in this journey.", table: .trips, fallback: "This deletes the trips in this journey."))
        }
    }

    private var tripsList: some View {
        List {
            viewModePicker
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if viewMode == .journeys {
                ForEach(journeyGroups) { group in
                    NavigationLink {
                        TripGroupDetailView(group: group, tripStore: tripStore)
                    } label: {
                        TripGroupCard(group: group, trips: tripStore.trips(in: group))
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            editingJourneyGroup = group
                        } label: {
                            Label(String(localized: "Edit"), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            } else {
                ForEach(countryGroups) { group in
                    NavigationLink {
                        CountryTripsView(group: group, tripStore: tripStore)
                    } label: {
                        CountryGroupCard(group: group)
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var viewModePicker: some View {
        Picker(WanderlustL10n.string("View", table: .trips, fallback: "View"), selection: $viewMode) {
            ForEach(TripsViewMode.allCases) { mode in
                Text(mode.title)
                    .font(.title2.weight(.semibold))
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .frame(height: 56)
        .wanderlustReadableWidth()
    }

    private var countrySortMenu: some View {
        WanderlustSortMenuButton(
            accessibilityLabel: WanderlustSortL10n.button,
            items: [
                WanderlustSortMenuItem(
                    id: "name",
                    title: WanderlustSortL10n.name,
                    subtitle: activeNameDirectionTitle,
                    isSelected: isNameSortSelected
                ) {
                    toggleNameSortImmediately()
                },
                WanderlustSortMenuItem(
                    id: "date",
                    title: WanderlustSortL10n.dateVisited,
                    subtitle: activeDateDirectionTitle,
                    isSelected: isDateSortSelected
                ) {
                    toggleDateSortImmediately()
                },
                WanderlustSortMenuItem(
                    id: "trips",
                    title: WanderlustSortL10n.trips,
                    subtitle: activeTripsDirectionTitle,
                    isSelected: isTripsSortSelected
                ) {
                    toggleTripsSortImmediately()
                },
                WanderlustSortMenuItem(
                    id: "cities",
                    title: WanderlustSortL10n.cities,
                    subtitle: activeCitiesDirectionTitle,
                    isSelected: isCitiesSortSelected
                ) {
                    toggleCitiesSortImmediately()
                }
            ]
        )
    }

    private var journeySortMenu: some View {
        WanderlustSortMenuButton(
            accessibilityLabel: WanderlustSortL10n.button,
            items: [
                WanderlustSortMenuItem(
                    id: "name",
                    title: WanderlustSortL10n.name,
                    subtitle: activeJourneyNameDirectionTitle,
                    isSelected: isJourneyNameSortSelected
                ) {
                    toggleJourneyNameSortImmediately()
                },
                WanderlustSortMenuItem(
                    id: "date",
                    title: WanderlustSortL10n.dateVisited,
                    subtitle: activeJourneyDateDirectionTitle,
                    isSelected: isJourneyDateSortSelected
                ) {
                    toggleJourneyDateSortImmediately()
                },
                WanderlustSortMenuItem(
                    id: "countries",
                    title: WanderlustL10n.string("Countries", table: .trips, fallback: "Countries"),
                    subtitle: activeJourneyCountriesDirectionTitle,
                    isSelected: isJourneyCountriesSortSelected
                ) {
                    toggleJourneyCountriesSortImmediately()
                },
                WanderlustSortMenuItem(
                    id: "segments",
                    title: WanderlustL10n.string("Segments", table: .trips, fallback: "Segments"),
                    subtitle: activeJourneySegmentsDirectionTitle,
                    isSelected: isJourneySegmentsSortSelected
                ) {
                    toggleJourneySegmentsSortImmediately()
                }
            ]
        )
    }

    private var addTripButton: some View {
        Button {
            showStartJourney = true
        } label: {
            WanderlustToolbarIconLabel(
                title: WanderlustL10n.string("Start Journey", table: .trips, fallback: "Start Journey"),
                systemImage: "plus",
                color: .blue
            )
        }
        .accessibilityLabel(WanderlustL10n.string("Start Journey", table: .trips, fallback: "Start Journey"))
    }

    private func toggleJourneyDateSortImmediately() {
        let newOption: TripsJourneySortOption
        switch journeySortOption {
        case .recent:
            newOption = .recentAscending
        case .recentAscending:
            newOption = .recent
        default:
            newOption = journeyLastDateDirection == .ascending ? .recentAscending : .recent
        }

        applyJourneySortOption(newOption)
    }

    private func toggleJourneyNameSortImmediately() {
        let newOption: TripsJourneySortOption
        switch journeySortOption {
        case .nameAscending:
            newOption = .nameDescending
        case .nameDescending:
            newOption = .nameAscending
        default:
            newOption = journeyLastNameDirection == .descending ? .nameDescending : .nameAscending
        }

        applyJourneySortOption(newOption)
    }

    private func toggleJourneyCountriesSortImmediately() {
        let newOption: TripsJourneySortOption
        switch journeySortOption {
        case .countryCount:
            newOption = .countryCountAscending
        case .countryCountAscending:
            newOption = .countryCount
        default:
            newOption = journeyLastCountriesDirection == .ascending ? .countryCountAscending : .countryCount
        }

        applyJourneySortOption(newOption)
    }

    private func toggleJourneySegmentsSortImmediately() {
        let newOption: TripsJourneySortOption
        switch journeySortOption {
        case .segmentCount:
            newOption = .segmentCountAscending
        case .segmentCountAscending:
            newOption = .segmentCount
        default:
            newOption = journeyLastSegmentsDirection == .ascending ? .segmentCountAscending : .segmentCount
        }

        applyJourneySortOption(newOption)
    }

    private func applyJourneySortOption(_ newOption: TripsJourneySortOption) {
        var transaction = Transaction()
        transaction.animation = nil

        withTransaction(transaction) {
            journeySortOption = newOption
        }

        if newOption == .recent {
            journeyLastDateDirection = .descending
        } else if newOption == .recentAscending {
            journeyLastDateDirection = .ascending
        } else if newOption == .nameAscending {
            journeyLastNameDirection = .ascending
        } else if newOption == .nameDescending {
            journeyLastNameDirection = .descending
        } else if newOption == .countryCount {
            journeyLastCountriesDirection = .descending
        } else if newOption == .countryCountAscending {
            journeyLastCountriesDirection = .ascending
        } else if newOption == .segmentCount {
            journeyLastSegmentsDirection = .descending
        } else if newOption == .segmentCountAscending {
            journeyLastSegmentsDirection = .ascending
        }
    }

    private func toggleDateSortImmediately() {
        let newOption: TripsCountrySortOption
        switch countrySortOption {
        case .recent:
            newOption = .recentAscending
        case .recentAscending:
            newOption = .recent
        default:
            newOption = lastDateSortDirection == .ascending ? .recentAscending : .recent
        }

        applySortOption(newOption)
    }

    private func toggleNameSortImmediately() {
        let newOption: TripsCountrySortOption
        switch countrySortOption {
        case .nameAscending:
            newOption = .nameDescending
        case .nameDescending:
            newOption = .nameAscending
        default:
            newOption = lastNameSortDirection == .descending ? .nameDescending : .nameAscending
        }

        applySortOption(newOption)
    }

    private func toggleTripsSortImmediately() {
        let newOption: TripsCountrySortOption
        switch countrySortOption {
        case .tripCount:
            newOption = .tripCountAscending
        case .tripCountAscending:
            newOption = .tripCount
        default:
            newOption = lastTripsSortDirection == .ascending ? .tripCountAscending : .tripCount
        }

        applySortOption(newOption)
    }

    private func toggleCitiesSortImmediately() {
        let newOption: TripsCountrySortOption
        switch countrySortOption {
        case .cityCount:
            newOption = .cityCountAscending
        case .cityCountAscending:
            newOption = .cityCount
        default:
            newOption = lastCitiesSortDirection == .ascending ? .cityCountAscending : .cityCount
        }

        applySortOption(newOption)
    }

    private func applySortOption(_ newOption: TripsCountrySortOption) {
        var transaction = Transaction()
        transaction.animation = nil

        withTransaction(transaction) {
            countrySortOption = newOption
        }

        if newOption == .recent {
            lastDateSortDirection = .descending
        } else if newOption == .recentAscending {
            lastDateSortDirection = .ascending
        } else if newOption == .nameAscending {
            lastNameSortDirection = .ascending
        } else if newOption == .nameDescending {
            lastNameSortDirection = .descending
        } else if newOption == .tripCount {
            lastTripsSortDirection = .descending
        } else if newOption == .tripCountAscending {
            lastTripsSortDirection = .ascending
        } else if newOption == .cityCount {
            lastCitiesSortDirection = .descending
        } else if newOption == .cityCountAscending {
            lastCitiesSortDirection = .ascending
        }
    }

    private func deleteJourney(_ group: TripGroup) {
        for trip in tripStore.trips(in: group) {
            _ = tripStore.deleteTrip(trip)
        }
        _ = tripStore.deleteTripGroup(id: group.id)
        deletingJourneyGroup = nil
    }

    // MARK: - Countries List

    private var tripsEmptyState: some View {
        WanderlustEmptyStateView(
            systemImage: "suitcase.fill",
            title: WanderlustL10n.string("No Trips Yet", table: .trips),
            message: WanderlustL10n.string("Add your first trip to begin building your Wanderlust", table: .trips)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, WanderlustSpacing.xLarge)
    }

    private var journeysListContent: some View {
        LazyVStack(spacing: 12) {
            ForEach(journeyGroups) { group in
                NavigationLink {
                    TripGroupDetailView(group: group, tripStore: tripStore)
                } label: {
                    TripGroupCard(group: group, trips: tripStore.trips(in: group))
                }
                .navigationLinkIndicatorVisibility(.hidden)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
        .wanderlustReadableWidth()
    }

    private var countriesListContent: some View {
        LazyVStack(spacing: 12) {
            ForEach(countryGroups) { group in
                NavigationLink {
                    CountryTripsView(group: group, tripStore: tripStore)
                } label: {
                    CountryGroupCard(group: group)
                }
                .navigationLinkIndicatorVisibility(.hidden)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 32)
        .wanderlustReadableWidth()
    }

}

// MARK: - Trip Group Card

private struct TripGroupCountryTag: Identifiable {
    let id: String
    let name: String
    let flag: String
    let tripID: UUID
    let firstDate: Date
}

private struct TripGroupCard: View {
    let group: TripGroup
    let trips: [Trip]

    private var countryTags: [TripGroupCountryTag] {
        var seen = Set<String>()
        return trips
            .sorted { first, second in
                if first.startDate != second.startDate {
                    return first.startDate < second.startDate
                }
                return first.displayTitle.localizedCaseInsensitiveCompare(second.displayTitle) == .orderedAscending
            }
            .flatMap { trip in
                trip.cities.sortedByVisitDate().map { city in (trip, city) }
            }
            .compactMap { trip, city in
                Self.countryTag(for: city, in: trip, seen: &seen)
            }
    }

    private var routeStops: [(name: String, countryName: String)] {
        var seen = Set<String>()
        let cities = trips
            .sorted { first, second in
                if first.startDate != second.startDate {
                    return first.startDate < second.startDate
                }
                return first.displayTitle.localizedCaseInsensitiveCompare(second.displayTitle) == .orderedAscending
            }
            .flatMap { $0.cities.sortedByVisitDate() }

        return cities.compactMap { city in
            let key = "\(city.localizedCountryName)|\(city.localizedName)"
            guard seen.insert(key).inserted else { return nil }
            return (city.localizedName, city.localizedCountryName)
        }
    }

    private var legacyAutomaticTitle: String {
        routeStops
            .map(\.name)
            .prefix(3)
            .joined(separator: "・")
    }

    private var legacyMonthAutomaticTitle: String {
        String(
            format: WanderlustL10n.string("%@ Trip", table: .trips, fallback: "%@ Trip"),
            WanderlustDateFormatter.monthYear(startDate)
        )
    }

    private var displayTitle: String {
        let trimmedTitle = group.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty ||
            trimmedTitle == legacyAutomaticTitle ||
            trimmedTitle == legacyMonthAutomaticTitle {
            return WanderlustDateFormatter.dateRange(start: startDate, end: endDate)
        }

        return trimmedTitle
    }

    private var startDate: Date {
        trips.map(\.startDate).min() ?? group.createdAt
    }

    private var endDate: Date {
        trips.map(\.endDate).max() ?? group.updatedAt
    }

    private var cityCount: Int {
        trips.reduce(0) { $0 + $1.cities.count }
    }

    private var flightCount: Int {
        trips.reduce(0) { $0 + $1.flights.count }
    }

    fileprivate static func countryTag(
        for city: VisitedCity,
        in trip: Trip,
        seen: inout Set<String>
    ) -> TripGroupCountryTag? {
        let code = WanderlustNameResolver.normalizedCountryCode(
            city.countryCode,
            fallback: city.countryName
        )
        let country = GeoJSONLoader.shared.country(withISOCode: code) ??
            GeoJSONLoader.shared.country(named: city.countryName)
        let key = country?.isoCode ?? (code.isEmpty ? city.localizedCountryName : code)
        guard seen.insert(key).inserted else { return nil }
        return TripGroupCountryTag(
            id: key,
            name: country?.displayName ?? city.localizedCountryName,
            flag: country?.flagEmoji ?? "🌍",
            tripID: trip.id,
            firstDate: city.earliestVisitDate ?? trip.startDate
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(displayTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            Text(WanderlustDateFormatter.dateRange(start: startDate, end: endDate))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 10) {
                HStack(spacing: -3) {
                    ForEach(Array(countryTags.prefix(4).enumerated()), id: \.offset) { _, tag in
                        Text(tag.flag)
                            .font(.body)
                            .frame(width: 28, height: 28)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(Circle())
                            .accessibilityHidden(true)
                    }

                    if countryTags.count > 4 {
                        Text("+\(countryTags.count - 4)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(Circle())
                    }
                }

                Spacer(minLength: 0)

                TripCardCount(
                    systemImage: "map",
                    text: PluralizationFormatter.compactCountries(countryTags.count)
                )
                TripCardCount(
                    systemImage: "building.2",
                    text: PluralizationFormatter.compactCities(cityCount)
                )
                if flightCount > 0 {
                    TripCardCount(
                        systemImage: "airplane",
                        text: PluralizationFormatter.compactFlightSummary(flightCount)
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .wanderlustContentCard(radius: WanderlustRadius.xLarge, padding: WanderlustSpacing.large)
        .contentShape(RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Trip Group Detail

private struct TripGroupDetailView: View {
    let group: TripGroup
    @ObservedObject var tripStore: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAddTrip = false
    @State private var showEditJourney = false
    @State private var showsDeleteConfirmation = false

    private var liveGroup: TripGroup? {
        tripStore.tripGroups.first { $0.id == group.id }
    }

    private var liveTrips: [Trip] {
        guard let liveGroup else { return [] }
        return tripStore.trips(in: liveGroup)
    }

    private var countryTags: [TripGroupCountryTag] {
        var seen = Set<String>()
        return liveTrips
            .sorted { first, second in
                if first.startDate != second.startDate {
                    return first.startDate < second.startDate
                }
                return first.displayTitle.localizedCaseInsensitiveCompare(second.displayTitle) == .orderedAscending
            }
            .flatMap { trip in
                trip.cities.sortedByVisitDate().map { city in (trip, city) }
            }
            .compactMap { trip, city in
                TripGroupCard.countryTag(for: city, in: trip, seen: &seen)
            }
    }

    private var itineraryRows: [TripGroupItineraryRow] {
        TripGroupItineraryRow.rows(
            from: liveTrips,
            transportItems: []
        )
    }

    private var startDate: Date {
        liveTrips.map(\.startDate).min() ?? liveGroup?.createdAt ?? group.createdAt
    }

    private var endDate: Date {
        liveTrips.map(\.endDate).max() ?? liveGroup?.updatedAt ?? group.updatedAt
    }

    private var routeStops: [(name: String, countryName: String)] {
        var seen = Set<String>()
        let cities = liveTrips
            .sorted { first, second in
                if first.startDate != second.startDate {
                    return first.startDate < second.startDate
                }
                return first.displayTitle.localizedCaseInsensitiveCompare(second.displayTitle) == .orderedAscending
            }
            .flatMap { $0.cities.sortedByVisitDate() }

        return cities.compactMap { city in
            let key = "\(city.localizedCountryName)|\(city.localizedName)"
            guard seen.insert(key).inserted else { return nil }
            return (city.localizedName, city.localizedCountryName)
        }
    }

    private var legacyAutomaticTitle: String {
        routeStops
            .map(\.name)
            .prefix(3)
            .joined(separator: "・")
    }

    private var legacyMonthAutomaticTitle: String {
        String(
            format: WanderlustL10n.string("%@ Trip", table: .trips, fallback: "%@ Trip"),
            WanderlustDateFormatter.monthYear(startDate)
        )
    }

    private var displayTitle: String {
        let title = (liveGroup?.title ?? group.title).trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty ||
            title == legacyAutomaticTitle ||
            title == legacyMonthAutomaticTitle {
            return WanderlustDateFormatter.dateRange(start: startDate, end: endDate)
        }

        return title
    }

    var body: some View {
        List {
            Section(WanderlustL10n.string("Date", table: .trips, fallback: "Date")) {
                Label {
                    Text(WanderlustDateFormatter.dateRange(start: startDate, end: endDate))
                        .font(.body)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "calendar")
                        .foregroundStyle(.blue)
                }
            }

            if !countryTags.isEmpty {
                Section(WanderlustL10n.string("Visited Countries", table: .trips, fallback: "Visited Countries")) {
                    ForEach(countryTags) { country in
                        NavigationLink {
                            TripDetailView(tripID: country.tripID, tripStore: tripStore)
                        } label: {
                            HStack(spacing: 12) {
                                Text(country.flag)
                                    .font(.title3)
                                    .frame(width: 30)

                                Text(country.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            if !itineraryRows.isEmpty {
                Section(WanderlustL10n.string("Itinerary", table: .trips, fallback: "Itinerary")) {
                    VStack(spacing: 0) {
                        let groups = TripGroupItineraryVisualGroup.groups(from: itineraryRows)
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            TripGroupItineraryGroupView(group: group, showsChevron: false)

                            if index < groups.count - 1 {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }

            if let notes = liveGroup?.notes, !notes.isEmpty {
                Section(WanderlustL10n.string("Notes", table: .trips)) {
                    Text(notes)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(displayTitle)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showAddTrip = true
                    } label: {
                        Label(
                            WanderlustL10n.string("Add Segment", table: .trips, fallback: "Add Segment"),
                            systemImage: "plus"
                        )
                    }

                    Button {
                        showEditJourney = true
                    } label: {
                        Label(String(localized: "Edit"), systemImage: "pencil")
                    }

                    if liveTrips.count > 1 {
                        Button(role: .destructive) {
                            showsDeleteConfirmation = true
                        } label: {
                            Label(
                                WanderlustL10n.string("Ungroup Journey", table: .trips, fallback: "Ungroup Journey"),
                                systemImage: "folder.badge.minus"
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddTrip) {
            AddTripView(
                parentTripGroupID: group.id,
                saveButtonTitle: WanderlustL10n.string("Add", table: .trips)
            )
        }
        .sheet(isPresented: $showEditJourney) {
            if let liveGroup {
                CreateTripGroupView(tripStore: tripStore, editingGroup: liveGroup)
            }
        }
        .alert(
            WanderlustL10n.string("Ungroup this journey?", table: .trips, fallback: "Ungroup this journey?"),
            isPresented: $showsDeleteConfirmation
        ) {
            Button(WanderlustL10n.string("Ungroup Journey", table: .trips, fallback: "Ungroup Journey"), role: .destructive) {
                _ = tripStore.deleteTripGroup(id: group.id)
                dismiss()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(WanderlustL10n.string("Trips stay saved and return to separate journeys.", table: .trips, fallback: "Trips stay saved and return to separate journeys."))
        }
        .onChange(of: liveTrips.map(\.id)) { _, newValue in
            if newValue.isEmpty {
                dismiss()
            }
        }
    }
}

private struct TripGroupTimelineView: View {
    let group: TripGroup
    @ObservedObject var tripStore: TripStore
    @State private var viewingTripID: UUID?

    private var liveGroup: TripGroup? {
        tripStore.tripGroups.first { $0.id == group.id }
    }

    private var liveTrips: [Trip] {
        guard let liveGroup else { return [] }
        return tripStore.trips(in: liveGroup)
    }

    private var itineraryRows: [TripGroupItineraryRow] {
        TripGroupItineraryRow.rows(
            from: liveTrips,
            transportItems: []
        )
    }

    private func itineraryRow(_ row: TripGroupItineraryRow) -> some View {
        Group {
            if let tripID = row.tripID {
                Button {
                    viewingTripID = tripID
                } label: {
                    TripGroupItineraryRowView(row: row)
                }
                .buttonStyle(.plain)
            } else {
                TripGroupItineraryRowView(row: row)
            }
        }
        .listRowSeparator(.hidden)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 0) {
                    let groups = TripGroupItineraryVisualGroup.groups(from: itineraryRows)
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        TripGroupItineraryGroupView(group: group) { tripID in
                            viewingTripID = tripID
                        }

                        if index < groups.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(WanderlustL10n.string("Travel Flow", table: .trips, fallback: "Travel Flow"))
        .toolbarTitleDisplayMode(.inline)
        .navigationDestination(item: $viewingTripID) { tripID in
            TripDetailView(tripID: tripID, tripStore: tripStore)
        }
    }
}

private struct TripGroupItineraryDay: Identifiable {
    let id: Date
    let date: Date
    let rows: [TripGroupItineraryRow]

    static func days(from rows: [TripGroupItineraryRow]) -> [TripGroupItineraryDay] {
        let calendar = Calendar.current
        let groupedRows = Dictionary(grouping: rows) { row in
            calendar.startOfDay(for: row.date)
        }
        return groupedRows
            .map { date, rows in
                TripGroupItineraryDay(id: date, date: date, rows: rows.sortedByTime())
            }
            .sorted { $0.date < $1.date }
    }
}

private struct TripGroupItineraryRow: Identifiable {
    enum Kind {
        case city
        case flight
        case transport
    }

    let id: String
    let kind: Kind
    let date: Date
    let title: String
    let subtitle: String
    let detail: String
    let dateText: String
    let tripID: UUID?
    let transportItemID: UUID?
    let systemImage: String

    init(
        id: String,
        kind: Kind,
        date: Date,
        title: String,
        subtitle: String,
        detail: String = "",
        dateText: String = "",
        tripID: UUID? = nil,
        transportItemID: UUID? = nil,
        systemImage: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.date = date
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.dateText = dateText
        self.tripID = tripID
        self.transportItemID = transportItemID
        self.systemImage = systemImage ?? kind.systemImage
    }

    static func rows(from trips: [Trip], transportItems: [TripGroupTransportItem]) -> [TripGroupItineraryRow] {
        var rows: [TripGroupItineraryRow] = []

        for trip in trips {
            for city in trip.cities {
                rows.append(
                    TripGroupItineraryRow(
                        id: "city-\(trip.id)-\(city.id)",
                        kind: .city,
                        date: city.arrivalDate ?? trip.startDate,
                        title: city.localizedName,
                        subtitle: city.localizedCountryName,
                        detail: WanderlustL10n.string("Stay", table: .trips, fallback: "Stay"),
                        dateText: cityDateText(city, fallbackStartDate: trip.startDate, fallbackEndDate: trip.endDate),
                        tripID: trip.id
                    )
                )
            }

            for flight in trip.flights {
                let flightNumber = flight.displayFlightNumber
                let title = flight.routeTitle.isEmpty
                    ? WanderlustL10n.string("Flight", table: .trips, fallback: "Flight")
                    : flight.routeTitle
                rows.append(
                    TripGroupItineraryRow(
                        id: "flight-\(trip.id)-\(flight.id)",
                        kind: .flight,
                        date: flight.departureDate,
                        title: title,
                        subtitle: flightNumber,
                        detail: WanderlustL10n.string("Flight", table: .trips, fallback: "Flight"),
                        tripID: trip.id
                    )
                )
            }
        }

        for item in transportItems {
            let subtitle = [item.transportationType.title, WanderlustDateFormatter.date(item.departureDate)]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            rows.append(
                TripGroupItineraryRow(
                    id: "transport-\(item.id)",
                    kind: .transport,
                    date: item.departureDate,
                    title: item.displayTitle,
                    subtitle: subtitle,
                    detail: item.transportationType.title,
                    transportItemID: item.id,
                    systemImage: item.transportationType.systemImage
                )
            )
        }

        return rows.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func cityDateText(_ city: VisitedCity, fallbackStartDate: Date, fallbackEndDate: Date) -> String {
        let startDate = city.arrivalDate ?? fallbackStartDate
        let endDate = city.departureDate ?? city.arrivalDate ?? fallbackEndDate
        return WanderlustDateFormatter.dateRange(start: startDate, end: endDate)
    }
}

private struct TripGroupItineraryVisualGroup: Identifiable {
    let id: String
    let kind: TripGroupItineraryRow.Kind
    let detail: String
    let systemImage: String
    var rows: [TripGroupItineraryRow]

    static func groups(from rows: [TripGroupItineraryRow]) -> [TripGroupItineraryVisualGroup] {
        rows.reduce(into: []) { groups, row in
            if let lastIndex = groups.indices.last, groups[lastIndex].canAppend(row) {
                groups[lastIndex].rows.append(row)
            } else {
                groups.append(
                    TripGroupItineraryVisualGroup(
                        id: row.id,
                        kind: row.kind,
                        detail: row.detail,
                        systemImage: row.systemImage,
                        rows: [row]
                    )
                )
            }
        }
    }

    private func canAppend(_ row: TripGroupItineraryRow) -> Bool {
        guard row.kind == kind else { return false }

        switch kind {
        case .flight:
            return true
        case .city:
            return rows.last?.subtitle == row.subtitle
        case .transport:
            return rows.last?.detail == row.detail
        }
    }
}

private extension TripGroupItineraryRow.Kind {
    var systemImage: String {
        switch self {
        case .city:
            return "mappin.and.ellipse"
        case .flight:
            return "airplane"
        case .transport:
            return "point.topleft.down.curvedto.point.bottomright.up"
        }
    }

    var tint: Color {
        switch self {
        case .city:
            return .green
        case .flight:
            return .blue
        case .transport:
            return .orange
        }
    }
}

private extension Array where Element == TripGroupItineraryRow {
    func sortedByTime() -> [TripGroupItineraryRow] {
        sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

private struct TripGroupTimelineDateHeader: View {
    let date: Date

    var body: some View {
        Text(WanderlustDateFormatter.date(date))
            .font(.headline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

private struct TripGroupItineraryRowView: View {
    let row: TripGroupItineraryRow
    var showsChevron = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: row.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(row.kind.tint)
                    )

                Rectangle()
                    .fill(row.kind.tint.opacity(0.22))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 34)
            .frame(minHeight: 68)

            VStack(alignment: .leading, spacing: 6) {
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(row.kind.tint)
                }

                Text(row.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !row.subtitle.isEmpty {
                    Text(row.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !row.dateText.isEmpty {
                    Text(row.dateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron, row.tripID != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.vertical, 10)
    }
}

private struct TripGroupItineraryGroupView: View {
    let group: TripGroupItineraryVisualGroup
    var showsChevron = true
    var onSelectTrip: ((UUID) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: group.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(group.kind.tint)
                    )

                if group.rows.count > 1 {
                    Rectangle()
                        .fill(group.kind.tint.opacity(0.22))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 34)
            .frame(minHeight: group.rows.count > 1 ? 92 : 54)

            VStack(alignment: .leading, spacing: 0) {
                if !group.detail.isEmpty {
                    Text(group.detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(group.kind.tint)
                        .padding(.bottom, 6)
                }

                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    itineraryContent(for: row)

                    if index < group.rows.count - 1 {
                        Divider()
                            .padding(.vertical, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func itineraryContent(for row: TripGroupItineraryRow) -> some View {
        if let tripID = row.tripID, let onSelectTrip {
            Button {
                onSelectTrip(tripID)
            } label: {
                TripGroupItineraryContentView(row: row, showsChevron: showsChevron)
            }
            .buttonStyle(.plain)
        } else {
            TripGroupItineraryContentView(row: row, showsChevron: showsChevron)
        }
    }
}

private struct TripGroupItineraryContentView: View {
    let row: TripGroupItineraryRow
    let showsChevron: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(row.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !row.subtitle.isEmpty {
                    Text(row.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !row.dateText.isEmpty {
                    Text(row.dateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron, row.tripID != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
    }
}

// MARK: - Start Journey

struct StartJourneyView: View {
    @ObservedObject var tripStore: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var tripGroupID: UUID?
    @State private var showsSegment = false
    @State private var hasCommittedJourney = false

    private var liveGroup: TripGroup? {
        tripGroupID.flatMap { id in
            tripStore.tripGroups.first { $0.id == id }
        }
    }

    private var liveTrips: [Trip] {
        guard let liveGroup else { return [] }
        return tripStore.trips(in: liveGroup)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        WanderlustL10n.string("Journey Name", table: .trips, fallback: "Journey Name"),
                        text: $title
                    )
                    .textInputAutocapitalization(.words)
                } header: {
                    WanderlustSectionHeader(title: WanderlustL10n.string("Journey Details", table: .trips, fallback: "Journey Details"))
                } footer: {
                    Text(WanderlustL10n.string("Name this trip and add visits, flights, or other travel as one itinerary.", table: .trips, fallback: "Name this trip and add visits, flights, or other travel as one itinerary."))
                }

                Section {
                    Button {
                        showsSegment = true
                    } label: {
                        Label(
                            liveTrips.isEmpty
                            ? WanderlustL10n.string("Add First Segment", table: .trips, fallback: "Add First Segment")
                            : WanderlustL10n.string("Add Segment", table: .trips, fallback: "Add Segment"),
                            systemImage: "plus.circle.fill"
                        )
                    }
                    Text(WanderlustL10n.string("Add each destination or travel day in order.", table: .trips, fallback: "Add each destination or travel day in order."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    WanderlustSectionHeader(title: WanderlustL10n.string("Itinerary", table: .trips, fallback: "Itinerary"))
                }

                if !liveTrips.isEmpty {
                    Section {
                        ForEach(liveTrips) { trip in
                            TripCardView(trip: trip)
                                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        }
                    } header: {
                        WanderlustSectionHeader(title: WanderlustL10n.string("Country Trips", table: .trips, fallback: "Country Trips"))
                    }
                }

                Section {
                    TextField(
                        WanderlustL10n.string("Journey Notes", table: .trips, fallback: "Journey Notes"),
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                } header: {
                    WanderlustSectionHeader(title: WanderlustL10n.string("Notes", table: .trips, fallback: "Notes"))
                }
            }
            .navigationTitle(WanderlustL10n.string("Start Journey", table: .trips, fallback: "Start Journey"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        cancelJourney()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        saveJourney()
                    }
                    .disabled(liveTrips.isEmpty)
                }
            }
            .sheet(isPresented: $showsSegment) {
                AddTripView(
                    parentTripGroupID: tripGroupID,
                    saveButtonTitle: WanderlustL10n.string("Add", table: .trips)
                ) { trip in
                    if tripGroupID == nil {
                        tripGroupID = tripStore.tripGroups.first { group in
                            group.tripIDs == [trip.id]
                        }?.id ?? trip.id
                    }
                    updateJourneyMetadata(groupID: tripGroupID ?? trip.id)
                }
            }
            .onChange(of: title) { _, _ in
                updateJourneyMetadata()
            }
            .onChange(of: notes) { _, _ in
                updateJourneyMetadata()
            }
            .onDisappear {
                discardUncommittedJourneyIfNeeded()
            }
        }
    }

    private func saveJourney() {
        updateJourneyMetadata()
        hasCommittedJourney = true
        dismiss()
    }

    private func cancelJourney() {
        discardUncommittedJourneyIfNeeded()
        dismiss()
    }

    private func discardUncommittedJourneyIfNeeded() {
        guard !showsSegment, !hasCommittedJourney, let liveGroup else { return }
        for trip in tripStore.trips(in: liveGroup) {
            _ = tripStore.deleteTrip(trip)
        }
        _ = tripStore.deleteTripGroup(id: liveGroup.id)
        tripGroupID = nil
    }

    private func updateJourneyMetadata(groupID explicitGroupID: UUID? = nil) {
        guard let groupID = explicitGroupID ?? tripGroupID,
              let group = tripStore.tripGroups.first(where: { $0.id == groupID }) else { return }
        _ = tripStore.updateTripGroup(
            id: group.id,
            title: title,
            notes: notes,
            tripIDs: group.tripIDs
        )
    }
}

// MARK: - Create Trip Group

private struct CreateTripGroupView: View {
    @ObservedObject var tripStore: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var selectedTripIDs = Set<UUID>()
    @State private var selectedTripOrder: [UUID] = []
    let editingGroup: TripGroup?

    init(tripStore: TripStore, editingGroup: TripGroup? = nil) {
        self.tripStore = tripStore
        self.editingGroup = editingGroup
        _title = State(initialValue: editingGroup?.title ?? "")
        _notes = State(initialValue: editingGroup?.notes ?? "")
        _selectedTripIDs = State(initialValue: Set(editingGroup?.tripIDs ?? []))
        _selectedTripOrder = State(initialValue: editingGroup?.tripIDs ?? [])
    }

    private var sortedTrips: [Trip] {
        tripStore.trips.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var selectedTripsInOrder: [Trip] {
        let tripsByID = Dictionary(sortedTrips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let orderedTrips = selectedTripOrder.compactMap { id in
            selectedTripIDs.contains(id) ? tripsByID[id] : nil
        }
        let orderedIDs = Set(orderedTrips.map(\.id))
        let remainingTrips = sortedTrips.filter { selectedTripIDs.contains($0.id) && !orderedIDs.contains($0.id) }
        return orderedTrips + remainingTrips
    }

    private var availableTrips: [Trip] {
        sortedTrips.filter { !selectedTripIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(
                        WanderlustL10n.string("Journey Name", table: .trips, fallback: "Journey Name"),
                        text: $title
                    )
                    .textInputAutocapitalization(.words)

                    TextField(
                        WanderlustL10n.string("Journey Notes", table: .trips, fallback: "Journey Notes"),
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }

                if !selectedTripsInOrder.isEmpty {
                    Section {
                        ForEach(Array(selectedTripsInOrder.enumerated()), id: \.element.id) { index, trip in
                            selectedTripLabel(for: trip, index: index)
                        }
                        .onMove(perform: moveSelectedTrips)
                        .onDelete(perform: removeSelectedTrips)
                    } header: {
                        WanderlustSectionHeader(title: WanderlustL10n.string("Included Trips", table: .trips, fallback: "Included Trips"))
                    } footer: {
                        if selectedTripsInOrder.count > 1 {
                            Text(WanderlustL10n.string("Drag to reorder. Swipe to remove.", table: .trips, fallback: "Drag to reorder. Swipe to remove."))
                        }
                    }
                }

                if !availableTrips.isEmpty {
                    Section {
                        ForEach(availableTrips) { trip in
                            Button {
                                addTrip(trip.id)
                            } label: {
                                availableTripLabel(for: trip)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        WanderlustSectionHeader(title: WanderlustL10n.string("Add Visit Records", table: .trips, fallback: "Add Visit Records"))
                    }
                }
            }
            .navigationTitle(
                editingGroup == nil
                ? WanderlustL10n.string("New Journey", table: .trips, fallback: "New Journey")
                : WanderlustL10n.string("Edit Journey", table: .trips, fallback: "Edit Journey")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(editingGroup == nil ? WanderlustL10n.string("Add", table: .trips) : String(localized: "Done")) {
                        save()
                    }
                    .disabled(selectedTripIDs.isEmpty)
                }
            }
        }
    }

    private func addTrip(_ tripID: UUID) {
        guard !selectedTripIDs.contains(tripID) else { return }
        selectedTripIDs.insert(tripID)
        selectedTripOrder.append(tripID)
    }

    private func removeSelectedTrips(at offsets: IndexSet) {
        let trips = selectedTripsInOrder
        for offset in offsets {
            guard trips.indices.contains(offset) else { continue }
            let tripID = trips[offset].id
            selectedTripIDs.remove(tripID)
            selectedTripOrder.removeAll { $0 == tripID }
        }
    }

    private func toggleTrip(_ tripID: UUID) {
        if selectedTripIDs.contains(tripID) {
            selectedTripIDs.remove(tripID)
            selectedTripOrder.removeAll { $0 == tripID }
        } else {
            selectedTripIDs.insert(tripID)
            selectedTripOrder.append(tripID)
        }
    }

    private func moveSelectedTrips(from source: IndexSet, to destination: Int) {
        var orderedIDs = selectedTripsInOrder.map(\.id)
        orderedIDs.move(fromOffsets: source, toOffset: destination)
        selectedTripOrder = orderedIDs
    }

    private func save() {
        let selectedIDs = selectedTripsInOrder.map(\.id)

        if let editingGroup {
            guard tripStore.updateTripGroup(
                id: editingGroup.id,
                title: title,
                notes: notes,
                tripIDs: selectedIDs
            ) else {
                return
            }
        } else {
            guard tripStore.addTripGroup(
                title: title,
                notes: notes,
                tripIDs: selectedIDs
            ) else {
                return
            }
        }
        dismiss()
    }

    private func selectedTripLabel(for trip: Trip, index: Int) -> some View {
        tripSelectionLabel(
            for: trip,
            accessory: AnyView(
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.blue, in: Circle())
            )
        )
    }

    private func availableTripLabel(for trip: Trip) -> some View {
        tripSelectionLabel(
            for: trip,
            accessory: AnyView(
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)
                    .imageScale(.large)
            )
        )
    }

    private func tripSelectionLabel(for trip: Trip, accessory: AnyView) -> some View {
        HStack(spacing: 12) {
            accessory
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.cities.map(\.localizedName).prefix(3).joined(separator: "・"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(WanderlustDateFormatter.dateRange(start: trip.startDate, end: trip.endDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Country Group Card

private struct CountryGroupCard: View {
    let group: CountryGroup

    var body: some View {
        HStack(spacing: 16) {
            Text(group.flagEmoji)
                .font(.largeTitle)
                .frame(width: 58, height: 58)
                .background(
                    Circle()
                        .fill(Color(.tertiarySystemGroupedBackground))
                )

            VStack(alignment: .leading, spacing: 7) {
                Text(group.countryName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(PluralizationFormatter.trips(group.tripCount))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.72))
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .wanderlustContentCard(radius: WanderlustRadius.xLarge, padding: WanderlustSpacing.large)
        .contentShape(RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Country Trips View

private struct CountryTripsView: View {
    let group: CountryGroup
    @ObservedObject var tripStore: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingTrip: Trip?
    @State private var deletingTrip: Trip?
    @State private var viewingTripID: UUID?
    @AppStorage("Trips.countryTripsSortOption") private var sortOption: CountryTripSortOption = .dateDescending
    @AppStorage("Trips.countryTripsLastDateDirection") private var lastDateSortDirection: TripsNameSortDirection = .descending
    @AppStorage("Trips.countryTripsLastDurationDirection") private var lastDurationSortDirection: TripsNameSortDirection = .descending
    @AppStorage("Trips.countryTripsLastCitiesDirection") private var lastCitiesSortDirection: TripsNameSortDirection = .descending
    @AppStorage("Trips.countryTripsLastFlightsDirection") private var lastFlightsSortDirection: TripsNameSortDirection = .descending

    private var matchingTrips: [Trip] {
        tripStore.trips.filter { tripContainsCountry($0) }
    }

    private var liveTrips: [Trip] {
        matchingTrips.sorted { lhs, rhs in
            switch sortOption {
            case .dateDescending:
                if lhs.startDate != rhs.startDate { return lhs.startDate > rhs.startDate }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .dateAscending:
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
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
                if lhs.cities.count != rhs.cities.count { return lhs.cities.count > rhs.cities.count }
                return lhs.startDate > rhs.startDate
            case .cityCountAscending:
                if lhs.cities.count != rhs.cities.count { return lhs.cities.count < rhs.cities.count }
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

    private var liveTripIDs: [UUID] {
        liveTrips.map(\.id)
    }

    var body: some View {
        List {
            if liveTrips.isEmpty {
                countryTripsEmptyState
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(liveTrips) { trip in
                    countryTripRow(trip)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(group.flagEmoji) \(group.countryName)")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if matchingTrips.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    countryTripSortMenu
                }
            }
        }
        .sheet(item: $editingTrip) { trip in
            EditTripView(trip: trip)
        }
        .navigationDestination(item: $viewingTripID) { tripID in
            TripDetailView(tripID: tripID, tripStore: tripStore)
        }
        .alert(
            WanderlustL10n.string("Delete this trip?", table: .trips),
            isPresented: Binding(
                get: { deletingTrip != nil },
                set: { if !$0 { deletingTrip = nil } }
            )
        ) {
            Button(WanderlustL10n.string("Delete Trip", table: .trips), role: .destructive) {
                if let trip = deletingTrip {
                    deleteCountryTrip(trip)
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                deletingTrip = nil
            }
            .tint(.blue)
            .fontWeight(.regular)
        } message: {
            Text(WanderlustL10n.string("This action cannot be undone.", table: .errors))
        }
        .onChange(of: liveTripIDs) { _, newIDs in
            editingTrip = editingTrip.flatMap { trip in
                newIDs.contains(trip.id) ? trip : nil
            }
            deletingTrip = deletingTrip.flatMap { trip in
                newIDs.contains(trip.id) ? trip : nil
            }
            if let viewingTripID, !newIDs.contains(viewingTripID) {
                self.viewingTripID = nil
            }
            if newIDs.isEmpty {
                Task { @MainActor in
                    await Task.yield()
                    dismiss()
                }
            }
        }
    }

    private func tripContainsCountry(_ trip: Trip) -> Bool {
        trip.cities.contains { city in
            let code = WanderlustNameResolver.normalizedCountryCode(
                city.countryCode,
                fallback: city.countryName
            )
            let key = code.isEmpty ? city.countryName : code
            return key == group.id
        }
    }

    private func deleteCountryTrip(_ trip: Trip) {
        editingTrip = nil
        viewingTripID = nil
        deletingTrip = nil

        guard tripStore.deleteTrip(trip) else { return }
        let remainingTripIDs = matchingTrips
            .filter { $0.id != trip.id }
            .map(\.id)
        if remainingTripIDs.isEmpty {
            Task { @MainActor in
                await Task.yield()
                dismiss()
            }
        }
    }

    private func countryTripRow(_ trip: Trip) -> some View {
        Button {
            viewingTripID = trip.id
        } label: {
            TripCardView(trip: trip)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deletingTrip = trip
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
            .tint(.red)

            Button {
                editingTrip = trip
            } label: {
                Label(String(localized: "Edit"), systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button(role: .destructive) {
                deletingTrip = trip
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }

            Button {
                editingTrip = trip
            } label: {
                Label(String(localized: "Edit"), systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private var countryTripSortMenu: some View {
        WanderlustSortMenuButton(
            accessibilityLabel: WanderlustSortL10n.button,
            items: [
                sortMenuItem(
                    id: "date",
                    title: WanderlustSortL10n.date,
                    isSelected: sortOption == .dateDescending || sortOption == .dateAscending,
                    subtitle: sortOption == .dateAscending ? WanderlustSortL10n.oldest : WanderlustSortL10n.newest,
                    action: toggleDateSort
                ),
                sortMenuItem(
                    id: "duration",
                    title: WanderlustSortL10n.duration,
                    isSelected: sortOption == .durationDescending || sortOption == .durationAscending,
                    subtitle: sortOption == .durationAscending ? WanderlustSortL10n.shortest : WanderlustSortL10n.longest,
                    action: toggleDurationSort
                ),
                sortMenuItem(
                    id: "cities",
                    title: WanderlustSortL10n.cities,
                    isSelected: sortOption == .cityCountDescending || sortOption == .cityCountAscending,
                    subtitle: sortOption == .cityCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most,
                    action: toggleCitiesSort
                ),
                sortMenuItem(
                    id: "flights",
                    title: WanderlustSortL10n.flights,
                    isSelected: sortOption == .flightCountDescending || sortOption == .flightCountAscending,
                    subtitle: sortOption == .flightCountAscending ? WanderlustSortL10n.fewest : WanderlustSortL10n.most,
                    action: toggleFlightsSort
                )
            ]
        )
    }

    private func sortMenuItem(
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

    private func applySortOption(_ newOption: CountryTripSortOption) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            sortOption = newOption
        }
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

    private var countryTripsEmptyState: some View {
        WanderlustEmptyStateView(
            systemImage: "magnifyingglass",
            title: WanderlustL10n.string("No Results", table: .trips, fallback: "No Results"),
            message: WanderlustL10n.string("Try a different city, date, memo, route, airline, or flight number.", table: .trips, fallback: "Try a different city, date, memo, route, airline, or flight number.")
        )
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 420)
    }

    private func tripDurationDays(_ trip: Trip) -> Int {
        max(Calendar.current.dateComponents([.day], from: trip.startDate, to: trip.endDate).day ?? 0, 0)
    }

}

// MARK: - Trip Card

struct TripCardView: View {
    let trip: Trip
    var countryName: String? = nil
    var countryFlag: String? = nil
    var showsCityCount = true
    var showsFlightCount = true
    var showsChevron = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if let countryName, !countryName.isEmpty {
                    HStack(spacing: 8) {
                        if let countryFlag, !countryFlag.isEmpty {
                            Text(countryFlag)
                                .font(.title3)
                                .accessibilityHidden(true)
                        }

                        Text(countryName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }

                Text(tripDateRangeText(trip))
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                if !trip.cities.isEmpty {
                    Text(trip.cities.map(\.localizedName).joined(separator: "・"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 16) {
                    if showsCityCount {
                        TripCardCount(
                            systemImage: "building.2",
                            text: PluralizationFormatter.compactCities(trip.cities.count)
                        )
                    }
                    if showsFlightCount, trip.flights.count > 0 {
                        TripCardCount(
                            systemImage: "airplane",
                            text: PluralizationFormatter.compactFlightSummary(trip.flights.count)
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 90)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
    }

    private func tripDateRangeText(_ trip: Trip) -> String {
        WanderlustDateFormatter.dateRange(start: trip.startDate, end: trip.endDate)
    }

}

private struct TripCardCount: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 16, alignment: .center)
                .accessibilityHidden(true)

            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
