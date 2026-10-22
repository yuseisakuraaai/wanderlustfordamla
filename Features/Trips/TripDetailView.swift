import SwiftUI
import MapKit
import CoreLocation

struct TripDetailView: View {
    let tripID: UUID

    @ObservedObject
    var tripStore: TripStore

    @Environment(\.dismiss)
    private var dismiss

    @State private var showEditTrip = false
    @State private var selectedFlightPlayback: FlightPlaybackSelection?
    @State private var showDeleteConfirmation = false

    private var trip: Trip? {
        tripStore.trip(
            withID: tripID
        )
    }

    init(
        trip: Trip,
        tripStore: TripStore
    ) {
        self.tripID = trip.id
        self.tripStore = tripStore
    }

    init(
        tripID: UUID,
        tripStore: TripStore
    ) {
        self.tripID = tripID
        self.tripStore = tripStore
    }

    var body: some View {
        Group {
            if let trip {
                tripContent(trip)
            } else {
                ContentUnavailableView(
                    WanderlustL10n.string("Trip Not Found", table: .errors),
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        WanderlustL10n.string("This trip may have been deleted.", table: .trips)
                    )
                )
            }
        }
        .navigationTitle(trip?.displayTitle ?? "")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if trip != nil {
                ToolbarItem(
                    placement: .primaryAction
                ) {
                    Menu {
                        Button {
                            showEditTrip = true
                        } label: {
                            Label(
                                WanderlustL10n.string("Edit Trip", table: .trips),
                                systemImage: "pencil"
                            )
                        }

                        Button(
                            role: .destructive
                        ) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(
                                WanderlustL10n.string("Delete Trip", table: .trips),
                                systemImage: "trash"
                            )
                        }
                    } label: {
                        Image(
                            systemName: "ellipsis.circle"
                        )
                    }
                }
            }
        }
        .sheet(
            isPresented: $showEditTrip
        ) {
            if let trip {
                EditTripView(
                    trip: trip
                )
            }
        }
        .sheet(
            item: $selectedFlightPlayback
        ) { selection in
            FlightMapView(
                flights: selection.flights
            )
        }
        .confirmationDialog(
            WanderlustL10n.string("Delete this trip?", table: .trips),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                WanderlustL10n.string("Delete Trip", table: .trips),
                role: .destructive
            ) {
                deleteTrip()
            }

            Button(
                String(localized: "Cancel"),
                role: .cancel
            ) {}
        } message: {
            Text(
                WanderlustL10n.string("This action cannot be undone.", table: .errors)
            )
        }
        .onChange(of: tripStore.trips.map(\.id)) { _, tripIDs in
            guard !tripIDs.contains(tripID) else { return }
            showEditTrip = false
            selectedFlightPlayback = nil
            showDeleteConfirmation = false
            Task { @MainActor in
                await Task.yield()
                dismiss()
            }
        }
    }

    // MARK: - Main Content

    private func tripContent(
        _ trip: Trip
    ) -> some View {
            List {
            headerSection(trip)
            tripInformationSection(trip)
            citiesSection(trip)
            transportationSection(trip)
            if trip.transportationTypes.contains(.airplane), !trip.flights.isEmpty {
                flightsSection(trip)
            }

            if !trip.notes.isEmpty {
                notesSection(trip)
            }
        }
    }

    // MARK: - Header

    private func headerSection(
        _ trip: Trip
    ) -> some View {
        Section {
            HStack(spacing: 14) {
                DetailMetric(
                    text: PluralizationFormatter.compactCities(trip.cityCount),
                    systemImage: "building.2.fill"
                )

                DetailMetric(
                    text: PluralizationFormatter.compactFlights(trip.flightCount),
                    systemImage: "airplane"
                )
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Trip Period

    private func tripInformationSection(
        _ trip: Trip
    ) -> some View {
        Section {
            TripDateDetailRow(
                title: WanderlustL10n.string("Start Date", table: .trips),
                value: localizedTripDate(trip.startDate)
            )

            TripDateDetailRow(
                title: WanderlustL10n.string("End Date", table: .trips),
                value: localizedTripDate(trip.endDate)
            )

            LabeledContent(
                WanderlustL10n.string("Trip Days", table: .statistics),
                value: PluralizationFormatter.days(tripDurationDays(trip))
            )
            .font(.body)
            .padding(.vertical, 6)
        } header: {
            WanderlustSectionHeader(title: WanderlustL10n.string("Trip Period", table: .trips))
        }
    }

    private func localizedTripDate(_ date: Date) -> String {
        WanderlustDateFormatter.date(date)
    }

    private func tripDurationDays(_ trip: Trip) -> Int {
        let start = Calendar.current.startOfDay(for: trip.startDate)
        let end = Calendar.current.startOfDay(for: trip.endDate)
        return max((Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1, 1)
    }

    private func transportationSection(
        _ trip: Trip
    ) -> some View {
        Section {
            let types = trip.transportationTypes.sorted { $0.sortOrder < $1.sortOrder }
            ForEach(types) { type in
                Label {
                    Text(type.title)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: type.systemImage)
                        .foregroundStyle(.blue)
                }
                    .font(.body)
                    .padding(.vertical, 6)
            }
        } header: {
            WanderlustSectionHeader(title: WanderlustL10n.string("Transportation", table: .trips))
        }
    }

    private func localizedCountryTags(for trip: Trip) -> [(name: String, flag: String)] {
        var seen = Set<String>()
        return trip.cities.compactMap { city in
            let code = WanderlustNameResolver.normalizedCountryCode(
                city.countryCode,
                fallback: city.countryName
            )
            let country = GeoJSONLoader.shared.country(withISOCode: code) ??
                GeoJSONLoader.shared.country(named: city.countryName)
            let name = country?.displayName ?? city.localizedCountryName
            let key = country?.isoCode ?? (code.isEmpty ? name : code)
            guard seen.insert(key).inserted else { return nil }
            return (name, country?.flagEmoji ?? flagEmoji(forCountryName: name))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Cities

    private func citiesSection(
        _ trip: Trip
    ) -> some View {
        Section {
            if trip.cities.isEmpty {
                ContentUnavailableView(
                    WanderlustL10n.string("No Cities", table: .trips),
                    systemImage: "building.2",
                    description: Text(
                        WanderlustL10n.string("This trip has no cities.", table: .trips)
                    )
                )
            } else {
                ForEach(
                    trip.cities.sortedByVisitDate()
                ) { city in
                    TripDetailCityRow(
                        city: city
                    )
                }
            }
        } header: {
            WanderlustSectionHeader(title: WanderlustL10n.string("Cities", table: .trips))
        }
    }

    // MARK: - Flights

    @ViewBuilder
    private func flightsSection(
        _ trip: Trip
    ) -> some View {
        if trip.flights.isEmpty {
            Section {
                ContentUnavailableView(
                    WanderlustL10n.string("No Flights", table: .settings),
                    systemImage: "airplane",
                    description: Text(
                        WanderlustL10n.string("No flights were added to this trip.", table: .settings)
                    )
                )
            } header: {
                WanderlustSectionHeader(title: WanderlustL10n.string("Flights", table: .settings))
            }
        } else {
            let groups = TripFlightGroupBuilder.groups(for: trip.flights)
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                Section {
                    flightGroupButton(group)
                } header: {
                    if let headerTitle = group.headerTitle {
                        WanderlustSectionHeader(title: headerTitle)
                    } else if index == 0 {
                        WanderlustSectionHeader(title: WanderlustL10n.string("Flights", table: .settings))
                    }
                }
                .listSectionSpacing(14)
            }
        }
    }

    private func flightGroupButton(
        _ group: TripFlightGroup
    ) -> some View {
        Button {
            selectedFlightPlayback = FlightPlaybackSelection(flights: group.flights)
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
        .accessibilityLabel(
            group.title
        )
    }

    // MARK: - Notes

    private func notesSection(
        _ trip: Trip
    ) -> some View {
        Section {
            Text(trip.notes)
                .textSelection(.enabled)
        } header: {
            WanderlustSectionHeader(title: WanderlustL10n.string("Notes", table: .trips))
        }
    }

    // MARK: - Actions

    private func deleteTrip() {
        guard let trip else {
            return
        }

        showEditTrip = false
        selectedFlightPlayback = nil
        showDeleteConfirmation = false

        if tripStore.deleteTrip(trip) {
            Task { @MainActor in
                await Task.yield()
                dismiss()
            }
        }
    }

    @MainActor
    private func flagEmoji(
        forCountryName countryName: String
    ) -> String {
        GeoJSONLoader.shared
            .country(
                named: countryName
            )?
            .flagEmoji ?? "🌍"
    }
}

// MARK: - Detail Metric

private struct DetailMetric: View {
    let text: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28, alignment: .center)

            Text(text)
                .wanderlustFont(17, relativeTo: .body, weight: .medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 22, alignment: .center)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 104,
            alignment: .center
        )
        .background(
            .thinMaterial,
            in: RoundedRectangle(
                cornerRadius: WanderlustRadius.xLarge,
                style: .continuous
            )
        )
    }
}

// MARK: - Country Tag

private struct CountryTag: View {
    let countryName: String
    let flag: String

    var body: some View {
        HStack(spacing: 6) {
            Text(flag)

            Text(countryName)
                .font(
                    .caption.weight(.semibold)
                )
        }
        .padding(
            .horizontal,
            10
        )
        .padding(
            .vertical,
            7
        )
        .background(
            .thinMaterial,
            in: Capsule()
        )
    }
}

// MARK: - City Row

private struct TripDetailCityRow: View {
    let city: VisitedCity

    var body: some View {
        HStack(
            alignment: .top,
            spacing: 13
        ) {
            Text(
                flagEmoji(
                    countryCode:
                        city.countryCode
                )
            )
            .font(.title2)
            .frame(width: 34)

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text(city.localizedName)
                    .font(.headline)

                if !city.sortedPeriods.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(city.sortedPeriods) { period in
                            Text(
                                WanderlustDateFormatter.dateRange(
                                    start: period.startDate,
                                    end: period.endDate
                                )
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !city.notes.isEmpty {
                    Text(city.notes)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }

            Spacer()

        }
        .padding(.vertical, 5)
    }

    private func flagEmoji(
        countryCode: String
    ) -> String {
        let code = countryCode
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .uppercased()

        guard code.count == 2 else {
            return "🌍"
        }

        return code
            .unicodeScalars
            .compactMap { scalar in
                UnicodeScalar(
                    127397 +
                    scalar.value
                )
                .map(String.init)
            }
            .joined()
    }
}

// MARK: - Flight Row

private struct FlightPlaybackSelection: Identifiable {
    let id = UUID()
    let flights: [Flight]
}

struct TripFlightGroup: Identifiable {
    let id: String
    let headerTitle: String?
    let title: String
    let flights: [Flight]
}

enum TripFlightGroupBuilder {
    static func groups(for flights: [Flight]) -> [TripFlightGroup] {
        let sorted = sortedFlights(flights)
        var groups: [TripFlightGroup] = []

        for direction in [FlightDirection.outbound, .returnFlight] {
            let directionFlights = sorted.filter { $0.direction == direction }
            guard !directionFlights.isEmpty else { continue }
            groups.append(
                TripFlightGroup(
                    id: direction.rawValue,
                    headerTitle: nil,
                    title: direction.title,
                    flights: directionFlights
                )
            )
        }

        var needsTripFlightHeader = true
        for groupID in tripFlightGroupIDs(from: sorted) {
            for direction in [FlightDirection.tripOutbound, .tripReturn] {
                let directionFlights = sorted.filter {
                    $0.direction == direction && $0.tripFlightGroupID == groupID
                }
                guard !directionFlights.isEmpty else { continue }
                groups.append(
                    TripFlightGroup(
                        id: "trip-\(groupID.uuidString)-\(direction.rawValue)",
                        headerTitle: needsTripFlightHeader ? tripFlightGroupTitle(index: 0) : nil,
                        title: direction.title,
                        flights: directionFlights
                    )
                )
                needsTripFlightHeader = false
            }
        }

        let additionalFlights = sorted.filter { $0.direction == .additional }
        if !additionalFlights.isEmpty {
            groups.append(
                TripFlightGroup(
                    id: FlightDirection.additional.rawValue,
                    headerTitle: needsTripFlightHeader ? tripFlightGroupTitle(index: 0) : nil,
                    title: FlightDirection.additional.title,
                    flights: additionalFlights
                )
            )
        }

        return groups
    }

    private static func sortedFlights(_ flights: [Flight]) -> [Flight] {
        flights
            .enumerated()
            .sorted { left, right in
                if left.element.direction != right.element.direction {
                    return left.element.direction.sortOrder < right.element.direction.sortOrder
                }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    private static func tripFlightGroupIDs(from flights: [Flight]) -> [UUID] {
        var ids: [UUID] = []
        for flight in flights where flight.direction == .tripOutbound || flight.direction == .tripReturn {
            guard let groupID = flight.tripFlightGroupID,
                  !ids.contains(groupID) else {
                continue
            }
            ids.append(groupID)
        }
        return ids
    }

    private static func tripFlightGroupTitle(index: Int) -> String {
        guard index > 0 else {
            return WanderlustL10n.string(
                "Trip Flights",
                table: .trips,
                fallback: "Trip Flights"
            )
        }

        return String(
            format: WanderlustL10n.string(
                "Trip Flights %d",
                table: .trips,
                fallback: "Trip Flights %d"
            ),
            index + 1
        )
    }
}

struct TripDetailFlightGroupRow: View {
    let title: String
    let flights: [Flight]

    private var sortedFlights: [Flight] {
        flights.sorted { $0.departureDate < $1.departureDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .textCase(.uppercase)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            airlineSummaryView

            HStack(alignment: .center, spacing: 8) {
                ForEach(Array(routeCodes.enumerated()), id: \.offset) { index, code in
                    if index > 0 {
                        Image(systemName: "airplane")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.blue)
                    }

                    Text(code)
                        .font(.system(size: routeCodeFontSize, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .lineLimit(1)

            VStack(alignment: .leading, spacing: 8) {
                airportLine(
                    title: WanderlustL10n.string("Departure", table: .trips),
                    airportName: firstDepartureAirportName
                )

                ForEach(Array(layoverAirportNames.enumerated()), id: \.offset) { _, airportName in
                    airportLine(
                        title: WanderlustL10n.string("Connection", table: .trips, fallback: "Connection"),
                        airportName: airportName
                    )
                }

                airportLine(
                    title: WanderlustL10n.string("Arrival", table: .trips),
                    airportName: lastArrivalAirportName
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                flightInfoLine(
                    title: WanderlustL10n.string("Departure Time", table: .trips),
                    value: firstDepartureTime
                )

                if !lastArrivalTime.isEmpty {
                    flightInfoLine(
                        title: WanderlustL10n.string("Arrival Time", table: .trips),
                        value: lastArrivalTime
                    )
                }

                if !durationSummary.isEmpty {
                    flightInfoLine(
                        title: WanderlustL10n.string("Duration", table: .trips),
                        value: durationSummary
                    )
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var routeCodes: [String] {
        let codes = [sortedFlights.first?.departureAirportCode] + sortedFlights.map(\.arrivalAirportCode)
        return codes.compactMap { code -> String? in
            let cleaned = (code ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    private var routeCodeFontSize: CGFloat {
        routeCodes.count >= 4 ? 26 : 40
    }

    private var airlineSummaryView: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(airlineSummaryLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
    }

    private var airlineSummaryLines: [String] {
        if hasMultipleAirlines {
            let lines = sortedFlights
                .map(flightSummaryLine)
                .filter { !$0.isEmpty }
            return lines.isEmpty ? [WanderlustL10n.string("Flight", table: .trips)] : lines
        }

        let parts = uniqueAirlineNames + flightNumbers
        return [parts.isEmpty ? WanderlustL10n.string("Flight", table: .trips) : parts.joined(separator: "・")]
    }

    private var hasMultipleAirlines: Bool {
        uniqueAirlineNames.count > 1
    }

    private var uniqueAirlineNames: [String] {
        sortedFlights
            .map(\.localizedAirlineName)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, airline in
                if !result.contains(where: { $0.localizedCaseInsensitiveCompare(airline) == .orderedSame }) {
                    result.append(airline)
                }
            }
    }

    private var flightNumbers: [String] {
        sortedFlights
            .map(\.displayFlightNumber)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func flightSummaryLine(for flight: Flight) -> String {
        let airline = flight.localizedAirlineName.trimmingCharacters(in: .whitespacesAndNewlines)
        let flightNumber = flight.displayFlightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (airline.isEmpty, flightNumber.isEmpty) {
        case (true, true):
            return ""
        case (true, false):
            return flightNumber
        case (false, true):
            return airline
        case (false, false):
            return "\(airline)・\(flightNumber)"
        }
    }

    private var firstDepartureAirportName: String {
        sortedFlights.first?.localizedDepartureAirportName ?? ""
    }

    private var lastArrivalAirportName: String {
        sortedFlights.last?.localizedArrivalAirportName ?? ""
    }

    private var layoverAirportNames: [String] {
        guard sortedFlights.count > 1 else { return [] }
        return sortedFlights.dropLast()
            .map(\.localizedArrivalAirportName)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var firstDepartureTime: String {
        sortedFlights.first?.departureDisplayText ?? ""
    }

    private var lastArrivalTime: String {
        sortedFlights.last?.arrivalDisplayText ?? ""
    }

    private var durationSummary: String {
        guard let firstDeparture = sortedFlights.first?.departureDate,
              let lastArrival = sortedFlights.compactMap(\.arrivalDate).last,
              lastArrival > firstDeparture else {
            return ""
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: firstDeparture, to: lastArrival)
        return PluralizationFormatter.flightDuration(
            hours: components.hour ?? 0,
            minutes: components.minute ?? 0
        )
    }

    private func airportLine(title: String, airportName: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(airportName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? WanderlustL10n.string("Unknown Airport", table: .airports) : airportName)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }

    private func flightInfoLine(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
    }
}

struct TripDetailFlightRow: View {
    let flight: Flight
    var showsChevron = true

    var body: some View {
        FlightCardView(flight: flight, showsChevron: showsChevron)
    }
}

struct FlightCardView: View {
    let flight: Flight
    var showsChevron = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(flight.directionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .textCase(.uppercase)

                Spacer()

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(airlineSummary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(code(flight.departureAirportCode))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.58)
                    .lineLimit(1)

                Image(systemName: "airplane")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.blue)

                Text(code(flight.arrivalAirportCode))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.58)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                airportLine(
                    title: WanderlustL10n.string("Departure", table: .trips),
                    airportName: flight.localizedDepartureAirportName
                )
                airportLine(
                    title: WanderlustL10n.string("Arrival", table: .trips),
                    airportName: flight.localizedArrivalAirportName
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                flightInfoLine(
                    title: WanderlustL10n.string("Departure Time", table: .trips),
                    value: flight.departureDisplayText
                )
                if let arrivalDisplayText = flight.arrivalDisplayText {
                    flightInfoLine(
                        title: WanderlustL10n.string("Arrival Time", table: .trips),
                        value: arrivalDisplayText
                    )
                }
                if let durationText = flight.durationText {
                    flightInfoLine(
                        title: WanderlustL10n.string("Duration", table: .trips),
                        value: durationText
                    )
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var airlineSummary: String {
        let flightNumber = flight.displayFlightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let airline = flight.localizedAirlineName.trimmingCharacters(in: .whitespacesAndNewlines)

        if airline.isEmpty {
            return flightNumber.isEmpty ? WanderlustL10n.string("Flight", table: .trips) : flightNumber
        }

        if flightNumber.isEmpty {
            return airline
        }

        return "\(airline) \(flightNumber)"
    }

    private func code(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return cleaned.isEmpty ? "—" : cleaned
    }

    private func airportLine(title: String, airportName: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(airportName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? WanderlustL10n.string("Unknown Airport", table: .airports) : airportName)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }

    private func flightInfoLine(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Flow Layout

private struct FlowLayout:
    Layout
{
    let spacing: CGFloat

    init(
        spacing: CGFloat = 8
    ) {
        self.spacing = spacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maximumWidth =
            proposal.width ??
            .infinity

        var currentX:
            CGFloat = 0

        var currentY:
            CGFloat = 0

        var rowHeight:
            CGFloat = 0

        for subview in subviews {
            let size =
                subview.sizeThatFits(
                    .unspecified
                )

            if currentX + size.width >
                maximumWidth,
               currentX > 0 {
                currentX = 0
                currentY +=
                    rowHeight +
                    spacing
                rowHeight = 0
            }

            currentX +=
                size.width +
                spacing

            rowHeight = max(
                rowHeight,
                size.height
            )
        }

        return CGSize(
            width:
                maximumWidth
                    .isFinite
                ? maximumWidth
                : currentX,
            height:
                currentY +
                rowHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX =
            bounds.minX

        var currentY =
            bounds.minY

        var rowHeight:
            CGFloat = 0

        for subview in subviews {
            let size =
                subview.sizeThatFits(
                    .unspecified
                )

            if currentX + size.width >
                bounds.maxX,
               currentX > bounds.minX {
                currentX =
                    bounds.minX

                currentY +=
                    rowHeight +
                    spacing

                rowHeight = 0
            }

            subview.place(
                at: CGPoint(
                    x: currentX,
                    y: currentY
                ),
                proposal:
                    ProposedViewSize(
                        size
                    )
            )

            currentX +=
                size.width +
                spacing

            rowHeight = max(
                rowHeight,
                size.height
            )
        }
    }
}

private struct TripDateDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body)

            Spacer(minLength: 16)

            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
    }
}

private extension View {
    func tripDetailInformationCard() -> some View {
        self
            .padding(.horizontal, WanderlustSpacing.large)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                WanderlustColor.secondaryBackground,
                in: RoundedRectangle(
                    cornerRadius: WanderlustRadius.xLarge,
                    style: .continuous
                )
            )
    }

    func tripDetailCardListRow() -> some View {
        self
            .listRowInsets(
                EdgeInsets(
                    top: 6,
                    leading: WanderlustSpacing.large,
                    bottom: 6,
                    trailing: WanderlustSpacing.large
                )
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

#Preview {
    TripDetailView(
        trip: Trip(
            title: "Europe Trip",
            startDate: Date(),
            endDate: Date()
                .addingTimeInterval(
                    86_400 * 10
                ),
            notes:
                "Winter trip across Europe.",
            cities: [
                VisitedCity(
                    name: "Paris",
                    countryName:
                        "France",
                    countryCode:
                        "FR",
                    latitude:
                        48.8566,
                    longitude:
                        2.3522,
                    arrivalDate:
                        Date(),
                    departureDate:
                        Date()
                        .addingTimeInterval(
                            86_400 * 3
                        )
                )
            ],
            flights: [
                Flight(
                    airlineName:
                        "Japan Airlines",
                    airlineCode:
                        "JL",
                    flightNumber:
                        "45",
                    departureAirportName:
                        "Tokyo Haneda Airport",
                    departureAirportCode:
                        "HND",
                    departureLatitude:
                        35.5494,
                    departureLongitude:
                        139.7798,
                    arrivalAirportName:
                        "Charles de Gaulle Airport",
                    arrivalAirportCode:
                        "CDG",
                    arrivalLatitude:
                        49.0097,
                    arrivalLongitude:
                        2.5479,
                    departureDate:
                        Date(),
                    arrivalDate:
                        Date()
                        .addingTimeInterval(
                            43_200
                        )
                )
            ]
        ),
        tripStore: TripStore.shared
    )
}
