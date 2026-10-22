import SwiftUI

struct FlightEditorView: View {
    private enum ScrollAnchor: Hashable {
        case departureAirportSectionHeader
        case departureAirport
        case arrivalAirportSectionHeader
        case arrivalAirport
    }

    let existingFlight: Flight?
    let defaultDirection: FlightDirection
    let tripStartDate: Date
    let tripEndDate: Date
    private let previousFlight: Flight?
    let onSave: (Flight) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @FocusState private var focusedField: FlightEditorField?

    @State private var selectedAirline: Airline?
    @State private var inheritedAirline: Airline?
    @State private var airlineQuery = ""
    @State private var airlineSuggestions: [Airline] = []
    @State private var airlineSearchTask: Task<Void, Never>?

    @State private var flightNumber: String
    @State private var customTitle: String

    @State private var departureAirport: Airport?
    @State private var inheritedDepartureAirport: Airport?
    @State private var arrivalAirport: Airport?

    @State private var departureQuery = ""
    @State private var arrivalQuery = ""

    @State private var departureSuggestions: [Airport] = []
    @State private var arrivalSuggestions: [Airport] = []
    @State private var departureSearchTask: Task<Void, Never>?
    @State private var arrivalSearchTask: Task<Void, Never>?
    @State private var connectionCandidates: [WanderlustRouteConnectionCandidate] = []
    @State private var selectedConnectionCandidate: WanderlustRouteConnectionCandidate?
    @State private var showAllConnectionCandidates = false
    @State private var directRoute: WanderlustRoute?
    @State private var routeAirlineSuggestions: [Airline] = []
    @State private var routeLookupCompleted = false

    @State private var departureDate: Date
    @State private var arrivalDate: Date

    @State private var isLoadingData = false
    @State private var errorMessage: String?

    private enum FlightEditorField {
        case airline, flightNumber, departure, arrival
    }

    private static let defaultFlightInterval: TimeInterval = 7_200
    private static let defaultLayoverInterval: TimeInterval = 5_400

    private static func airportSearchKeyboardInset(for viewportHeight: CGFloat) -> CGFloat {
        min(max(viewportHeight * 0.30, 220), 300)
    }

    init(
        existingFlight: Flight? = nil,
        defaultDirection: FlightDirection = .additional,
        tripStartDate: Date,
        tripEndDate: Date,
        previousFlight: Flight? = nil,
        onSave: @escaping (Flight) -> Void
    ) {
        self.existingFlight = existingFlight
        self.defaultDirection = defaultDirection
        self.tripStartDate = tripStartDate
        self.tripEndDate = max(
            tripEndDate,
            tripStartDate
        )
        self.previousFlight = previousFlight
        self.onSave = onSave

        _flightNumber = State(
            initialValue:
                existingFlight?.flightNumber ?? ""
        )
        _customTitle = State(
            initialValue:
                existingFlight?.customTitle ?? ""
        )

        let fallbackDepartureDate = defaultDirection == .returnFlight ? tripEndDate : tripStartDate
        let initialDepartureDate: Date
        if let existingFlight {
            initialDepartureDate = Flight.localDisplayDate(
                fromAbsoluteDate: existingFlight.departureDate,
                timeZoneIdentifier: existingFlight.resolvedDepartureTimeZoneIdentifier
            )
        } else if let previousArrivalDate = previousFlight?.arrivalDate {
            initialDepartureDate = Flight.localDisplayDate(
                fromAbsoluteDate: previousArrivalDate,
                timeZoneIdentifier: previousFlight?.resolvedArrivalTimeZoneIdentifier ?? TimeZone.current.identifier
            )
            .addingTimeInterval(Self.defaultLayoverInterval)
        } else {
            initialDepartureDate = fallbackDepartureDate
        }

        let initialArrivalDate: Date
        if let existingFlight,
           let arrivalDate = existingFlight.arrivalDate {
            initialArrivalDate = Flight.localDisplayDate(
                fromAbsoluteDate: arrivalDate,
                timeZoneIdentifier: existingFlight.resolvedArrivalTimeZoneIdentifier
            )
        } else {
            initialArrivalDate = initialDepartureDate.addingTimeInterval(
                Self.defaultFlightInterval
            )
        }

        _departureDate = State(
            initialValue: initialDepartureDate
        )

        _arrivalDate = State(
            initialValue: initialArrivalDate
        )
    }

    private var navigationTitle: String {
        existingFlight == nil
        ? WanderlustL10n.string("Add Flight", table: .settings)
        : WanderlustL10n.string("Edit Flight", table: .settings)
    }

    private var resolvedDirection: FlightDirection {
        existingFlight?.direction ?? defaultDirection
    }

    private var canSave: Bool {
        departureAirport != nil &&
        arrivalAirport != nil &&
        departureAirport?.id != arrivalAirport?.id &&
        routeLookupCompleted &&
        hasSelectedRoutePath &&
        routeSupportsSelectedAirline &&
        flightArrivalAbsoluteDate > flightDepartureAbsoluteDate &&
        (existingFlight == nil || hasChanges)
    }

    private var hasSelectedRoutePath: Bool {
        directRoute != nil ||
        selectedConnectionCandidate != nil ||
        canPreserveExistingConnectionRoute
    }

    private var canPreserveExistingConnectionRoute: Bool {
        guard let existingFlight,
              existingFlight.effectiveLegs.count > 1,
              selectedConnectionCandidate == nil,
              departureAirport?.id == existingFlight.departureAirportID,
              arrivalAirport?.id == existingFlight.arrivalAirportID else {
            return false
        }

        return true
    }

    private var routeSupportsSelectedAirline: Bool {
        guard let selectedAirline else { return true }

        let availableRouteCodes = Set(routeAirlineCodes.map(normalizedAirlineCode).filter { !$0.isEmpty })
        guard !availableRouteCodes.isEmpty else { return true }

        let selectedCodes = Set([
            selectedAirline.normalizedIATACode,
            selectedAirline.normalizedICAOCode,
            selectedAirline.bestCode
        ].map(normalizedAirlineCode).filter { !$0.isEmpty })

        return !availableRouteCodes.isDisjoint(with: selectedCodes)
    }

    private func normalizedAirlineCode(_ code: String) -> String {
        code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private var hasChanges: Bool {
        guard let existingFlight else { return true }
        guard !isLoadingData else { return false }

        let existingCustomTitle = existingFlight.customTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentCustomTitle = resolvedDirection == .additional
            ? customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let currentAirlineCode = selectedAirline?.bestCode ?? ""
        let existingAirlineCode = existingFlight.airlineCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let currentDepartureCode = departureAirport?.bestCode ?? ""
        let currentArrivalCode = arrivalAirport?.bestCode ?? ""

        return currentCustomTitle != existingCustomTitle ||
            currentAirlineCode != existingAirlineCode ||
            cleanFlightNumber != existingFlight.flightNumber
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ||
            currentDepartureCode != existingFlight.departureAirportCode
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ||
            currentArrivalCode != existingFlight.arrivalAirportCode
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ||
            abs(flightDepartureAbsoluteDate.timeIntervalSince(existingFlight.departureDate)) >= 1 ||
            abs(flightArrivalAbsoluteDate.timeIntervalSince(existingFlight.arrivalDate ?? existingFlight.departureDate)) >= 1 ||
            selectedConnectionCandidate != nil
    }

    private var cleanFlightNumber: String {
        flightNumber
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .uppercased()
    }

    private var completeFlightNumber: String {
        guard let selectedAirline else {
            return cleanFlightNumber
        }

        let code =
            selectedAirline
                .bestCode

        guard !code.isEmpty else {
            return cleanFlightNumber
        }

        return "\(code)\(cleanFlightNumber)"
    }

    @ViewBuilder
    private var customTitleSection: some View {
        if resolvedDirection == .additional {
            Section(WanderlustL10n.string("Flight Name", table: .trips, fallback: "Flight Name")) {
                TextField(
                    WanderlustL10n.string("Trip Flight", table: .trips, fallback: "Trip Flight"),
                    text: $customTitle
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            }
        }
    }

    private var routeAirlineCodes: [String] {
        if let selectedConnectionCandidate {
            return selectedConnectionCandidate.preferredAirlineCodes
        }

        return directRoute?.airlines ?? []
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    Form {
                        customTitleSection
                        airlineSection
                        flightNumberSection
                        departureAirportSection
                        arrivalAirportSection
                        routeSection
                        dateAndTimeSection
                    }
                    .listSectionSpacing(.compact)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: focusedField) { _, field in
                        scrollFocusedAirportSearch(
                            field,
                            using: proxy
                        )
                    }
                    .safeAreaInset(edge: .bottom) {
                        Color.clear
                            .frame(
                                height: focusedField == .departure || focusedField == .arrival
                                    ? Self.airportSearchKeyboardInset(for: geometry.size.height)
                                    : 0
                            )
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                    .tint(.blue)
                    .fontWeight(.regular)
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(String(localized: "Save")) {
                        saveFlight()
                    }
                    .tint(.blue)
                    .fontWeight(.regular)
                    .disabled(!canSave)
                }

            }
            .task {
                await loadRequiredData()
            }
            .alert(
                WanderlustL10n.string("Couldn’t Save Flight", table: .errors),
                isPresented: Binding(
                    get: {
                        errorMessage != nil
                    },
                    set: { isPresented in
                        if !isPresented {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button(
                    String(localized: "OK"),
                    role: .cancel
                ) {
                    errorMessage = nil
                }
            } message: {
                Text(
                    errorMessage ??
                    WanderlustL10n.string("An unknown error occurred.", table: .errors)
                )
            }
        }
    }

    private func scrollFocusedAirportSearch(
        _ field: FlightEditorField?,
        using proxy: ScrollViewProxy
    ) {
        switch field {
        case .departure:
            scrollToDepartureAirportSearch(includeSuggestions: false, using: proxy)
        case .arrival:
            scrollToArrivalAirportSearch(
                includeSuggestions: false,
                using: proxy
            )
        default:
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard focusedField == field else { return }
            switch field {
            case .departure:
                scrollToDepartureAirportSearch(includeSuggestions: false, using: proxy)
            case .arrival:
                scrollToArrivalAirportSearch(
                    includeSuggestions: false,
                    using: proxy
                )
            default:
                break
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard focusedField == field else { return }
            switch field {
            case .departure:
                scrollToDepartureAirportSearch(includeSuggestions: false, using: proxy)
            case .arrival:
                scrollToArrivalAirportSearch(
                    includeSuggestions: false,
                    using: proxy
                )
            default:
                break
            }
        }
    }

    private func scrollToDepartureAirportSearch(
        includeSuggestions: Bool = true,
        using proxy: ScrollViewProxy
    ) {
        if includeSuggestions,
           let lastSuggestion = departureSuggestions.last {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(lastSuggestion.id, anchor: .bottom)
            }
            return
        }

        scrollToAirportSearch(
            .departureAirportSectionHeader,
            using: proxy
        )
    }

    private func scrollToArrivalAirportSearch(
        includeSuggestions: Bool = true,
        using proxy: ScrollViewProxy
    ) {
        if includeSuggestions,
           let lastSuggestion = arrivalSuggestions.last {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(lastSuggestion.id, anchor: .bottom)
            }
            return
        }

        scrollToAirportSearch(
            .arrivalAirportSectionHeader,
            using: proxy
        )
    }

    private func scrollToAirportSearch(
        _ anchor: ScrollAnchor,
        using proxy: ScrollViewProxy
    ) {
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    // MARK: - Airline

    private var airlineSection: some View {
        Section {
            if isLoadingData {
                HStack(spacing: 12) {
                    ProgressView()

                    Text(WanderlustL10n.string("Loading airline data…", table: .airlines))
                        .foregroundStyle(.secondary)
                }
            }

            if let selectedAirline {
                SelectedAirlineRow(
                    airline: selectedAirline,
                    onChange: {
                        resetSelectedAirline()
                    }
                )
            } else {
                MarkedSearchTextField(
                    placeholder: WanderlustL10n.string("Airline name", table: .airlines),
                    text: $airlineQuery,
                    onInputChange: { scheduleAirlineSuggestions($0) },
                    onChange: {},
                    onSubmit: {
                        Task {
                            await autocompleteAirline()
                        }
                    }
                )
                .frame(minHeight: 36)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                if shouldShowInheritedAirlineButton,
                   let inheritedAirline {
                    InheritedFlightValueButton(
                        title: WanderlustL10n.string(
                            "Use Previous Airline",
                            table: .trips,
                            fallback: "Use Previous Airline"
                        ),
                        subtitle: inheritedAirline.displayTitle,
                        systemImage: "arrow.triangle.2.circlepath"
                    ) {
                        selectAirline(inheritedAirline)
                    }
                }

                ForEach(
                    airlineSuggestions
                ) { airline in
                    Button {
                        selectAirline(
                            airline
                        )
                    } label: {
                        AirlineSuggestionRow(
                            airline: airline
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text(WanderlustL10n.string("Airline", table: .airlines))
        }
    }

    // MARK: - Flight Number

    private var flightNumberSection: some View {
        Section {
            TextField(
                WanderlustL10n.string("Flight Number", table: .settings),
                text: $flightNumber
            )
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.numberPad)
            .focused($focusedField, equals: .flightNumber)
            .submitLabel(.next)
            .onChange(of: flightNumber) {
                normalizeFlightNumber()
            }
            .frame(minHeight: 36)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            if selectedAirline != nil,
               !cleanFlightNumber.isEmpty {
                LabeledContent(
                    WanderlustL10n.string("Full flight number", table: .settings),
                    value: completeFlightNumber
                )
            }
        } header: {
            Text(WanderlustL10n.string("Flight Number", table: .settings))
        }
    }

    // MARK: - Departure Airport

    private var departureAirportSection: some View {
        Section {
            if let departureAirport {
                SelectedFlightAirportRow(
                    airport: departureAirport,
                    onChange: {
                        resetDepartureAirport()
                    }
                )
            } else {
                TextField(
                    WanderlustL10n.string("Airport, city or IATA code", table: .airports),
                    text: $departureQuery
                )
                .focused($focusedField, equals: .departure)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: departureQuery) { _, newValue in
                    scheduleDepartureSuggestions(newValue)
                }
                .onSubmit {
                    Task {
                        await autocompleteDepartureAirport()
                    }
                }
                .frame(minHeight: 36)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .id(ScrollAnchor.departureAirport)

                if shouldShowInheritedDepartureAirportButton,
                   let inheritedDepartureAirport {
                    InheritedFlightValueButton(
                        title: WanderlustL10n.string(
                            "Use Previous Arrival Airport",
                            table: .trips,
                            fallback: "Use Previous Arrival Airport"
                        ),
                        subtitle: inheritedDepartureAirport.displayTitle,
                        systemImage: "arrow.down.right.circle"
                    ) {
                        selectDepartureAirport(inheritedDepartureAirport)
                    }
                }

                ForEach(
                    departureSuggestions
                ) { airport in
                    Button {
                        selectDepartureAirport(
                            airport
                        )
                    } label: {
                        FlightAirportSuggestionRow(
                            airport: airport
                        )
                    }
                    .buttonStyle(.plain)
                }

            }
        } header: {
            Text(WanderlustL10n.string("Departure Airport", table: .airports))
                .id(ScrollAnchor.departureAirportSectionHeader)
        }
    }

    // MARK: - Arrival Airport

    private var arrivalAirportSection: some View {
        Section {
            if let arrivalAirport {
                SelectedFlightAirportRow(
                    airport: arrivalAirport,
                    onChange: {
                        resetArrivalAirport()
                    }
                )
            } else {
                TextField(
                    WanderlustL10n.string("Airport, city or IATA code", table: .airports),
                    text: $arrivalQuery
                )
                .focused($focusedField, equals: .arrival)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: arrivalQuery) { _, newValue in
                    scheduleArrivalSuggestions(newValue)
                }
                .onSubmit {
                    Task {
                        await autocompleteArrivalAirport()
                    }
                }
                .frame(minHeight: 36)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .id(ScrollAnchor.arrivalAirport)

                ForEach(
                    arrivalSuggestions
                ) { airport in
                    Button {
                        selectArrivalAirport(
                            airport
                        )
                    } label: {
                        FlightAirportSuggestionRow(
                            airport: airport
                        )
                    }
                    .buttonStyle(.plain)
                }

            }
        } header: {
            Text(WanderlustL10n.string("Arrival Airport", table: .airports))
                .id(ScrollAnchor.arrivalAirportSectionHeader)
        }
    }

    private func resetSelectedAirline() {
        selectedAirline = nil
        airlineQuery = ""
        airlineSuggestions = []
        focusedField = nil
    }

    private func resetDepartureAirport() {
        departureAirport = nil
        departureQuery = ""
        departureSuggestions = []
        clearRouteSelection()
        focusedField = nil
    }

    private func resetArrivalAirport() {
        arrivalAirport = nil
        arrivalQuery = ""
        arrivalSuggestions = []
        clearRouteSelection()
        focusedField = nil
    }

    private func clearRouteSelection() {
        directRoute = nil
        routeAirlineSuggestions = []
        routeLookupCompleted = false
        connectionCandidates = []
        selectedConnectionCandidate = nil
        showAllConnectionCandidates = false
    }

    private var shouldShowInheritedAirlineButton: Bool {
        existingFlight == nil &&
            selectedAirline == nil &&
            airlineQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            inheritedAirline != nil
    }

    private var shouldShowInheritedDepartureAirportButton: Bool {
        existingFlight == nil &&
            departureAirport == nil &&
            departureQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            inheritedDepartureAirport != nil
    }

    // MARK: - Route Suggestions

    @ViewBuilder
    private var routeSection: some View {
        if departureAirport != nil, arrivalAirport != nil {
            Section {
                if routeLookupCompleted {
                    if let directRoute {
                        Label(
                            WanderlustL10n.string("Route path available", table: .trips, fallback: "Route path available"),
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)

                        if !routeAirlineSuggestions.isEmpty {
                            RouteAirlineSuggestionStrip(
                                airlines: routeAirlineSuggestions,
                                selectedAirline: selectedAirline,
                                onSelect: selectAirline
                            )
                        } else if !directRoute.airlines.isEmpty {
                            Text(directRoute.airlines.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label(
                            WanderlustL10n.string("No direct route found", table: .trips, fallback: "No direct route found"),
                            systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                        )
                        .foregroundStyle(.secondary)

                        if connectionCandidates.isEmpty {
                            Text(
                                WanderlustL10n.string(
                                    "No route path was found for these airports.",
                                    table: .trips,
                                    fallback: "No route path was found for these airports."
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(visibleConnectionCandidates) { candidate in
                                RouteConnectionCandidateCard(
                                    candidate: candidate,
                                    airportName: localizedAirportName,
                                    airlineName: localizedAirlineName,
                                    isSelected: selectedConnectionCandidate == candidate
                                ) {
                                    useConnectionCandidate(candidate)
                                }
                            }

                            if connectionCandidates.count > visibleConnectionCandidates.count {
                                Button {
                                    withAnimation(.snappy) {
                                        showAllConnectionCandidates = true
                                    }
                                } label: {
                                    Label(
                                        WanderlustL10n.string("Show All", table: .trips, fallback: "Show All"),
                                        systemImage: "chevron.down"
                                    )
                                }
                            }
                        }
                    }

                    if hasSelectedRoutePath,
                       !routeSupportsSelectedAirline {
                        Label(
                            WanderlustL10n.string(
                                "Selected airline is not available on this route.",
                                table: .trips,
                                fallback: "Selected airline is not available on this route."
                            ),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(WanderlustL10n.string("Loading route data…", table: .trips, fallback: "Loading route data…"))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(WanderlustL10n.string("Route Suggestions", table: .trips, fallback: "Route Suggestions"))
            }
        }
    }

    private var visibleConnectionCandidates: [WanderlustRouteConnectionCandidate] {
        Array(connectionCandidates.prefix(showAllConnectionCandidates ? 10 : 3))
    }

    private var departureTimeZone: TimeZone {
        TimeZone(identifier: departureTimeZoneIdentifier) ?? .current
    }

    private var arrivalTimeZone: TimeZone {
        TimeZone(identifier: arrivalTimeZoneIdentifier) ?? .current
    }

    private var departureTimeZoneIdentifier: String {
        if let departureAirport {
            return Flight.resolvedTimeZoneIdentifier(
                storedIdentifier: departureAirport.resolvedTimeZoneIdentifier,
                airportCode: departureAirport.bestCode
            )
        }

        return existingFlight?.resolvedDepartureTimeZoneIdentifier ??
            TimeZone.current.identifier
    }

    private var arrivalTimeZoneIdentifier: String {
        if let arrivalAirport {
            return Flight.resolvedTimeZoneIdentifier(
                storedIdentifier: arrivalAirport.resolvedTimeZoneIdentifier,
                airportCode: arrivalAirport.bestCode
            )
        }

        return existingFlight?.resolvedArrivalTimeZoneIdentifier ??
            TimeZone.current.identifier
    }

    private var departurePickerDate: Binding<Date> {
        Binding(
            get: {
                Flight.absoluteDate(
                    fromLocalDate: departureDate,
                    timeZoneIdentifier: departureTimeZoneIdentifier
                )
            },
            set: { newValue in
                departureDate = Flight.localWallDate(
                    fromPickerDate: newValue,
                    timeZoneIdentifier: departureTimeZoneIdentifier
                )
                ensureArrivalAfterDeparture()
            }
        )
    }

    private var arrivalPickerDate: Binding<Date> {
        Binding(
            get: {
                Flight.absoluteDate(
                    fromLocalDate: arrivalDate,
                    timeZoneIdentifier: arrivalTimeZoneIdentifier
                )
            },
            set: { newValue in
                arrivalDate = Flight.localWallDate(
                    fromPickerDate: newValue,
                    timeZoneIdentifier: arrivalTimeZoneIdentifier
                )
            }
        )
    }

    private func ensureArrivalAfterDeparture() {
        let departureAbsolute = flightDepartureAbsoluteDate
        let arrivalAbsolute = flightArrivalAbsoluteDate
        guard arrivalAbsolute <= departureAbsolute else { return }

        let adjustedArrivalAbsolute = departureAbsolute.addingTimeInterval(Self.defaultFlightInterval)
        arrivalDate = Flight.localDisplayDate(
            fromAbsoluteDate: adjustedArrivalAbsolute,
            timeZoneIdentifier: arrivalTimeZoneIdentifier
        )
    }

    // MARK: - Date and Time

    private var dateAndTimeSection: some View {
        Section(WanderlustL10n.string("Date and Time", table: .trips)) {
            DatePicker(
                WanderlustL10n.string("Departure", table: .trips),
                selection: departurePickerDate
            )
            .environment(\.timeZone, departureTimeZone)

            DatePicker(
                WanderlustL10n.string("Arrival", table: .trips),
                selection: arrivalPickerDate
            )
            .environment(\.timeZone, arrivalTimeZone)

            if let formattedDuration {
                LabeledContent(
                    WanderlustL10n.string("Duration", table: .trips),
                    value: formattedDuration
                )
            }
        }
    }

    // MARK: - Loading

    @MainActor
    private func loadRequiredData() async {
        guard existingFlight != nil else {
            await loadInheritedValues()
            return
        }

        isLoadingData = true
        await loadExistingValues()
        isLoadingData = false
        Task { await refreshRouteContext() }
    }

    private func ensureAirlineDataLoaded() async {
    }

    private func ensureAirportDataLoaded() async {
    }

    private func ensureRouteDataLoaded() async {
    }

    private func loadExistingValues() async {
        guard let existingFlight else {
            return
        }

        if selectedAirline == nil {
            selectedAirline = try? await WanderlustStaticDataStore.shared.airline(
                matching: existingFlight.airlineCode
            )
        }

        if departureAirport == nil {
            departureAirport =
                (try? await WanderlustStaticDataStore.shared.airport(
                    matching: existingFlight.departureAirportCode
                )) ??
                fallbackAirport(
                    name:
                        existingFlight
                            .departureAirportName,
                    code:
                        existingFlight
                            .departureAirportCode,
                    latitude:
                        existingFlight
                            .departureLatitude,
                    longitude:
                        existingFlight
                            .departureLongitude,
                    timeZoneIdentifier:
                        existingFlight
                            .resolvedDepartureTimeZoneIdentifier
                )
        }

        if arrivalAirport == nil {
            arrivalAirport =
                (try? await WanderlustStaticDataStore.shared.airport(
                    matching: existingFlight.arrivalAirportCode
                )) ??
                fallbackAirport(
                    name:
                        existingFlight
                            .arrivalAirportName,
                    code:
                        existingFlight
                            .arrivalAirportCode,
                    latitude:
                        existingFlight
                            .arrivalLatitude,
                    longitude:
                        existingFlight
                            .arrivalLongitude,
                    timeZoneIdentifier:
                        existingFlight
                            .resolvedArrivalTimeZoneIdentifier
                )
        }
    }

    private func loadInheritedValues() async {
        guard existingFlight == nil,
              let previousFlight else {
            return
        }

        if inheritedAirline == nil {
            inheritedAirline = await resolveInheritedAirline(from: previousFlight)
        }

        if inheritedDepartureAirport == nil {
            inheritedDepartureAirport = await resolveInheritedDepartureAirport(from: previousFlight)
        }
    }

    private func resolveInheritedAirline(from flight: Flight) async -> Airline? {
        let code = flight.airlineCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let name = flight.airlineName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !code.isEmpty,
           let airline = try? await WanderlustStaticDataStore.shared.airline(matching: code) {
            return airline
        }

        guard !code.isEmpty || !name.isEmpty else { return nil }

        return Airline(
            id: code.isEmpty ? name : code,
            name: name.isEmpty ? code : name,
            iataCode: code.count == 2 ? code : "",
            icaoCode: code.count == 3 ? code : ""
        )
    }

    private func resolveInheritedDepartureAirport(from flight: Flight) async -> Airport? {
        let code = flight.arrivalAirportCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if !code.isEmpty,
           let airport = try? await WanderlustStaticDataStore.shared.airport(matching: code) {
            return airport
        }

        guard !code.isEmpty ||
            !flight.arrivalAirportName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return fallbackAirport(
            name: flight.arrivalAirportName,
            code: code,
            latitude: flight.arrivalLatitude,
            longitude: flight.arrivalLongitude,
            timeZoneIdentifier: flight.resolvedArrivalTimeZoneIdentifier
        )
    }

    // MARK: - Airline Search

    private func scheduleAirlineSuggestions(_ input: String? = nil) {
        airlineSearchTask?.cancel()
        let query =
            (input ?? airlineQuery)
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        guard query.count >= 1 else {
            airlineSuggestions = []
            return
        }

        airlineSearchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }

            let results = (try? await WanderlustStaticDataStore.shared.searchAirlines(
                query: query,
                limit: 5
            )) ?? []

            guard !Task.isCancelled else { return }
            airlineSuggestions = results
        }
    }

    private func selectAirline(
        _ airline: Airline
    ) {
        airlineSearchTask?.cancel()
        selectedAirline = airline
        airlineQuery = ""
        airlineSuggestions = []
        focusedField = nil
    }

    private func autocompleteAirline() async {
        if airlineSuggestions.isEmpty {
            airlineSuggestions = (try? await WanderlustStaticDataStore.shared.searchAirlines(
                query: airlineQuery,
                limit: 5
            )) ?? []
        }

        if let airline = airlineSuggestions.first {
            selectAirline(airline)
        }
    }

    private func airlineForCode(_ code: String) -> Airline? {
        let cleanedCode = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !cleanedCode.isEmpty else { return nil }

        return nil
    }

    private func airlineSuggestionPrecedes(_ first: Airline, _ second: Airline) -> Bool {
        if first.id == selectedAirline?.id {
            return true
        }

        if second.id == selectedAirline?.id {
            return false
        }

        if first.isMajorRouteAirline != second.isMajorRouteAirline {
            return first.isMajorRouteAirline
        }

        return first.displayName.localizedCaseInsensitiveCompare(second.displayName) == .orderedAscending
    }

    private func refreshRouteContext() async {
        selectedConnectionCandidate = nil
        showAllConnectionCandidates = false
        directRoute = nil
        connectionCandidates = []

        guard let departureAirport,
              let arrivalAirport else {
            routeLookupCompleted = false
            return
        }

        let departureCode = departureAirport.bestCode
        let arrivalCode = arrivalAirport.bestCode

        routeLookupCompleted = false
        let resolvedDirectRoute = try? await WanderlustStaticDataStore.shared.directRoute(
            from: departureCode,
            to: arrivalCode
        )
        let resolvedConnectionCandidates: [WanderlustRouteConnectionCandidate]
        if resolvedDirectRoute == nil {
            resolvedConnectionCandidates = await SearchIndexStore.shared.connectionCandidates(
                from: departureCode,
                to: arrivalCode,
                limit: 10
            )
        } else {
            resolvedConnectionCandidates = []
        }

        guard self.departureAirport?.bestCode == departureCode,
              self.arrivalAirport?.bestCode == arrivalCode else {
            return
        }

        directRoute = resolvedDirectRoute
        connectionCandidates = resolvedConnectionCandidates
        var airlines: [Airline] = []
        for code in routeAirlineCodes {
            if let airline = try? await WanderlustStaticDataStore.shared.airline(matching: code) {
                airlines.append(airline)
            }
        }
        routeAirlineSuggestions = airlines.sorted(by: airlineSuggestionPrecedes)
        routeLookupCompleted = true
    }

    private func useConnectionCandidate(_ candidate: WanderlustRouteConnectionCandidate) {
        selectedConnectionCandidate = candidate
    }

    private func localizedAirportName(_ code: String) -> String {
        return WanderlustL10n.airportName(iataCode: code, fallback: code)
    }

    private func localizedAirlineName(_ code: String) -> String {
        return WanderlustL10n.airlineName(code: code, fallback: code)
    }

    // MARK: - Airport Search

    private func scheduleDepartureSuggestions(_ input: String? = nil) {
        departureSearchTask?.cancel()
        let query =
            (input ?? departureQuery)
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        guard query.count >= 1 else {
            departureSuggestions = []
            return
        }

        let excludedID = arrivalAirport?.id
        departureSearchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }

            let results = (try? await WanderlustStaticDataStore.shared.searchAirports(
                query: query,
                excluding: excludedID,
                limit: 4
            )) ?? []

            guard !Task.isCancelled else { return }
            departureSuggestions = results
        }
    }

    private func scheduleArrivalSuggestions(_ input: String? = nil) {
        arrivalSearchTask?.cancel()
        let query =
            (input ?? arrivalQuery)
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        guard query.count >= 1 else {
            arrivalSuggestions = []
            return
        }

        let excludedID = departureAirport?.id
        arrivalSearchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }

            let results = (try? await WanderlustStaticDataStore.shared.searchAirports(
                query: query,
                excluding: excludedID,
                limit: 4
            )) ?? []

            guard !Task.isCancelled else { return }
            arrivalSuggestions = results
        }
    }

    private func selectDepartureAirport(
        _ airport: Airport
    ) {
        departureSearchTask?.cancel()
        departureAirport = airport
        directRoute = nil
        routeAirlineSuggestions = []
        routeLookupCompleted = false
        departureQuery = ""
        departureSuggestions = []
        focusedField = nil

        if arrivalAirport?.id ==
            airport.id {
            arrivalAirport = nil
        }

        ensureArrivalAfterDeparture()
        Task { await refreshRouteContext() }
    }

    private func selectArrivalAirport(
        _ airport: Airport
    ) {
        arrivalSearchTask?.cancel()
        arrivalAirport = airport
        directRoute = nil
        routeAirlineSuggestions = []
        routeLookupCompleted = false
        arrivalQuery = ""
        arrivalSuggestions = []
        focusedField = nil

        if departureAirport?.id ==
            airport.id {
            departureAirport = nil
        }

        ensureArrivalAfterDeparture()
        Task { await refreshRouteContext() }
    }

    private func autocompleteDepartureAirport() async {
        if departureSuggestions.isEmpty {
            departureSuggestions = (try? await WanderlustStaticDataStore.shared.searchAirports(
                query: departureQuery,
                excluding: arrivalAirport?.id,
                limit: 4
            )) ?? []
        }

        if let airport = departureSuggestions.first {
            selectDepartureAirport(airport)
        }
        focusedField = nil
    }

    private func autocompleteArrivalAirport() async {
        if arrivalSuggestions.isEmpty {
            arrivalSuggestions = (try? await WanderlustStaticDataStore.shared.searchAirports(
                query: arrivalQuery,
                excluding: departureAirport?.id,
                limit: 4
            )) ?? []
        }

        if let airport = arrivalSuggestions.first {
            selectArrivalAirport(airport)
        }
        focusedField = nil
    }

    // MARK: - Existing Airport Lookup

    private func fallbackAirport(
        name: String,
        code: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String = ""
    ) -> Airport {
        Airport(
            id: [
                code,
                String(latitude),
                String(longitude)
            ]
            .joined(separator: "|"),
            ident: code,
            name:
                name.isEmpty
                ? code
                : name,
            latitude: latitude,
            longitude: longitude,
            scheduledService: true,
            gpsCode:
                code.count == 4
                ? code
                : "",
            iataCode:
                code.count == 3
                ? code
                : "",
            timezone:
                timeZoneIdentifier
        )
    }

    // MARK: - Flight Number

    private func normalizeFlightNumber() {
        var value =
            flightNumber
                .filter {
                    $0.isNumber
                }

        if let selectedAirline {
            let iata =
                selectedAirline
                    .normalizedIATACode

            if !iata.isEmpty,
               value.hasPrefix(iata) {
                value.removeFirst(
                    min(
                        iata.count,
                        value.count
                    )
                )
            }
        }

        flightNumber = String(
            value.prefix(4)
        )
    }

    // MARK: - Save

    private func saveFlight() {
        focusedField = nil

        guard let departureAirport,
              let arrivalAirport else {
            errorMessage =
                WanderlustL10n.string("Select both departure and arrival airports.", table: .airports)
            return
        }

        guard departureAirport.id !=
                arrivalAirport.id else {
            errorMessage =
                WanderlustL10n.string("Departure and arrival airports must be different.", table: .errors)
            return
        }

        guard flightArrivalAbsoluteDate > flightDepartureAbsoluteDate else {
            errorMessage =
                WanderlustL10n.string("Arrival must be after departure.", table: .errors)
            return
        }

        guard routeLookupCompleted,
              hasSelectedRoutePath else {
            errorMessage =
                WanderlustL10n.string(
                    "No route path was found for these airports.",
                    table: .trips,
                    fallback: "No route path was found for these airports."
                )
            return
        }

        guard routeSupportsSelectedAirline else {
            errorMessage =
                WanderlustL10n.string(
                    "Selected airline is not available on this route.",
                    table: .trips,
                    fallback: "Selected airline is not available on this route."
                )
            return
        }

        var flight = Flight(
            id:
                existingFlight?.id ??
                UUID(),
            direction:
                resolvedDirection,
            customTitle:
                resolvedDirection == .additional
                ? customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                : "",
            airlineName:
                selectedAirline?.name ?? "",
            airlineCode:
                selectedAirline?.bestCode ?? "",
            flightNumber:
                cleanFlightNumber,
            departureAirportName:
                departureAirport
                    .name,
            departureAirportCode:
                departureAirport
                    .bestCode,
            departureAirportID:
                departureAirport
                    .id,
            departureTimeZoneIdentifier:
                departureTimeZoneIdentifier,
            departureLatitude:
                departureAirport
                    .latitude,
            departureLongitude:
                departureAirport
                    .longitude,
            arrivalAirportName:
                arrivalAirport
                    .name,
            arrivalAirportCode:
                arrivalAirport
                    .bestCode,
            arrivalAirportID:
                arrivalAirport
                    .id,
            arrivalTimeZoneIdentifier:
                arrivalTimeZoneIdentifier,
            arrivalLatitude:
                arrivalAirport
                    .latitude,
            arrivalLongitude:
                arrivalAirport
                    .longitude,
            departureDate:
                flightDepartureAbsoluteDate,
            arrivalDate:
                flightArrivalAbsoluteDate,
            departureLocalDate:
                departureLocalDate,
            arrivalLocalDate:
                arrivalLocalDate
        )

        flight.legs = makeFlightLegs(
            departureAirport: departureAirport,
            arrivalAirport: arrivalAirport,
            airline: selectedAirline,
            flightNumber: cleanFlightNumber
        )

        if let existingFlight,
           existingFlight.effectiveLegs.count > 1,
           canPreserveExistingConnectionRoute {
            flight.legs = existingFlight.effectiveLegs
        }

        onSave(flight)
        dismiss()
    }

    // MARK: - Formatting

    private var formattedDuration: String? {
        guard flightArrivalAbsoluteDate > flightDepartureAbsoluteDate else {
            return nil
        }
        return flightDurationCalculator?.durationText
    }

    private var flightDurationCalculator: FlightDurationCalculator? {
        guard departureAirport != nil,
              arrivalAirport != nil else {
            return nil
        }

        return FlightDurationCalculator(
            departureLocalDate: departureLocalDate,
            arrivalLocalDate: arrivalLocalDate,
            departureTimeZoneIdentifier: departureTimeZoneIdentifier,
            arrivalTimeZoneIdentifier: arrivalTimeZoneIdentifier
        )
    }

    private var departureLocalDate: Date {
        departureDate
    }

    private var arrivalLocalDate: Date {
        arrivalDate
    }

    private var flightDepartureAbsoluteDate: Date {
        flightDurationCalculator?.departureAbsoluteDate ?? departureDate
    }

    private var flightArrivalAbsoluteDate: Date {
        flightDurationCalculator?.arrivalAbsoluteDate ?? arrivalDate
    }

    private func makeFlightLegs(
        departureAirport: Airport,
        arrivalAirport: Airport,
        airline: Airline?,
        flightNumber: String
    ) -> [FlightLeg] {
        let routeCodes = cleanedRouteCodes(selectedConnectionCandidate?.airportCodes ?? [
            departureAirport.bestCode,
            arrivalAirport.bestCode
        ])

        let airports = routeCodes.enumerated().map { index, code -> Airport in
            if index == 0 {
                return departureAirport
            }

            if index == routeCodes.count - 1 {
                return arrivalAirport
            }

            if let airport = airport(for: code) {
                return airport
            }

            return fallbackAirport(
                name: code,
                code: code,
                latitude: 0,
                longitude: 0
            )
        }

        guard airports.count >= 2 else { return [] }

        let absoluteDeparture = flightDepartureAbsoluteDate
        let absoluteArrival = flightArrivalAbsoluteDate
        let totalDuration = max(absoluteArrival.timeIntervalSince(absoluteDeparture), 60)
        let legCount = airports.count - 1
        let layoverDuration = legCount > 1 ? min(max(totalDuration * 0.08, 1_800), 5_400) : 0
        let flightDurationTotal = max(totalDuration - layoverDuration * Double(legCount - 1), Double(legCount) * 60)
        let segmentDuration = flightDurationTotal / Double(legCount)

        return (0..<legCount).compactMap { index in
            let departureAbsolute = absoluteDeparture
                .addingTimeInterval(Double(index) * (segmentDuration + layoverDuration))
            let arrivalAbsolute = index == legCount - 1
                ? absoluteArrival
                : departureAbsolute.addingTimeInterval(segmentDuration)
            let origin = airports[index]
            let destination = airports[index + 1]
            guard !sameAirport(origin, destination) else {
                return nil
            }
            let originTimeZone = Flight.resolvedTimeZoneIdentifier(
                storedIdentifier: origin.resolvedTimeZoneIdentifier,
                airportCode: origin.bestCode
            )
            let destinationTimeZone = Flight.resolvedTimeZoneIdentifier(
                storedIdentifier: destination.resolvedTimeZoneIdentifier,
                airportCode: destination.bestCode
            )

            return FlightLeg(
                airlineName: airline?.name ?? "",
                airlineCode: airline?.bestCode ?? "",
                flightNumber: flightNumber,
                departureAirportName: origin.name,
                departureAirportCode: origin.bestCode,
                departureAirportID: origin.id,
                departureTimeZoneIdentifier: originTimeZone,
                departureLatitude: origin.latitude,
                departureLongitude: origin.longitude,
                arrivalAirportName: destination.name,
                arrivalAirportCode: destination.bestCode,
                arrivalAirportID: destination.id,
                arrivalTimeZoneIdentifier: destinationTimeZone,
                arrivalLatitude: destination.latitude,
                arrivalLongitude: destination.longitude,
                departureLocalDate: Flight.localDisplayDate(
                    fromAbsoluteDate: departureAbsolute,
                    timeZoneIdentifier: originTimeZone
                ),
                arrivalLocalDate: Flight.localDisplayDate(
                    fromAbsoluteDate: arrivalAbsolute,
                    timeZoneIdentifier: destinationTimeZone
                )
            )
        }
    }

    private func cleanedRouteCodes(_ codes: [String]) -> [String] {
        var result: [String] = []
        for code in codes {
            let cleanedCode = code
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard !cleanedCode.isEmpty else { continue }
            if result.last != cleanedCode {
                result.append(cleanedCode)
            }
        }
        return result
    }

    private func sameAirport(_ first: Airport, _ second: Airport) -> Bool {
        let firstID = first.id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let secondID = second.id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let firstCode = first.bestCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let secondCode = second.bestCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return (!firstID.isEmpty && firstID == secondID) || (!firstCode.isEmpty && firstCode == secondCode)
    }

    private func airport(for code: String) -> Airport? {
        let cleanedCode = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !cleanedCode.isEmpty else { return nil }
        return AirportDataLoader.shared.airport(withIATACode: cleanedCode) ??
            AirportDataLoader.shared.airport(withICAOCode: cleanedCode) ??
            AirportDataLoader.shared.airport(withID: cleanedCode)
    }
}

// MARK: - Inherited Flight Value Button

private struct InheritedFlightValueButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Airline Suggestion Row

private struct AirlineSuggestionRow: View {
    let airline: Airline

    private var resolvedCountryCode: String {
        airline.normalizedCountryCode
    }

    private var localizedCountry: String {
        let countryCode = resolvedCountryCode
        if !countryCode.isEmpty {
            return WanderlustNameResolver.countryName(
                for: countryCode,
                fallback: airline.displayCountry
            )
        }

        guard !airline.displayCountry.isEmpty else { return "" }
        return WanderlustNameResolver.countryName(
            for: airline.displayCountry,
            fallback: airline.displayCountry
        )
    }

    private var airlineFlagEmoji: String {
        flagEmoji(for: resolvedCountryCode)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(airlineFlagEmoji)
                .font(.title2)
                .frame(width: 34)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    airline.displayName
                )
                .font(.headline)
                .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    if !airline
                        .normalizedIATACode
                        .isEmpty {
                        Text(
                            airline
                                .normalizedIATACode
                        )
                        .font(
                            .caption
                                .bold()
                                .monospaced()
                        )
                    }

                    if !localizedCountry.isEmpty {
                        Text(localizedCountry)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(
                systemName:
                    "plus.circle.fill"
            )
            .foregroundStyle(.blue)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Selected Airline Row

private struct SelectedAirlineRow: View {
    let airline: Airline
    let onChange: () -> Void

    private var resolvedCountryCode: String {
        airline.normalizedCountryCode
    }

    private var localizedCountry: String {
        let countryCode = resolvedCountryCode
        if !countryCode.isEmpty {
            return WanderlustNameResolver.countryName(
                for: countryCode,
                fallback: airline.displayCountry
            )
        }

        guard !airline.displayCountry.isEmpty else { return "" }
        return WanderlustNameResolver.countryName(
            for: airline.displayCountry,
            fallback: airline.displayCountry
        )
    }

    private var airlineFlagEmoji: String {
        flagEmoji(for: resolvedCountryCode)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(airlineFlagEmoji)
                .font(.title2)
                .frame(width: 34)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    airline.displayName
                )
                .font(.headline)

                HStack(spacing: 7) {
                    Text(
                        airline
                            .normalizedIATACode
                    )
                    .font(
                        .caption
                            .bold()
                            .monospaced()
                    )

                    if !localizedCountry.isEmpty {
                        Text(localizedCountry)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button(String(localized: "Change")) {
                onChange()
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

private func flagEmoji(for countryCode: String) -> String {
    let code = countryCode
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
    guard code.count == 2 else { return "🌍" }
    let scalars = code.unicodeScalars.compactMap {
        UnicodeScalar(127397 + $0.value)
    }
    guard scalars.count == 2 else { return "🌍" }
    return String(String.UnicodeScalarView(scalars))
}

// MARK: - Route Suggestions

private struct RouteAirlineSuggestionStrip: View {
    let airlines: [Airline]
    let selectedAirline: Airline?
    let onSelect: (Airline) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(airlines) { airline in
                    Button {
                        onSelect(airline)
                    } label: {
                        Label(
                            airline.displayName,
                            systemImage: selectedAirline?.id == airline.id ? "checkmark.circle.fill" : "airplane"
                        )
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct RouteConnectionCandidateCard: View {
    let candidate: WanderlustRouteConnectionCandidate
    let airportName: (String) -> String
    let airlineName: (String) -> String
    let isSelected: Bool
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(candidate.airportCodes.joined(separator: " → "))
                    .font(.headline.monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(candidate.airportCodes.enumerated()), id: \.offset) { index, code in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(index == 0 ? "•" : "↓")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(airportName(code))
                                .font(.subheadline)
                            Text(code)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !candidate.preferredAirlineCodes.isEmpty {
                LabeledContent {
                    Text(candidate.preferredAirlineCodes.map(airlineName).joined(separator: ", "))
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Text(WanderlustL10n.string("Airlines", table: .airlines, fallback: "Airlines"))
                        .font(.caption)
                }
            }

            Button {
                onUse()
            } label: {
                Label(
                    WanderlustL10n.string("Use This Route", table: .trips, fallback: "Use This Route"),
                    systemImage: "checkmark"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Airport Suggestion Row

private struct FlightAirportSuggestionRow: View {
    let airport: Airport

    private var localizedCountry: String {
        GeoJSONLoader.shared.country(withISOCode: airport.normalizedCountryCode)?.displayName
            ?? airport.normalizedCountryCode
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                HStack(alignment: .center, spacing: 7) {
                    Text(airport.flagEmoji)
                        .font(.title2)
                        .frame(width: 34)

                    Text(airport.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                airportSubtitle
                    .padding(.leading, 41)
            }

            Spacer()

            Image(
                systemName:
                    "plus.circle.fill"
            )
            .foregroundStyle(.blue)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var airportSubtitle: some View {
        HStack(spacing: 7) {
            if !airport.bestCode.isEmpty {
                Text(airport.bestCode)
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(.primary)
            }

            if !localizedCountry.isEmpty {
                Text(localizedCountry)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !airport.displayMunicipality.isEmpty {
                Text(airport.displayMunicipality)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Selected Airport Row

private struct SelectedFlightAirportRow: View {
    let airport: Airport
    let onChange: () -> Void

    private var localizedCountry: String {
        GeoJSONLoader.shared.country(withISOCode: airport.normalizedCountryCode)?.displayName
            ?? airport.normalizedCountryCode
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(airport.flagEmoji)
                .font(.title2)
                .frame(width: 34)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(airport.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                airportSubtitle
            }

            Spacer()

            Button(String(localized: "Change")) {
                onChange()
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var airportSubtitle: some View {
        HStack(spacing: 7) {
            if !airport.bestCode.isEmpty {
                Text(airport.bestCode)
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(.primary)
            }

            if !localizedCountry.isEmpty {
                Text(localizedCountry)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !airport.displayMunicipality.isEmpty {
                Text(airport.displayMunicipality)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    FlightEditorView(
        tripStartDate: Date(),
        tripEndDate:
            Date()
                .addingTimeInterval(
                    86_400 * 7
                )
    ) { flight in
        print(
            flight.displayFlightNumber
        )
    }
}
