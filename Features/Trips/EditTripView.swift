import SwiftUI

private enum EditTripDateSelection:
    String,
    CaseIterable,
    Identifiable
{
    case start
    case end

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start:
            return WanderlustL10n.string("Start", table: .trips)
        case .end:
            return WanderlustL10n.string("End", table: .trips)
        }
    }
}

enum EditVisitPeriodDateSelection:
    String,
    CaseIterable,
    Identifiable
{
    case start
    case end

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start:
            return WanderlustL10n.string("Start", table: .trips)
        case .end:
            return WanderlustL10n.string("End", table: .trips)
        }
    }
}

private enum EditTripFocusedField {
    case citySearch
    case notes
}

private extension View {
    func editTripFormInputRow() -> some View {
        frame(height: 22)
            .padding(.vertical, 6)
    }
}

struct EditTripView: View {
    private enum ScrollAnchor: Hashable {
        case citySectionHeader
        case citySearch
        case notesSectionHeader
    }

    let trip: Trip

    @Environment(\.dismiss)
    private var dismiss

    @FocusState
    private var focusedField: EditTripFocusedField?

    @StateObject
    private var tripStore =
        TripStore.shared

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isTripDatePickerPresented = false
    @State private var activeTripDateSelection:
        EditVisitPeriodDateSelection = .start
    @State private var tripPeriodID = UUID()
    @State private var notes: String

    @State private var cities:
        [VisitedCity]

    @State private var selectedTransportationTypes:
        Set<TransportationType>

    @State private var flights:
        [Flight]

    @State private var tripFlightGroupIDs:
        [UUID]

    @State private var cityQuery = ""

    @State private var citySuggestions:
        [WanderlustCity] = []

    @State private var citySearchTask: Task<Void, Never>?

    private static func citySearchKeyboardInset(for viewportHeight: CGFloat) -> CGFloat {
        min(max(viewportHeight * 0.28, 190), 260)
    }

    private static func notesKeyboardInset(for viewportHeight: CGFloat) -> CGFloat {
        min(max(viewportHeight * 0.22, 150), 220)
    }

    @State private var editingCity:
        VisitedCity?

    @State private var flightEditorContext:
        FlightEditorContext?

    @State private var isSaving =
        false

    @State private var errorMessage:
        String?

    init(
        trip: Trip
    ) {
        self.trip = trip

        _startDate =
            State(
                initialValue:
                    trip.startDate
            )

        _endDate =
            State(
                initialValue:
                    trip.endDate
            )

        _notes =
            State(
                initialValue:
                    trip.notes
            )

        _cities =
            State(
                initialValue:
                    Self.normalizedCitiesForEditing(
                        trip.cities
                    )
            )

        _selectedTransportationTypes =
            State(
                initialValue:
                    Set(trip.transportationTypes)
            )

        let normalizedFlights = Self.normalizedFlightsForEditing(
            trip.flights
        )

        _flights =
            State(
                initialValue:
                    normalizedFlights
            )

        _tripFlightGroupIDs =
            State(
                initialValue:
                    Self.tripFlightGroupIDs(
                        from: normalizedFlights
                    )
            )
    }

    private var canSave:
        Bool {
        !cities.isEmpty &&
        endDate >= startDate &&
        !selectedTransportationTypes.isEmpty &&
        !isSaving
    }

    private var tripPeriodBinding: Binding<VisitPeriod> {
        Binding(
            get: {
                VisitPeriod(
                    id: tripPeriodID,
                    startDate: startDate,
                    endDate: endDate
                )
            },
            set: { newPeriod in
                let oldStartDate = startDate
                let oldEndDate = endDate
                let newStartDate = Calendar.current.startOfDay(for: newPeriod.startDate)
                let newEndDate = max(
                    Calendar.current.startOfDay(for: newPeriod.endDate),
                    newStartDate
                )

                startDate = newStartDate
                endDate = newEndDate

                if oldStartDate != newStartDate {
                    updateCityDatesForTripStartChange(from: oldStartDate, to: newStartDate)
                }
                if oldEndDate != newEndDate {
                    updateCityDatesForTripEndChange(from: oldEndDate, to: newEndDate)
                }
            }
        )
    }

    private var tripCountryISO2: String? {
        let fromCurrentCities = Set(
            cities.map {
                WanderlustNameResolver.normalizedCountryCode(
                    $0.countryCode,
                    fallback: $0.countryName
                )
            }
            .filter { !$0.isEmpty }
        )
        if fromCurrentCities.count == 1 {
            return fromCurrentCities.first
        }
        return trip.countryISO2
    }

    private static func normalizedCitiesForEditing(
        _ cities: [VisitedCity]
    ) -> [VisitedCity] {
        var seenIDs: Set<UUID> = []
        return cities.map { city in
            guard seenIDs.insert(city.id).inserted else {
                var copy = VisitedCity(
                    geonameID: city.geonameID,
                    name: city.name,
                    countryName: city.countryName,
                    countryCode: city.countryCode,
                    latitude: city.latitude,
                    longitude: city.longitude,
                    notes: city.notes
                )
                copy.periods = city.periods
                return copy
            }

            return city
        }
    }

    private static func normalizedFlightsForEditing(
        _ flights: [Flight]
    ) -> [Flight] {
        let legacyGroupID = UUID()
        return flights.map { flight in
            var copy = flight
            if (copy.direction == .tripOutbound || copy.direction == .tripReturn),
               copy.tripFlightGroupID == nil {
                copy.tripFlightGroupID = legacyGroupID
            }
            return copy
        }
        .normalizedFlightList()
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

    private func scrollFocusedField(
        _ field: EditTripFocusedField?,
        using proxy: ScrollViewProxy
    ) {
        switch field {
        case .citySearch:
            scrollFocusedCitySearch(using: proxy)
        case .notes:
            scrollFocusedNotes(using: proxy)
        case nil:
            break
        }
    }

    private func scrollFocusedCitySearch(
        using proxy: ScrollViewProxy
    ) {

        isTripDatePickerPresented = false
        scrollToCitySearch(includeSuggestions: false, using: proxy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard focusedField == .citySearch else { return }
            scrollToCitySearch(includeSuggestions: false, using: proxy)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard focusedField == .citySearch else { return }
            scrollToCitySearch(includeSuggestions: false, using: proxy)
        }
    }

    private func scrollFocusedNotes(
        using proxy: ScrollViewProxy
    ) {
        isTripDatePickerPresented = false
        scrollToNotes(using: proxy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard focusedField == .notes else { return }
            scrollToNotes(using: proxy)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard focusedField == .notes else { return }
            scrollToNotes(using: proxy)
        }
    }

    private func scrollToCitySearch(
        includeSuggestions: Bool = true,
        using proxy: ScrollViewProxy
    ) {
        if includeSuggestions,
           let lastSuggestion = citySuggestions.last {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(lastSuggestion.id, anchor: .bottom)
            }
            return
        }

        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(ScrollAnchor.citySectionHeader, anchor: .top)
        }
    }

    private func scrollToNotes(
        using proxy: ScrollViewProxy
    ) {
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(ScrollAnchor.notesSectionHeader, anchor: .top)
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    Form {
                        tripInformationSection
                        citiesSection
                        transportationSection
                        if selectedTransportationTypes.contains(.airplane) {
                            flightsSection
                        }
                        notesSection
                        deleteSection
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .listSectionSpacing(.compact)
                    .onChange(of: focusedField) { _, field in
                        scrollFocusedField(field, using: proxy)
                    }
                    .safeAreaInset(edge: .bottom) {
                        Color.clear
                            .frame(
                                height: keyboardInset(
                                    for: focusedField,
                                    viewportHeight: geometry.size.height
                                )
                            )
                    }
                }
            }
            .navigationTitle(
                WanderlustL10n.string("Edit Trip", table: .trips)
            )
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                    .tint(.blue)
                    .fontWeight(.regular)
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button(String(localized: "Save")) {
                        saveTrip()
                    }
                    .tint(.blue)
                    .fontWeight(.regular)
                    .disabled(!canSave)
                }

            }
            .sheet(
                item: $editingCity
            ) { city in
                EditVisitedCitySheet(
                    city: city,
                    tripStartDate:
                        startDate,
                    tripEndDate:
                        endDate
                ) { updatedCity in
                    updateCity(
                        updatedCity
                    )
                }
            }
            .sheet(
                item:
                    $flightEditorContext
            ) { context in
                FlightEditorSheet(
                    existingFlight:
                        context.flight,
                    defaultDirection:
                        context.direction,
                    tripStartDate:
                        startDate,
                    tripEndDate:
                        endDate,
                    previousFlight:
                        context.flight == nil
                        ? latestFlight(for: context.direction, groupID: context.tripFlightGroupID)
                        : nil
                ) { savedFlight in
                    saveFlight(
                        savedFlight,
                        forcedDirection:
                            context.flight?.direction ??
                            context.direction,
                        forcedTripFlightGroupID:
                            context.flight?.tripFlightGroupID ??
                            context.tripFlightGroupID
                    )
                }
            }
            .alert(
                WanderlustL10n.string("Couldn't Save Trip", table: .errors),
                isPresented: Binding(
                    get: {
                        errorMessage != nil
                    },
                    set: { value in
                        if !value {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button(
                    String(localized: "OK"),
                    role: .cancel
                ) {}
            } message: {
                Text(
                    errorMessage ??
                    WanderlustL10n.string("An unknown error occurred.", table: .errors)
                )
            }
            .onDisappear {
                citySearchTask?.cancel()
                citySearchTask = nil
            }
        }
    }

    // MARK: - Trip Information

    private var tripInformationSection:
        some View {
        Section(
            WanderlustL10n.string("Dates", table: .trips)
        ) {
            tripPeriodSelectionRow

            if isTripDatePickerPresented {
                EditVisitPeriodPicker(
                    period: tripPeriodBinding,
                    activeSelection: $activeTripDateSelection,
                    startDateRange: Self.tripDatePickerBounds,
                    endDateRange: startDate...Self.tripDatePickerBounds.upperBound
                ) {
                } onSelectionCompleted: { selection in
                    if selection == .end {
                        isTripDatePickerPresented = false
                    }
                }
            }
        }
    }

    private static var tripDatePickerBounds: ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        let lower = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? Date(timeIntervalSince1970: -2_208_988_800)
        let upper = calendar.date(from: DateComponents(year: 2100, month: 12, day: 31)) ?? Date(timeIntervalSince1970: 4_134_412_800)
        return lower...upper
    }

    private var tripPeriodSelectionRow: some View {
        Button {
            if isTripDatePickerPresented {
                isTripDatePickerPresented = false
            } else {
                activeTripDateSelection = .start
                isTripDatePickerPresented = true
            }
        } label: {
            HStack(spacing: 12) {
                Text(WanderlustDateFormatter.dateRange(start: startDate, end: endDate))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                if isTripDatePickerPresented {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cities

    private var citiesSection:
        some View {
        Section {
            TextField(
                tripCountryISO2 == nil
                    ? WanderlustL10n.string("Select a country before adding cities.", table: .trips)
                    : WanderlustL10n.string("Search city", table: .world),
                text: $cityQuery
            )
            .focused($focusedField, equals: .citySearch)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onChange(of: cityQuery) {
                scheduleCitySuggestions()
            }
            .onSubmit {
                focusedField = nil
            }
            .disabled(tripCountryISO2 == nil)
            .editTripFormInputRow()
            .id(ScrollAnchor.citySearch)

            if tripCountryISO2 == nil {
                Text(WanderlustL10n.string("City search is available after this trip has a single destination country.", table: .world))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(
                citySuggestions
            ) { city in
                Button {
                    addCity(city)
                } label: {
                    EditCitySuggestionRow(
                        city: city
                    )
                }
                .buttonStyle(.plain)
            }

            ForEach(cities) { city in
                Button {
                    openCityEditor(city)
                } label: {
                    EditableCityRow(
                        city: city
                    )
                }
                .buttonStyle(.plain)
                .swipeActions(
                    edge: .trailing,
                    allowsFullSwipe:
                        true
                ) {
                    Button(
                        role:
                            .destructive
                        ) {
                            removeCity(city)
                        } label: {
                        Label(
                            String(localized: "Delete"),
                            systemImage:
                                "trash"
                        )
                    }
                    .tint(.red)

                    Button {
                        openCityEditor(city)
                    } label: {
                        Label(
                            String(localized: "Edit"),
                            systemImage:
                                "pencil"
                        )
                    }
                    .tint(.blue)
                }
            }
        } header: {
            Text(WanderlustL10n.string("Cities", table: .trips))
                .id(ScrollAnchor.citySectionHeader)
        } footer: {
            Text(
                WanderlustL10n.string("Tap a city to edit its visit dates and notes.", table: .trips)
            )
        }
    }

    // MARK: - Transportation

    private var transportationSection:
        some View {
        Section {
            ForEach(TransportationType.allCases) { type in
                Button {
                    toggleTransportation(type)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: type.systemImage)
                            .foregroundStyle(.blue)
                            .frame(width: 28)

                        Text(type.title)
                            .foregroundStyle(.primary)

                        Spacer()

                        if selectedTransportationTypes.contains(type) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(WanderlustL10n.string("Transportation", table: .trips))
        } footer: {
            Text(WanderlustL10n.string("Select every transportation method used on this trip. Flight details are only needed for airplane trips.", table: .errors))
        }
    }

    // MARK: - Flights

    @ViewBuilder
    private var flightsSection:
        some View {
        flightGroupSection(
            title: WanderlustL10n.string("Outbound Flight", table: .trips),
            flights: flights(for: .outbound),
            direction: .outbound,
            mainHeaderTitle: WanderlustL10n.string("Flights", table: .settings)
        )

        flightGroupSection(
            title: WanderlustL10n.string("Return Flight", table: .trips),
            flights: flights(for: .returnFlight),
            direction: .returnFlight
        )

        if hasTripFlightContent {
            flightSeparatorSection
        }

        ForEach(Array(visibleTripFlightGroupIDs.enumerated()), id: \.element) { index, groupID in
            flightGroupSection(
                title: WanderlustL10n.string("Outbound Flight", table: .trips),
                flights: flights(for: .tripOutbound, groupID: groupID),
                direction: .tripOutbound,
                tripFlightGroupID: groupID,
                mainHeaderTitle: tripFlightGroupTitle(index: index),
                mainHeaderDeleteAction: {
                    removeTripFlightGroup(groupID)
                }
            )

            flightGroupSection(
                title: WanderlustL10n.string("Return Flight", table: .trips),
                flights: flights(for: .tripReturn, groupID: groupID),
                direction: .tripReturn,
                tripFlightGroupID: groupID
            )
        }

        if !flights(for: .additional).isEmpty {
            flightGroupSection(
                title: WanderlustL10n.string("Trip Flight", table: .trips, fallback: "Trip Flight"),
                flights: flights(for: .additional),
                direction: .additional,
                showsFooter: true
            )
        }

        addTripFlightGroupSection
    }

    private var hasTripFlightContent: Bool {
        !visibleTripFlightGroupIDs.isEmpty || !flights(for: .additional).isEmpty
    }

    @ViewBuilder
    private func flightGroupSection(
        title: String,
        flights: [Flight],
        direction: FlightDirection,
        tripFlightGroupID: UUID? = nil,
        mainHeaderTitle: String? = nil,
        mainHeaderDeleteAction: (() -> Void)? = nil,
        showsSwapAction: Bool = false,
        showsFooter: Bool = false
    ) -> some View {
        Section {
            editableFlightRows(
                title: title,
                flights: flights,
                direction: direction,
                tripFlightGroupID: tripFlightGroupID
            )

        } header: {
            if let mainHeaderTitle {
                flightGroupHeader(
                    title: mainHeaderTitle,
                    deleteAction: mainHeaderDeleteAction
                )
            }
        } footer: {
            if showsFooter {
                Text(WanderlustL10n.string("Swipe left on a flight to delete it.", table: .trips, fallback: "Swipe left on a flight to delete it."))
            }
        }
    }

    private func flightGroupHeader(
        title: String,
        deleteAction: (() -> Void)?
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let deleteAction {
                Button(role: .destructive) {
                    deleteAction()
                } label: {
                    Image(systemName: "trash")
                        .imageScale(.medium)
                        .accessibilityLabel(
                            WanderlustL10n.string(
                                "Delete Trip Flights",
                                table: .trips,
                                fallback: "Delete Trip Flights"
                            )
                        )
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func editableFlightRows(
        title: String,
        flights: [Flight],
        direction: FlightDirection,
        tripFlightGroupID: UUID? = nil
    ) -> some View {
        if flights.isEmpty {
            Button {
                flightEditorContext =
                    FlightEditorContext(
                        flight: nil,
                        direction: direction,
                        tripFlightGroupID: tripFlightGroupID
                    )
            } label: {
                emptyAddFlightRow(
                    title: title,
                    addTitle: WanderlustL10n.string("Add", table: .trips)
                )
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        } else {
            ForEach(flights) { flight in
                Button {
                    flightEditorContext =
                        FlightEditorContext(
                            flight: flight,
                            direction: flight.direction,
                            tripFlightGroupID: flight.tripFlightGroupID
                        )
                } label: {
                    EditableFlightRow(flight: flight, showsMoveHandle: true)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        removeFlight(flight)
                    } label: {
                        Label(String(localized: "Delete"), systemImage: "trash")
                    }
                }
            }
            .onMove { source, destination in
                moveFlights(in: direction, groupID: tripFlightGroupID, from: source, to: destination)
            }
            .environment(\.editMode, .constant(.active))

            Button {
                flightEditorContext =
                    FlightEditorContext(
                        flight: nil,
                        direction: direction,
                        tripFlightGroupID: tripFlightGroupID
                    )
            } label: {
                smallAddFlightRow(
                    addTitle: WanderlustL10n.string("Add", table: .trips)
                )
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }

    private func emptyAddFlightRow(title: String, addTitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "airplane")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            Text(addTitle)
                .font(.body)
                .foregroundStyle(.blue)

            Image(systemName: "plus")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.blue)
                )
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private func smallAddFlightRow(addTitle: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "plus")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.blue)
                )

            Text(addTitle)
                .font(.body)
                .foregroundStyle(.blue)

            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private var addTripFlightGroupSection: some View {
        Section {
            Button {
                tripFlightGroupIDs.append(UUID())
            } label: {
                smallAddFlightRow(
                    addTitle: WanderlustL10n.string(
                        "Add Trip Flights",
                        table: .trips,
                        fallback: "Add Trip Flights"
                    )
                )
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        } header: {
            flightControlsSeparator
        } footer: {
            Text(WanderlustL10n.string("Swipe left on a flight to delete it.", table: .trips, fallback: "Swipe left on a flight to delete it."))
        }
    }

    private var flightSeparatorSection: some View {
        Section {
            EmptyView()
        } header: {
            flightControlsSeparator
        }
    }

    private var flightControlsSeparator: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
    }

    // MARK: - Notes

    private var notesSection:
        some View {
        Section {
            TextField(
                WanderlustL10n.string("Trip notes", table: .trips),
                text: $notes,
                axis: .vertical
            )
            .focused(
                $focusedField,
                equals: .notes
            )
            .lineLimit(4...10)
            .submitLabel(.done)
            .onSubmit {
                focusedField = nil
            }
        } header: {
            Text(WanderlustL10n.string("Notes", table: .trips))
                .id(ScrollAnchor.notesSectionHeader)
        }
    }

    private func keyboardInset(
        for field: EditTripFocusedField?,
        viewportHeight: CGFloat
    ) -> CGFloat {
        switch field {
        case .citySearch:
            Self.citySearchKeyboardInset(for: viewportHeight)
        case .notes:
            Self.notesKeyboardInset(for: viewportHeight)
        case nil:
            0
        }
    }

    // MARK: - Delete

    private var deleteSection:
        some View {
        Section {
            Button(
                WanderlustL10n.string("Delete Trip", table: .trips),
                role: .destructive
            ) {
                if tripStore
                    .deleteTrip(trip) {
                    dismiss()
                } else {
                    errorMessage =
                        tripStore
                            .lastErrorMessage
                }
            }
        }
    }

    // MARK: - City Search

    private func openCityEditor(_ city: VisitedCity) {
        focusedField = nil
        citySearchTask?.cancel()
        cityQuery = ""
        citySuggestions = []
        Task { @MainActor in
            await Task.yield()
            editingCity = city
        }
    }

    private func scheduleCitySuggestions() {
        citySearchTask?.cancel()
        let query = cityQuery
        let countryISO2 = tripCountryISO2
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 1 else {
            citySuggestions = []
            citySearchTask = nil
            return
        }
        citySearchTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            let results = await CitySearchService.shared.search(
                query: trimmedQuery,
                countryISO2: countryISO2,
                excluding: cities,
                limit: 5
            )
            guard !Task.isCancelled,
                  cityQuery.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery,
                  tripCountryISO2 == countryISO2 else {
                return
            }
            citySuggestions = results
        }
    }

    private func addCity(
        _ city: WanderlustCity
    ) {
        citySearchTask?.cancel()
        citySearchTask = nil

        let period = VisitPeriod(startDate: startDate, endDate: endDate)

        let newCity =
            VisitedCity(
                geonameID:
                    city.id,
                name:
                    city.localizedMunicipalityDisplayName,
                countryName:
                    countryName(
                        for: city
                    ),
                countryCode:
                    city
                        .normalizedCountryCode,
                latitude:
                    city.latitude,
                longitude:
                    city.longitude,
                arrivalDate:
                    period.startDate,
                departureDate:
                    period.endDate
            )

        guard !cities.contains(where: {
            if let geonameID = $0.geonameID { return geonameID == city.id }
            return false
        }) else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            citySuggestions = []
            cityQuery = ""
            focusedField = nil
            cities.append(newCity)
            cities = cities.sortedByVisitDate()
        }

    }

    private func updateCity(
        _ updatedCity:
            VisitedCity
    ) {
        guard let index =
                cities.firstIndex(
                    where: {
                        $0.id ==
                        updatedCity.id
                    }
                ) else {
            return
        }

        cities[index] =
            updatedCity
        cities = cities.sortedByVisitDate()
    }

    private func removeCity(
        _ city: VisitedCity
    ) {
        guard cities.count > 1 else {
            errorMessage =
                WanderlustL10n.string("A trip must contain at least one city.", table: .errors)
            return
        }

        cities.removeAll {
            $0.id == city.id
        }
    }

    private func updateCityDatesForTripStartChange(from oldStartDate: Date, to newStartDate: Date) {
        let calendar = Calendar.current
        cities = cities.map { city in
            var copy = city
            if copy.periods.isEmpty {
                copy.periods = [VisitPeriod(startDate: newStartDate, endDate: endDate)]
                return copy
            }

            copy.periods = copy.periods.map { period in
                guard calendar.isDate(period.startDate, inSameDayAs: oldStartDate) else {
                    return period
                }
                return VisitPeriod(
                    id: period.id,
                    startDate: newStartDate,
                    endDate: max(period.endDate, newStartDate)
                )
            }
            return copy
        }
        normalizeCityDatesForCurrentTrip()
    }

    private func updateCityDatesForTripEndChange(from oldEndDate: Date, to newEndDate: Date) {
        let calendar = Calendar.current
        cities = cities.map { city in
            var copy = city
            if copy.periods.isEmpty {
                copy.periods = [VisitPeriod(startDate: startDate, endDate: newEndDate)]
                return copy
            }

            copy.periods = copy.periods.map { period in
                guard calendar.isDate(period.endDate, inSameDayAs: oldEndDate) else {
                    return period
                }
                return VisitPeriod(
                    id: period.id,
                    startDate: period.startDate,
                    endDate: newEndDate
                )
            }
            return copy
        }
        normalizeCityDatesForCurrentTrip()
    }

    private func normalizeCityDatesForCurrentTrip() {
        cities = CityVisitDatePlanner
            .normalizedCities(
                cities,
                tripStart: startDate,
                tripEnd: endDate
            )
    }

    private func latestVisitDate(for city: VisitedCity) -> Date {
        city.periods.map(\.endDate).max() ?? city.departureDate ?? .distantPast
    }

    private func countryName(
        for city: WanderlustCity
    ) -> String {
        city.normalizedCountryCode.isEmpty
            ? (tripCountryISO2 ?? "")
            : city.normalizedCountryCode
    }

    // MARK: - Flights

    private func saveFlight(
        _ flight: Flight,
        forcedDirection: FlightDirection? = nil,
        forcedTripFlightGroupID: UUID? = nil
    ) {
        var normalizedFlight = flight
        if let forcedDirection {
            normalizedFlight.direction = forcedDirection
        }
        if normalizedFlight.direction == .tripOutbound || normalizedFlight.direction == .tripReturn {
            normalizedFlight.tripFlightGroupID = forcedTripFlightGroupID ?? normalizedFlight.tripFlightGroupID ?? UUID()
            if let groupID = normalizedFlight.tripFlightGroupID,
               !tripFlightGroupIDs.contains(groupID) {
                tripFlightGroupIDs.append(groupID)
            }
        } else {
            normalizedFlight.tripFlightGroupID = nil
        }
        if normalizedFlight.direction != .additional {
            normalizedFlight.customTitle = ""
        }

        if let index =
            flights.firstIndex(
                where: {
                    $0.id ==
                    normalizedFlight.id
                }
            ) {
            flights[index] =
                normalizedFlight
        } else {
            flights.append(
                normalizedFlight
            )
        }

        flights = Self.normalizedFlightsForEditing(flights)
    }

    private func removeFlight(
        _ flight: Flight
    ) {
        flights.removeAll {
            $0.id == flight.id
        }
    }

    private func flights(for direction: FlightDirection) -> [Flight] {
        flights
            .filter { $0.direction == direction }
    }

    private func flights(for direction: FlightDirection, groupID: UUID?) -> [Flight] {
        flights
            .filter { $0.direction == direction && $0.tripFlightGroupID == groupID }
    }

    private var visibleTripFlightGroupIDs: [UUID] {
        var ids = tripFlightGroupIDs
        for flight in flights where flight.direction == .tripOutbound || flight.direction == .tripReturn {
            guard let groupID = flight.tripFlightGroupID,
                  !ids.contains(groupID) else {
                continue
            }
            ids.append(groupID)
        }
        return ids
    }

    private func removeTripFlightGroup(_ groupID: UUID) {
        tripFlightGroupIDs.removeAll { $0 == groupID }
        flights.removeAll {
            ($0.direction == .tripOutbound || $0.direction == .tripReturn) &&
                $0.tripFlightGroupID == groupID
        }
    }

    private func tripFlightGroupTitle(index: Int) -> String {
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

    private func moveFlights(in direction: FlightDirection, groupID: UUID? = nil, from source: IndexSet, to destination: Int) {
        var group = groupID == nil ? flights(for: direction) : flights(for: direction, groupID: groupID)
        group.move(fromOffsets: source, toOffset: destination)

        var remaining = flights.filter {
            guard $0.direction == direction else { return true }
            return groupID != nil && $0.tripFlightGroupID != groupID
        }
        let insertionIndex = flights.firstIndex { $0.direction.sortOrder > direction.sortOrder } ?? flights.endIndex
        let precedingCount = flights[..<insertionIndex].filter {
            guard $0.direction == direction else { return true }
            return groupID != nil && $0.tripFlightGroupID != groupID
        }.count
        remaining.insert(contentsOf: group, at: min(precedingCount, remaining.count))
        flights = remaining
    }

    private func latestFlight(for direction: FlightDirection, groupID: UUID? = nil) -> Flight? {
        groupID == nil
            ? flights(for: direction).last
            : flights(for: direction, groupID: groupID).last
    }

    private func toggleTransportation(_ type: TransportationType) {
        if selectedTransportationTypes.contains(type) {
            guard selectedTransportationTypes.count > 1 else { return }
            selectedTransportationTypes.remove(type)
            if type == .airplane {
                flights = []
            }
        } else {
            selectedTransportationTypes.insert(type)
        }
    }

    // MARK: - Save Trip

    private func saveTrip() {
        focusedField = nil

        guard canSave else {
            return
        }

        if selectedTransportationTypes.contains(.airplane),
           !flights.hasValidGroupedDepartureOrder {
            errorMessage = flights.departureOrderValidationMessage
            return
        }

        isSaving = true
        errorMessage = nil

        let updatedTrip =
            Trip(
                id: trip.id,
                title: "",
                startDate:
                    startDate,
                endDate:
                    endDate,
                notes:
                    notes
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ),
                cities: cities,
                transportationTypes:
                    selectedTransportationTypes
                    .sorted { $0.sortOrder < $1.sortOrder },
                flights:
                    selectedTransportationTypes.contains(.airplane)
                    ? Self.normalizedFlightsForEditing(flights)
                    : [],
                isFavorite:
                    trip.isFavorite
            )


        let wasSaved =
            tripStore
                .updateTrip(
                    updatedTrip
                )

        isSaving = false

        if wasSaved {
            dismiss()
        } else {
            errorMessage =
                tripStore
                    .lastErrorMessage ??
                WanderlustL10n.string("The trip could not be updated.", table: .errors)
        }
    }

}

// MARK: - Flight Editor Context

private struct FlightEditorContext: Identifiable {
    let id = UUID()
    let flight: Flight?
    let direction: FlightDirection
    let tripFlightGroupID: UUID?
}

// MARK: - Edit City Suggestion Row

private struct EditCitySuggestionRow:
    View
{
    let city: WanderlustCity

    var body: some View {
        let cityDisplayName = city.localizedMunicipalityDisplayName

        HStack(spacing: 12) {
            Text(city.flagEmoji)
                .font(.title2)
                .frame(width: 34)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    cityDisplayName
                )
                .font(.headline)
                .foregroundStyle(
                    .primary
                )

                if let prefectureName = city.japanesePrefectureName {
                    Text(prefectureName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

// MARK: - Editable City Row

struct EditableCityRow:
    View
{
    let city: VisitedCity

    var body: some View {
        HStack(spacing: 12) {
            Text(
                countryFlag(
                    code:
                        city.countryCode
                )
            )
            .font(.title2)
            .frame(width: 34)

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(city.localizedName)
                    .font(.headline)

                let sorted = city.sortedPeriods
                if !sorted.isEmpty {
                    let displayed = sorted.prefix(2)
                    ForEach(Array(displayed.enumerated()), id: \.offset) { _, period in
                        Text(WanderlustDateFormatter.dateRange(start: period.startDate, end: period.endDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if sorted.count > 2 {
                        Text(String(format: String(localized: "ほか%d件"), sorted.count - 2))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption)
            .foregroundStyle(
                .tertiary
            )
        }
        .contentShape(Rectangle())
    }

    private func countryFlag(
        code: String
    ) -> String {
        let cleaned =
            code
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .uppercased()

        guard cleaned.count == 2 else {
            return "🌍"
        }

        return cleaned
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

// MARK: - Edit Visited City Sheet

struct EditVisitedCitySheet:
    View
{
    let city: VisitedCity
    let tripStartDate: Date
    let tripEndDate: Date
    let onSave:
        (VisitedCity) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @FocusState
    private var isNotesFocused: Bool

    @State private var periods: [VisitPeriod] = []
    @State private var selectedPeriodID: UUID?
    @State private var activePeriodDateSelection:
        EditVisitPeriodDateSelection = .start

    @State private var notes = ""
    @State private var validationMessage: String?
    @State private var didLoadInitialState = false

    init(
        city: VisitedCity,
        tripStartDate: Date,
        tripEndDate: Date,
        onSave:
            @escaping
            (VisitedCity) -> Void
    ) {
        self.city = city
        self.tripStartDate =
            tripStartDate
        self.tripEndDate =
            tripEndDate
        self.onSave =
            onSave

    }

    var body: some View {
        NavigationStack {
            Form {
                visitDatesSection

                Section(WanderlustL10n.string("Notes", table: .trips)) {
                    TextField(
                        WanderlustL10n.string("City notes", table: .trips),
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                    .focused($isNotesFocused)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(
                city.localizedName
            )
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                    .tint(.blue)
                    .fontWeight(.regular)
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button(String(localized: "Save")) {
                        isNotesFocused = false

                        guard validatePeriods() else {
                            return
                        }
                        var updatedCity =
                            city

                        updatedCity.periods =
                            periods
                            .map {
                                CityVisitDatePlanner.normalizedPeriod(
                                    $0,
                                    tripStart: effectiveTripStartDate,
                                    tripEnd: effectiveTripEndDate
                                )
                            }
                            .sorted { $0.startDate < $1.startDate }

                        updatedCity.notes =
                            notes
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )

                        onSave(
                            updatedCity
                        )

                        dismiss()
                    }
                    .tint(.blue)
                    .fontWeight(.regular)
                }

                ToolbarItemGroup(
                    placement: .keyboard
                ) {
                    Spacer()

                    Button(String(localized: "Done")) {
                        isNotesFocused = false
                    }
                }
            }
            .onAppear {
                loadInitialStateIfNeeded()
            }
        }
    }

    private var visitDatesSection: some View {
        Section {
            ForEach(sortedPeriods) { period in
                visitPeriodCard(period)

                if selectedPeriodID == period.id,
                   let selectedPeriod = binding(for: period.id) {
                    selectedPeriodCalendarCard(for: period, binding: selectedPeriod)
                }
            }

            if canAddPeriod {
                Button {
                    addPeriod()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.subheadline)
                            .imageScale(.medium)

                        Text(WanderlustL10n.string("Add Visit Period", table: .trips))
                            .font(.subheadline)
                    }
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            if !canAddPeriod {
                Text(
                    WanderlustL10n.string(
                        "All trip dates are already covered.",
                        table: .trips,
                        fallback: "All trip dates are already covered."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } header: {
            Text(WanderlustL10n.string("Visit Dates", table: .trips))
        } footer: {
            if periods.count > 1 {
                Text(WanderlustL10n.string("Swipe left on a visit period to delete it.", table: .trips))
            }
        }
    }

    private var sortedPeriods: [VisitPeriod] {
        periods.sorted { first, second in
            if first.startDate != second.startDate {
                return first.startDate < second.startDate
            }
            return first.id.uuidString < second.id.uuidString
        }
    }

    private func visitPeriodCard(_ period: VisitPeriod) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if sortedPeriods.count > 1 {
                Text(visitPeriodTitle(for: period))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            periodSelectionRow(
                period,
                number: periodNumber(for: period)
            )
        }
    }

    private func selectedPeriodCalendarCard(
        for period: VisitPeriod,
        binding selectedPeriod: Binding<VisitPeriod>
    ) -> some View {
        selectedPeriodPicker(for: period, binding: selectedPeriod)
    }

    @ViewBuilder
    private func selectedPeriodPicker(
        for period: VisitPeriod,
        binding selectedPeriod: Binding<VisitPeriod>
    ) -> some View {
        let allowedStartDate = allowedStartDate(for: period)
        let allowedEndDate = allowedEndDate(for: period)
        let startDateRange = allowedStartDate...min(allowedEndDate, period.endDate)
        let endDateRange = max(period.startDate, allowedStartDate)...allowedEndDate

        if startDateRange.lowerBound <= startDateRange.upperBound,
           endDateRange.lowerBound <= endDateRange.upperBound {
            EditVisitPeriodPicker(
                period: selectedPeriod,
                activeSelection: $activePeriodDateSelection,
                startDateRange: startDateRange,
                endDateRange: endDateRange
            ) {
                validationMessage = nil
            } onSelectionCompleted: { selection in
                if selection == .end, periods.count > 1 {
                    self.selectedPeriodID = nil
                }
            }
        } else {
            Text(
                WanderlustL10n.string(
                    "Visit periods cannot overlap.",
                    table: .errors,
                    fallback: "Visit periods cannot overlap."
                )
            )
            .font(.caption)
            .foregroundStyle(.red)
        }
    }

    private var effectiveTripStartDate: Date {
        countryVisitDateRange.lowerBound
    }

    private var effectiveTripEndDate: Date {
        countryVisitDateRange.upperBound
    }

    private var countryVisitDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(tripStartDate, tripEndDate))
        let end = calendar.startOfDay(for: max(tripStartDate, tripEndDate))
        return start...end
    }

    private var canAddPeriod: Bool {
        nextAvailablePeriodStartDate != nil
    }

    private var nextAvailablePeriodStartDate: Date? {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: effectiveTripEndDate)
        let normalizedPeriods = periods.map {
            CityVisitDatePlanner.normalizedPeriod(
                $0,
                tripStart: effectiveTripStartDate,
                tripEnd: effectiveTripEndDate
            )
        }
        let sortedPeriods = normalizedPeriods.sorted { $0.startDate < $1.startDate }

        guard let lastPeriod = sortedPeriods.last else {
            return calendar.startOfDay(for: effectiveTripStartDate)
        }

        guard let candidate = calendar.date(byAdding: .day, value: 1, to: lastPeriod.endDate) else {
            return nil
        }
        return candidate <= end ? candidate : nil
    }

    private var selectedPeriod: Binding<VisitPeriod>? {
        guard let selectedPeriodID,
              let index = periods.firstIndex(where: { $0.id == selectedPeriodID }) else {
            guard let firstIndex = periods.indices.first else {
                return nil
            }
            return $periods[firstIndex]
        }
        return $periods[index]
    }

    @ViewBuilder
    private func periodSelectionRow(
        _ period: VisitPeriod,
        number: Int
    ) -> some View {
        let isSelected =
            selectedPeriodID == period.id

        Button {
            if isSelected {
                selectedPeriodID = nil
            } else {
                selectedPeriodID = period.id
                activePeriodDateSelection = .start
            }
        } label: {
            HStack(spacing: 12) {
                Text(WanderlustDateFormatter.dateRange(start: period.startDate, end: period.endDate))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            if periods.count > 1 {
                Button(role: .destructive) {
                    removePeriod(period)
                } label: {
                    Label(String(localized: "Delete"), systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }

    private func periodNumber(for period: VisitPeriod) -> Int {
        guard let index = sortedPeriods.firstIndex(where: { $0.id == period.id }) else {
            return 1
        }
        return sortedPeriods.distance(from: sortedPeriods.startIndex, to: index) + 1
    }

    private func visitPeriodTitle(for period: VisitPeriod) -> String {
        let number = periodNumber(for: period)
        return String(
            format: WanderlustL10n.string(
                "Visit Period %d",
                table: .trips,
                fallback: "訪問期間%d"
            ),
            number
        )
    }

    private func binding(for periodID: UUID) -> Binding<VisitPeriod>? {
        guard let index = periods.firstIndex(where: { $0.id == periodID }) else {
            return nil
        }
        return $periods[index]
    }

    private func allowedStartDate(for period: VisitPeriod) -> Date {
        let calendar = Calendar.current
        let effectiveStart = calendar.startOfDay(for: effectiveTripStartDate)
        let effectiveEnd = calendar.startOfDay(for: effectiveTripEndDate)
        guard let previous = adjacentPeriods(for: period).previous,
              let nextDate = calendar.date(
                  byAdding: .day,
                  value: 1,
                  to: calendar.startOfDay(for: previous.endDate)
              ) else {
            return effectiveStart
        }
        return min(max(nextDate, effectiveStart), effectiveEnd)
    }

    private func allowedEndDate(for period: VisitPeriod) -> Date {
        let calendar = Calendar.current
        let effectiveStart = calendar.startOfDay(for: effectiveTripStartDate)
        let effectiveEnd = calendar.startOfDay(for: effectiveTripEndDate)
        guard let next = adjacentPeriods(for: period).next,
              let previousDate = calendar.date(
                  byAdding: .day,
                  value: -1,
                  to: calendar.startOfDay(for: next.startDate)
              ) else {
            return effectiveEnd
        }
        return max(min(previousDate, effectiveEnd), effectiveStart)
    }

    private func adjacentPeriods(for period: VisitPeriod) -> (previous: VisitPeriod?, next: VisitPeriod?) {
        let sorted = periods.sorted { first, second in
            if first.startDate != second.startDate {
                return first.startDate < second.startDate
            }
            return first.id.uuidString < second.id.uuidString
        }
        guard let index = sorted.firstIndex(where: { $0.id == period.id }) else {
            return (nil, nil)
        }
        let previous = index > sorted.startIndex ? sorted[sorted.index(before: index)] : nil
        let nextIndex = sorted.index(after: index)
        let next = nextIndex < sorted.endIndex ? sorted[nextIndex] : nil
        return (previous, next)
    }

    private static func normalizedInitialPeriods(
        for city: VisitedCity,
        tripStartDate: Date,
        tripEndDate: Date
    ) -> [VisitPeriod] {
        let effectiveStart = min(tripStartDate, tripEndDate)
        let effectiveEnd = max(tripStartDate, tripEndDate)
        let sourcePeriods = city.periods.isEmpty
            ? [VisitPeriod(startDate: effectiveStart, endDate: effectiveStart)]
            : city.sortedPeriods

        var seenIDs: Set<UUID> = []
        return sourcePeriods
            .map {
                let normalized = CityVisitDatePlanner.normalizedPeriod(
                    $0,
                    tripStart: effectiveStart,
                    tripEnd: effectiveEnd
                )
                guard seenIDs.insert(normalized.id).inserted else {
                    return VisitPeriod(
                        startDate: normalized.startDate,
                        endDate: normalized.endDate
                    )
                }
                return normalized
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private func addPeriod() {
        guard let startDate = nextAvailablePeriodStartDate else {
            validationMessage = WanderlustL10n.string(
                "Visit periods cannot overlap.",
                table: .errors,
                fallback: "Visit periods cannot overlap."
            )
            return
        }
        let period = VisitPeriod(startDate: startDate, endDate: startDate)
        periods.append(period)
        selectedPeriodID = period.id
        activePeriodDateSelection = .start
        validationMessage = nil
    }

    private func removePeriod(_ period: VisitPeriod) {
        periods.removeAll { $0.id == period.id }
        if selectedPeriodID == period.id {
            selectedPeriodID = nil
            activePeriodDateSelection = .start
        }
        validationMessage = nil
    }

    private func loadInitialStateIfNeeded() {
        guard !didLoadInitialState else {
            return
        }
        periods = Self.normalizedInitialPeriods(
            for: city,
            tripStartDate: tripStartDate,
            tripEndDate: tripEndDate
        )
        selectedPeriodID = periods.first?.id
        activePeriodDateSelection = .start
        notes = city.notes
        validationMessage = nil
        didLoadInitialState = true
    }

    private func validatePeriods() -> Bool {
        let normalized = periods.map {
            CityVisitDatePlanner.normalizedPeriod(
                $0,
                tripStart: tripStartDate,
                tripEnd: tripEndDate
            )
        }

        if normalized.contains(where: { $0.endDate < $0.startDate }) {
            validationMessage = WanderlustL10n.string("End Date must be after Start Date.", table: .errors)
            return false
        }

        let sorted = normalized.sorted { $0.startDate < $1.startDate }
        for index in sorted.indices.dropFirst() {
            let previous = sorted[sorted.index(before: index)]
            let current = sorted[index]
            if current.startDate <= previous.endDate {
                validationMessage = WanderlustL10n.string(
                    "Visit periods cannot overlap.",
                    table: .errors,
                    fallback: "Visit periods cannot overlap."
                )
                return false
            }
        }

        validationMessage = nil
        periods = sorted
        return true
    }
}

struct EditVisitPeriodPicker: View {
    @Binding var period: VisitPeriod
    @Binding var activeSelection: EditVisitPeriodDateSelection
    let startDateRange: ClosedRange<Date>
    let endDateRange: ClosedRange<Date>
    let onDateChange: () -> Void
    var onSelectionCompleted: (EditVisitPeriodDateSelection) -> Void = { _ in }
    var onEndDateSelected: () -> Void = {}

    @State private var datePickerRefreshID = UUID()

    private var activeSelectionBinding: Binding<EditVisitPeriodDateSelection> {
        Binding(
            get: {
                activeSelection
            },
            set: { newSelection in
                guard activeSelection != newSelection else {
                    return
                }

                if activeSelection == .start, newSelection == .end {
                    ensureEndDateAllowsStartDate()
                }
                activeSelection = newSelection
                datePickerRefreshID = UUID()
            }
        )
    }

    private var selectedDate: Binding<Date> {
        Binding(
            get: {
                let range = selectedRange
                switch activeSelection {
                case .start:
                    return clamped(period.startDate, lower: range.lowerBound, upper: range.upperBound)
                case .end:
                    return clamped(period.endDate, lower: range.lowerBound, upper: range.upperBound)
                }
            },
            set: { newValue in
                let previousEndDate = period.endDate
                switch activeSelection {
                case .start:
                    let start = clamped(
                        newValue,
                        lower: startDateRange.lowerBound,
                        upper: startDateRange.upperBound
                    )
                    period.startDate = start
                    period.endDate = adjustedEndDate(for: start, currentEndDate: period.endDate)
                case .end:
                    period.endDate = clamped(
                        newValue,
                        lower: endDateRange.lowerBound,
                        upper: endDateRange.upperBound
                    )
                    onEndDateSelected()
                    if shouldCompleteEndSelection(from: previousEndDate, to: period.endDate) {
                        onSelectionCompleted(.end)
                    }
                }
                onDateChange()
            }
        )
    }

    private var selectedRange: ClosedRange<Date> {
        switch activeSelection {
        case .start:
            return normalizedRange(lower: startDateRange.lowerBound, upper: startDateRange.upperBound)
        case .end:
            return normalizedRange(lower: endDateRange.lowerBound, upper: endDateRange.upperBound)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(
                WanderlustL10n.string("Visit Dates", table: .trips),
                selection: activeSelectionBinding
            ) {
                ForEach(EditVisitPeriodDateSelection.allCases) { selection in
                    Text(selection.title)
                        .tag(selection)
                }
            }
            .pickerStyle(.segmented)

            DatePicker(
                activeSelection.title,
                selection: selectedDate,
                in: selectedRange,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .id(datePickerRefreshID)
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
    }

    private func ensureEndDateAllowsStartDate() {
        let adjustedEndDate = adjustedEndDate(for: period.startDate, currentEndDate: period.endDate)
        if period.endDate != adjustedEndDate {
            period.endDate = adjustedEndDate
            onDateChange()
        }
    }

    private func adjustedEndDate(for startDate: Date, currentEndDate: Date) -> Date {
        let start = Calendar.current.startOfDay(for: startDate)
        if currentEndDate < start || isEndDateTooFarFromStart(start, currentEndDate: currentEndDate) {
            return clamped(
                start,
                lower: endDateRange.lowerBound,
                upper: endDateRange.upperBound
            )
        }

        return clamped(
            currentEndDate,
            lower: start,
            upper: endDateRange.upperBound
        )
    }

    private func isEndDateTooFarFromStart(_ startDate: Date, currentEndDate: Date) -> Bool {
        guard let resetThreshold = Calendar.current.date(
            byAdding: .month,
            value: 2,
            to: startDate
        ) else {
            return false
        }
        return currentEndDate >= resetThreshold
    }

    private func shouldCompleteEndSelection(from oldDate: Date, to newDate: Date) -> Bool {
        let calendar = Calendar.current
        let oldComponents = calendar.dateComponents([.year, .month, .day], from: oldDate)
        let newComponents = calendar.dateComponents([.year, .month, .day], from: newDate)
        return oldComponents.year == newComponents.year &&
            oldComponents.month == newComponents.month &&
            oldComponents.day != newComponents.day
    }

    private func normalizedRange(lower: Date, upper: Date) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let lowerDay = calendar.startOfDay(for: lower)
        let upperDay = calendar.startOfDay(for: upper)
        return min(lowerDay, upperDay)...max(lowerDay, upperDay)
    }

    private func clamped(
        _ date: Date,
        lower: Date,
        upper: Date
    ) -> Date {
        let range = normalizedRange(lower: lower, upper: upper)
        let day = Calendar.current.startOfDay(for: date)
        return min(max(day, range.lowerBound), range.upperBound)
    }
}

// MARK: - Editable Flight Row

private struct EditableFlightRow:
    View
{
    let flight: Flight
    var showsMoveHandle = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsMoveHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, alignment: .center)
            }

            Image(systemName: "airplane")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 22, height: 46, alignment: .center)

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text(flight.directionTitle)
                    .font(.headline)

                if !flightSummary.isEmpty {
                    Text(flightSummary)
                        .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(flight.routeTitle)
                .font(.headline.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minHeight: 46, alignment: .center)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 12, height: 46, alignment: .center)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private var flightSummary: String {
        [
            flight.displayFlightNumber.isEmpty ? nil : flight.displayFlightNumber,
            flight.durationText
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

// MARK: - Flight Editor Sheet

private struct FlightEditorSheet: View {
    let existingFlight: Flight?
    let defaultDirection: FlightDirection
    let tripStartDate: Date
    let tripEndDate: Date
    let previousFlight: Flight?
    let onSave: (Flight) -> Void

    var body: some View {
        FlightEditorView(
            existingFlight: existingFlight,
            defaultDirection: defaultDirection,
            tripStartDate: tripStartDate,
            tripEndDate: tripEndDate,
            previousFlight: previousFlight,
            onSave: onSave
        )
    }
}

// MARK: - Flight Airport Row

private struct FlightAirportRow: View {
    let airport: Airport

    var body: some View {
        HStack(spacing: 12) {
            Text(airport.flagEmoji)
                .font(.title2)
                .frame(width: 34)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(airport.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(airport.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    EditTripView(
        trip: Trip(
            title: "Europe Trip",
            startDate: Date(),
            endDate: Date().addingTimeInterval(86_400 * 7),
            notes: "",
            cities: [
                VisitedCity(
                    geonameID: nil,
                    name: "Paris",
                    countryName: "France",
                    countryCode: "FR",
                    latitude: 48.8566,
                    longitude: 2.3522,
                    arrivalDate: nil,
                    departureDate: nil,
                    notes: ""
                )
            ],
            flights: []
        )
    )
}
