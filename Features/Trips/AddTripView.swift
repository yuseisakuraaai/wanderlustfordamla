import SwiftUI
import CoreLocation

private struct PendingFlight: Identifiable {
    let id = UUID()
    let direction: FlightDirection
    let tripFlightGroupID: UUID?
}

private enum TripDateSelection:
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

private extension View {
    func addTripFormInputRow() -> some View {
        frame(height: 22)
            .padding(.vertical, 6)
    }
}

struct AddTripView: View {
    private enum ScrollAnchor: Hashable {
        case citySectionHeader
        case citySearch
        case notesSectionHeader
    }

    @Environment(\.dismiss) private var dismiss

    // シングルトンは View の所有物ではないので @ObservedObject を使う
    @ObservedObject private var tripStore = TripStore.shared
    private let parentTripGroupID: UUID?
    private let saveButtonTitle: String
    private let onSaved: (Trip) -> Void

    // Country
    @State private var selectedCountry: Country? = nil
    @State private var countryQuery = ""
    @State private var countrySuggestions: [Country] = []
    @State private var countrySearchTask: Task<Void, Never>? = nil
    @State private var activeCountrySearchQuery = ""

    // Cities
    @State private var selectedCities: [VisitedCity] = []
    @State private var cityQuery = ""
    @State private var citySuggestions: [WanderlustCity] = []
    @State private var citySearchTask: Task<Void, Never>? = nil
    @State private var activeCitySearchQuery = ""
    @State private var editingCity: VisitedCity?

    // Dates
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var isTripDatePickerPresented = true
    @State private var activeTripDateSelection:
        EditVisitPeriodDateSelection = .start
    @State private var tripPeriodID = UUID()
    @State private var hasSelectedTripEndDate = false

    // Flights
    @State private var selectedTransportationTypes: Set<TransportationType> = []
    @State private var selectedFlights: [Flight] = []
    @State private var tripFlightGroupIDs: [UUID] = []
    @State private var pendingFlight: PendingFlight?
    @State private var editingFlight: Flight?

    // Notes
    @State private var notes = ""
    @State private var tripTitle = ""

    // Save
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var isRestoringDraft = false
    @State private var showsDiscardDraftConfirmation = false
    @FocusState private var focusedField: AddTripField?

    private enum AddTripField {
        case country, city, notes
    }

    private static let searchDebounceDelay: Duration = .milliseconds(60)

    private static func citySearchKeyboardInset(for viewportHeight: CGFloat) -> CGFloat {
        min(max(viewportHeight * 0.28, 190), 260)
    }

    private static func notesKeyboardInset(for viewportHeight: CGFloat) -> CGFloat {
        min(max(viewportHeight * 0.22, 150), 220)
    }

    init(
        parentTripGroupID: UUID? = nil,
        saveButtonTitle: String? = nil,
        onSaved: @escaping (Trip) -> Void = { _ in }
    ) {
        self.parentTripGroupID = parentTripGroupID
        self.saveButtonTitle = saveButtonTitle ?? String(localized: "Save")
        self.onSaved = onSaved
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
                let newEndDate: Date
                if activeTripDateSelection == .start && !hasSelectedTripEndDate {
                    newEndDate = newStartDate
                } else {
                    newEndDate = max(
                        Calendar.current.startOfDay(for: newPeriod.endDate),
                        newStartDate
                    )
                }

                startDate = newStartDate
                endDate = newEndDate

                if oldStartDate != newStartDate {
                    updateCityDatesForTripStartChange(from: oldStartDate, to: newStartDate)
                }
                if oldEndDate != newEndDate {
                    updateCityDatesForTripEndChange(from: oldEndDate, to: newEndDate)
                }
                if oldStartDate != newStartDate || oldEndDate != newEndDate {
                    scheduleDraftSave()
                }
            }
        )
    }

    private func scrollFocusedField(
        _ field: AddTripField?,
        using proxy: ScrollViewProxy
    ) {
        switch field {
        case .city:
            scrollFocusedCitySearch(using: proxy)
        case .notes:
            scrollFocusedNotes(using: proxy)
        case .country, nil:
            break
        }
    }

    private func scrollFocusedCitySearch(
        using proxy: ScrollViewProxy
    ) {

        isTripDatePickerPresented = false
        scrollToCitySearch(includeSuggestions: false, using: proxy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard focusedField == .city else { return }
            scrollToCitySearch(includeSuggestions: false, using: proxy)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard focusedField == .city else { return }
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
                        countrySection
                        datesSection
                        citiesSection
                        transportationSection
                        if selectedTransportationTypes.contains(.airplane) {
                            flightsSection
                        }
                        notesSection
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
            .navigationTitle(WanderlustL10n.string("New Trip", table: .trips))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { cancelTripCreation() }
                        .tint(.blue)
                        .fontWeight(.regular)
                        .confirmationDialog(
                            WanderlustL10n.string("Discard Draft?", table: .trips, fallback: "Discard Draft?"),
                            isPresented: $showsDiscardDraftConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button(
                                WanderlustL10n.string("Discard Draft", table: .trips, fallback: "Discard Draft"),
                                role: .destructive
                            ) {
                                discardDraftAndDismiss()
                            }

                            Button(
                                WanderlustL10n.string("Keep Draft", table: .trips, fallback: "Keep Draft")
                            ) {
                                dismiss()
                            }

                            Button(String(localized: "Cancel"), role: .cancel) {}
                        } message: {
                            Text(
                                WanderlustL10n.string(
                                    "Keep this draft if you want to continue editing it later.",
                                    table: .trips,
                                    fallback: "Keep this draft if you want to continue editing it later."
                                )
                            )
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle) {
                        saveTrip()
                    }
                    .tint(.blue)
                    .fontWeight(.regular)
                    .disabled(isSaving)
                }
            }
            .sheet(item: $pendingFlight) { pending in
                AddFlightView(
                    direction: pending.direction,
                    tripStartDate: startDate,
                    tripEndDate: endDate,
                    previousFlight: latestFlight(
                        for: pending.direction,
                        groupID: pending.tripFlightGroupID
                    )
                ) { flight in
                    saveFlight(
                        flight,
                        forcedDirection: pending.direction,
                        forcedTripFlightGroupID: pending.tripFlightGroupID
                    )
                }
            }
            .sheet(item: $editingFlight) { flight in
                FlightEditorView(
                    existingFlight: flight,
                    defaultDirection: flight.direction,
                    tripStartDate: startDate,
                    tripEndDate: endDate
                ) { savedFlight in
                    saveFlight(
                        savedFlight,
                        forcedDirection: flight.direction,
                        forcedTripFlightGroupID: flight.tripFlightGroupID
                    )
                }
            }
            .sheet(item: $editingCity) { city in
                EditVisitedCitySheet(
                    city: city,
                    tripStartDate: startDate,
                    tripEndDate: endDate
                ) { updatedCity in
                    updateCity(updatedCity)
                }
            }
            .alert(
                WanderlustL10n.string("Couldn't Save Trip", table: .errors),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? WanderlustL10n.string("An unknown error occurred.", table: .errors))
            }
            .onDisappear {
                focusedField = nil
                countrySearchTask?.cancel()
                citySearchTask?.cancel()
                draftSaveTask?.cancel()
                countrySearchTask = nil
                citySearchTask = nil
                draftSaveTask = nil
            }
            .task {
                try? await WanderlustStaticDataStore.shared.warmUp()
                if parentTripGroupID == nil {
                    await checkForDraft()
                }
            }
        }
    }

    // MARK: - Country Section

    private var countrySection: some View {
        Section(String(localized: "Country")) {
            if let country = selectedCountry {
                HStack(spacing: 12) {
                    Text(country.flagEmoji)
                        .font(.headline)
                        .frame(width: 34, height: 22)

                    Text(country.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        resetSelectedCountry()
                    } label: {
                        Text(String(localized: "Change"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .addTripFormInputRow()
            } else {
                MarkedSearchTextField(
                    placeholder: WanderlustL10n.string("Search country", table: .world),
                    text: $countryQuery,
                    onInputChange: { scheduleCountrySearch(for: $0) },
                    onChange: {}
                )
                .addTripFormInputRow()

                ForEach(countrySuggestions) { country in
                    Button {
                        selectedCountry = country
                        countryQuery = ""
                        countrySuggestions = []
                        activeCountrySearchQuery = ""
                        focusedField = nil
                        Task {
                            await CityDataLoader.shared.prepareSearch(countryCode: country.isoCode)
                        }
                        scheduleDraftSave()
                    } label: {
                        HStack(spacing: 12) {
                            Text(country.flagEmoji)
                                .font(.title2)
                                .frame(width: 34)
                            Text(country.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func resetSelectedCountry() {
        selectedCountry = nil
        countryQuery = ""
        countrySuggestions = []
        activeCountrySearchQuery = ""
        selectedCities = []
        citySuggestions = []
        cityQuery = ""
        activeCitySearchQuery = ""
        scheduleDraftSave()
    }

    // MARK: - Cities Section

    private var citiesSection: some View {
        Section {
            if selectedCountry == nil {
                Text(WanderlustL10n.string("Select a country above to search cities.", table: .world))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .addTripFormInputRow()
            } else if let selectedCountry {
                TextField(
                    PluralizationFormatter.searchCity(in: selectedCountry.displayName),
                    text: $cityQuery
                )
                .focused($focusedField, equals: .city)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: cityQuery) { _, newValue in
                    scheduleCitySearch(for: newValue)
                }
                .onSubmit {
                    dismissCitySearchKeyboard()
                }
                .addTripFormInputRow()
                .id(ScrollAnchor.citySearch)

                ForEach(citySuggestions) { city in
                    Button {
                        addCity(city)
                    } label: {
                        CitySuggestionRow(
                            city: city
                        )
                    }
                    .buttonStyle(.plain)
                }

                ForEach(selectedCities) { city in
                    Button {
                        openCityEditor(city)
                    } label: {
                        EditableCityRow(
                            city: city
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            removeCity(city)
                        } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }
                        .tint(.red)

                        Button {
                            openCityEditor(city)
                        } label: {
                            Label(String(localized: "Edit"), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        } header: {
            Text(WanderlustL10n.string("Cities", table: .trips))
                .id(ScrollAnchor.citySectionHeader)
        } footer: {
            if selectedCities.isEmpty && selectedCountry != nil {
                Text(WanderlustL10n.string("Add at least one city to save the trip.", table: .trips))
            } else if !selectedCities.isEmpty {
                Text(WanderlustL10n.string("Swipe left on a city to remove it.", table: .trips))
            }
        }
    }

    // MARK: - Dates Section

    private var datesSection: some View {
        Section(WanderlustL10n.string("Dates", table: .trips)) {
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
                } onEndDateSelected: {
                    hasSelectedTripEndDate = true
                }
            }
        }
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
                Text(tripPeriodSummary)
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

    private var tripPeriodSummary: String {
        guard hasSelectedTripEndDate else {
            return WanderlustDateFormatter.date(startDate)
        }
        return WanderlustDateFormatter.dateRange(start: startDate, end: endDate)
    }

    private static var tripDatePickerBounds: ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        let lower = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? Date(timeIntervalSince1970: -2_208_988_800)
        let upper = calendar.date(from: DateComponents(year: 2100, month: 12, day: 31)) ?? Date(timeIntervalSince1970: 4_134_412_800)
        return lower...upper
    }

    // MARK: - Transportation Section

    private var transportationSection: some View {
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

    // MARK: - Flights Section

    @ViewBuilder
    private var flightsSection: some View {
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
            flightRows(
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
    private func flightRows(
        title: String,
        flights: [Flight],
        direction: FlightDirection,
        tripFlightGroupID: UUID? = nil
    ) -> some View {
        if flights.isEmpty {
            Button {
                pendingFlight = PendingFlight(direction: direction, tripFlightGroupID: tripFlightGroupID)
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
                    editingFlight = flight
                } label: {
                    SelectedFlightRow(flight: flight, showsMoveHandle: true)
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
                pendingFlight = PendingFlight(direction: direction, tripFlightGroupID: tripFlightGroupID)
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
                scheduleDraftSave()
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

    // MARK: - Notes Section

    private var notesSection: some View {
        Section {
            TextField(WanderlustL10n.string("Trip notes", table: .trips), text: $notes, axis: .vertical)
                .lineLimit(4...10)
                .focused($focusedField, equals: .notes)
                .submitLabel(.done)
                .onChange(of: notes) { scheduleDraftSave() }
                .onSubmit {
                    focusedField = nil
                }
        } header: {
            Text(WanderlustL10n.string("Notes", table: .trips))
                .id(ScrollAnchor.notesSectionHeader)
        }
    }

    private func keyboardInset(
        for field: AddTripField?,
        viewportHeight: CGFloat
    ) -> CGFloat {
        switch field {
        case .city:
            Self.citySearchKeyboardInset(for: viewportHeight)
        case .notes:
            Self.notesKeyboardInset(for: viewportHeight)
        case .country, nil:
            0
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadRequiredData() async {}

    // MARK: - Country Search

    private func updateCountrySuggestions() {
        let query = countryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        scheduleCountrySearch(for: query)
    }

    private func scheduleCountrySearch() {
        scheduleCountrySearch(for: countryQuery)
    }

    private func scheduleCountrySearch(for input: String) {
        countrySearchTask?.cancel()
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        activeCountrySearchQuery = query
        guard !query.isEmpty else {
            countrySuggestions = []
            countrySearchTask = nil
            return
        }
        countrySearchTask = Task {
            guard !Task.isCancelled else { return }
            let results: [Country]
            do {
                results = try await WanderlustStaticDataStore.shared.searchCountries(query: query, limit: 6)
            } catch {
                await GeoJSONLoader.shared.loadIfNeededAsync()
                results = await GeoJSONLoader.shared.searchCountriesOffMain(query: query, limit: 6)
            }
            await MainActor.run {
                guard !Task.isCancelled,
                      activeCountrySearchQuery == query else { return }
                countrySuggestions = results
            }
        }
    }

    // MARK: - City Search (debounced, country-scoped)

    private func uniqueCitySuggestions(_ cities: [WanderlustCity]) -> [WanderlustCity] {
        var seenIDs = Set<Int>()
        return cities.filter { city in
            seenIDs.insert(city.id).inserted
        }
    }

    private func scheduleCitySearch() {
        scheduleCitySearch(for: cityQuery)
    }

    private func scheduleCitySearch(for input: String) {
        citySearchTask?.cancel()
        let countryCode = selectedCountry?.isoCode
        let trimmedQuery = input.trimmingCharacters(in: .whitespacesAndNewlines)
        activeCitySearchQuery = trimmedQuery
        guard trimmedQuery.count >= 1 else {
            citySuggestions = []
            citySearchTask = nil
            return
        }
        citySearchTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            let results = await CitySearchService.shared.search(
                query: trimmedQuery,
                countryISO2: countryCode,
                excluding: selectedCities,
                limit: 5
            )
            guard !Task.isCancelled,
                  activeCitySearchQuery == trimmedQuery,
                  selectedCountry?.isoCode == countryCode else {
                return
            }
            citySuggestions = uniqueCitySuggestions(results)
        }
    }

    private func addCity(_ city: WanderlustCity) {
        citySearchTask?.cancel()
        citySearchTask = nil

        let country = countryName(for: city)
        let period = VisitPeriod(startDate: startDate, endDate: endDate)

        let visitedCity = VisitedCity(
            geonameID: city.id,
            name: city.localizedMunicipalityDisplayName,
            countryName: country,
            countryCode: city.normalizedCountryCode,
            latitude: city.latitude,
            longitude: city.longitude,
            arrivalDate: period.startDate,
            departureDate: period.endDate
        )

        guard !selectedCities.contains(where: {
            if let geonameID = $0.geonameID { return geonameID == city.id }
            return false
        }) else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            citySuggestions = []
            cityQuery = ""
            activeCitySearchQuery = ""
            dismissCitySearchKeyboard()
            selectedCities.append(visitedCity)
            selectedCities = selectedCities.sortedByVisitDate()
            scheduleDraftSave()
        }
    }

    private func dismissCitySearchKeyboard() {
        focusedField = nil
    }

    private func removeCity(_ city: VisitedCity) {
        selectedCities.removeAll { $0.id == city.id }
        scheduleDraftSave()
    }

    private func openCityEditor(_ city: VisitedCity) {
        focusedField = nil
        Task { @MainActor in
            await Task.yield()
            editingCity = city
        }
    }

    private func updateCity(_ updatedCity: VisitedCity) {
        guard let index = selectedCities.firstIndex(where: { $0.id == updatedCity.id }) else {
            return
        }
        selectedCities[index] = updatedCity
        selectedCities = selectedCities.sortedByVisitDate()
        scheduleDraftSave()
    }

    private func updateCityDatesForTripStartChange(from oldStartDate: Date, to newStartDate: Date) {
        let calendar = Calendar.current
        selectedCities = selectedCities.map { city in
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
        selectedCities = selectedCities.map { city in
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
        selectedCities = CityVisitDatePlanner
            .normalizedCities(
                selectedCities,
                tripStart: startDate,
                tripEnd: endDate
            )
    }

    private func latestVisitDate(for city: VisitedCity) -> Date {
        city.periods.map(\.endDate).max() ?? city.departureDate ?? .distantPast
    }

    private func countryName(for city: WanderlustCity) -> String {
        city.normalizedCountryCode.isEmpty
            ? (selectedCountry?.isoCode ?? "")
            : city.normalizedCountryCode
    }

    private func countryDisplayName(for city: WanderlustCity) -> String {
        let code = city.normalizedCountryCode
        guard !code.isEmpty else { return selectedCountry?.displayName ?? "" }
        return WanderlustNameResolver.countryName(for: code, fallback: selectedCountry?.displayName ?? code)
    }

    private func removeFlight(_ flight: Flight) {
        selectedFlights.removeAll { $0.id == flight.id }
        scheduleDraftSave()
    }

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

        selectedFlights.removeAll { $0.id == normalizedFlight.id }
        selectedFlights.append(normalizedFlight)
        selectedFlights = selectedFlights.normalizedFlightList()
        scheduleDraftSave()
    }

    private func flights(for direction: FlightDirection) -> [Flight] {
        selectedFlights
            .filter { $0.direction == direction }
    }

    private func flights(for direction: FlightDirection, groupID: UUID?) -> [Flight] {
        selectedFlights
            .filter { $0.direction == direction && $0.tripFlightGroupID == groupID }
    }

    private var visibleTripFlightGroupIDs: [UUID] {
        var ids = tripFlightGroupIDs
        for flight in selectedFlights where flight.direction == .tripOutbound || flight.direction == .tripReturn {
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
        selectedFlights.removeAll {
            ($0.direction == .tripOutbound || $0.direction == .tripReturn) &&
                $0.tripFlightGroupID == groupID
        }
        scheduleDraftSave()
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

        var remaining = selectedFlights.filter {
            guard $0.direction == direction else { return true }
            return groupID != nil && $0.tripFlightGroupID != groupID
        }
        let insertionIndex = selectedFlights.firstIndex { $0.direction.sortOrder > direction.sortOrder } ?? selectedFlights.endIndex
        let precedingCount = selectedFlights[..<insertionIndex].filter {
            guard $0.direction == direction else { return true }
            return groupID != nil && $0.tripFlightGroupID != groupID
        }.count
        remaining.insert(contentsOf: group, at: min(precedingCount, remaining.count))
        selectedFlights = remaining
        scheduleDraftSave()
    }

    private func latestFlight(for direction: FlightDirection, groupID: UUID? = nil) -> Flight? {
        let currentSegmentFlight = groupID == nil
            ? flights(for: direction).last
            : flights(for: direction, groupID: groupID).last

        return currentSegmentFlight ?? latestParentTripGroupFlight()
    }

    private func latestParentTripGroupFlight() -> Flight? {
        guard let parentTripGroupID,
              let group = tripStore.tripGroups.first(where: { $0.id == parentTripGroupID }) else {
            return nil
        }

        return tripStore.trips(in: group)
            .flatMap(\.flights)
            .sorted { $0.departureDate < $1.departureDate }
            .last
    }

    private func toggleTransportation(_ type: TransportationType) {
        if selectedTransportationTypes.contains(type) {
            selectedTransportationTypes.remove(type)
            if type == .airplane {
                selectedFlights = []
            }
        } else {
            selectedTransportationTypes.insert(type)
        }
        scheduleDraftSave()
    }

    private func validateTrip() -> [String] {
        var messages: [String] = []
        if selectedCities.isEmpty {
            messages.append(WanderlustL10n.string("Add at least one city to save the trip.", table: .trips))
        }
        if endDate < startDate {
            messages.append(
                "\(WanderlustL10n.string("End Date", table: .trips)) ≥ \(WanderlustL10n.string("Start Date", table: .trips))"
            )
        }
        if selectedTransportationTypes.contains(.airplane),
           !selectedFlights.hasValidGroupedDepartureOrder {
            messages.append(selectedFlights.departureOrderValidationMessage)
        }
        return messages
    }

    private func saveTrip() {
        guard !isSaving else { return }
        let errors = validateTrip()
        guard errors.isEmpty else {
            errorMessage = errors.joined(separator: "\n")
            return
        }
        focusedField = nil
        isSaving = true
        errorMessage = nil

        let newTrip = Trip(
            title: "",
            startDate: startDate,
            endDate: endDate,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            cities: selectedCities,
            transportationTypes: selectedTransportationTypes.sorted { $0.sortOrder < $1.sortOrder },
            flights: selectedTransportationTypes.contains(.airplane) ? selectedFlights.normalizedFlightList() : []
        )


        let wasSaved = tripStore.addTrip(newTrip, toTripGroupID: parentTripGroupID)
        isSaving = false

        if wasSaved {
            onSaved(newTrip)
            Task { try? await TripDraftStore.shared.deleteDraft() }
            dismiss()
        } else {
            errorMessage = tripStore.lastErrorMessage ?? WanderlustL10n.string("The trip could not be saved.", table: .errors)
        }
    }

    private func cancelTripCreation() {
        focusedField = nil
        if currentDraft().isMeaningful {
            showsDiscardDraftConfirmation = true
        } else {
            Task { try? await TripDraftStore.shared.deleteDraft() }
            dismiss()
        }
    }

    private func discardDraftAndDismiss() {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        Task {
            try? await TripDraftStore.shared.deleteDraft()
            await MainActor.run {
                dismiss()
            }
        }
    }

    @MainActor
    private func checkForDraft() async {
        guard let draft = try? await TripDraftStore.shared.loadDraft(),
              draft.isMeaningful else {
            return
        }
        if draft.isExpired {
            try? await TripDraftStore.shared.deleteDraft()
            return
        }
        restoreDraft(draft)
    }

    private func restoreDraft(_ draft: TripDraft) {
        isRestoringDraft = true
        tripTitle = draft.title
        startDate = draft.startDate
        endDate = max(draft.endDate, draft.startDate)
        if !draft.countryCode.isEmpty {
            selectedCountry = Country(
                iso2: WanderlustNameResolver.normalizedCountryCode(draft.countryCode),
                iso3: "",
                continent: "",
                polygonParts: []
            )
            Task {
                await CityDataLoader.shared.prepareSearch(countryCode: draft.countryCode)
            }
        }
        selectedCities = draft.cities.sortedByVisitDate()
        selectedTransportationTypes = Set(draft.transportationTypes)
        selectedFlights = draft.flights.normalizedFlightList()
        notes = draft.notes
        isRestoringDraft = false
    }

    private func scheduleDraftSave() {
        guard !isRestoringDraft else { return }
        guard parentTripGroupID == nil else { return }
        draftSaveTask?.cancel()
        let draft = currentDraft()
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if draft.isMeaningful {
                try? await TripDraftStore.shared.saveDraft(draft)
            } else {
                try? await TripDraftStore.shared.deleteDraft()
            }
        }
    }

    private func currentDraft() -> TripDraft {
        TripDraft(
            title: tripTitle,
            startDate: startDate,
            endDate: endDate,
            countryCode: selectedCountry?.isoCode ?? "",
            cities: selectedCities,
            transportationTypes: selectedTransportationTypes.sorted { $0.sortOrder < $1.sortOrder },
            flights: selectedFlights.normalizedFlightList(),
            notes: notes,
            updatedAt: Date()
        )
    }

}

// MARK: - City Suggestion Row

private struct CitySuggestionRow: View {
    let city: WanderlustCity

    var body: some View {
        let cityDisplayName = city.localizedMunicipalityDisplayName

        HStack(spacing: 12) {
            Text(city.flagEmoji)
                .font(.title2)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(cityDisplayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let prefectureName = city.japanesePrefectureName {
                    Text(prefectureName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.blue)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Selected Flight Row

private struct SelectedFlightRow: View {
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

            VStack(alignment: .leading, spacing: 5) {
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

// MARK: - Add Flight View

private struct AddFlightView: View {
    let direction: FlightDirection
    let tripStartDate: Date
    let tripEndDate: Date
    let previousFlight: Flight?
    let onSave: (Flight) -> Void

    var body: some View {
        FlightEditorView(
            defaultDirection: direction,
            tripStartDate: tripStartDate,
            tripEndDate: tripEndDate,
            previousFlight: previousFlight,
            onSave: onSave
        )
    }
}

// MARK: - Airport Rows

private struct AirportSuggestionRow: View {
    let airport: Airport

    var body: some View {
        HStack(spacing: 12) {
            Text(airport.flagEmoji).font(.title2).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(airport.displayTitle).font(.headline).foregroundStyle(.primary)
                Text(airport.displaySubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
        }
        .contentShape(Rectangle())
    }
}

private struct SelectedAirportRow: View {
    let airport: Airport

    var body: some View {
        HStack(spacing: 12) {
            Text(airport.flagEmoji).font(.title2).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(airport.displayTitle).font(.headline)
                Text(airport.displaySubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}

#Preview {
    AddTripView()
}
