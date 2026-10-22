import SwiftUI
import Foundation
import CoreLocation
import UserNotifications
import UIKit
import Combine

private enum PostOnboardingPermissionStep {
    case none
    case location
    case notifications
}

private final class PostOnboardingLocationPermissionCoordinator:
    NSObject,
    ObservableObject,
    CLLocationManagerDelegate
{
    private let manager = CLLocationManager()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestWhenInUse(completion: @escaping () -> Void) {
        self.completion = completion
        guard manager.authorizationStatus == .notDetermined else {
            completion()
            self.completion = nil
            return
        }
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else {
            return
        }
        completion?()
        completion = nil
    }
}

struct ContentView: View {
    // シングルトンは View の所有物ではないので @ObservedObject を使う
    @ObservedObject private var tripStore = TripStore.shared

    @State private var selectedTab = 0
    @State private var passportResetToCoverToken = 0
    @State private var showStartJourney = false
    @State private var showSearch = false

    @State private var worldMapMode: WorldMapMode = .countries

    @State private var selectedCountry: Country?
    @State private var focusedCountry: Country?
    @State private var focusRequestID = UUID()
    @State private var selectedCity: VisitedCity?
    @State private var hasWorldMapRendered = false
    @State private var didResetInitialTransientState = false
    @State private var postOnboardingPermissionStep: PostOnboardingPermissionStep = .none
    @State private var permissionFlowTask: Task<Void, Never>?
    @StateObject private var locationPermissionCoordinator = PostOnboardingLocationPermissionCoordinator()

    @AppStorage("atlas.username")
    private var username = ""

    @AppStorage("atlas.email")
    private var email = ""

    @AppStorage("atlas.homeCountry")
    private var homeCountry = ""

    @AppStorage("atlas.appearance")
    private var appearance = WanderlustAppearance.system.rawValue

    @AppStorage("atlas.homeCountryHighlight")
    private var homeCountryHighlight = true

    @AppStorage("atlas.postOnboardingPermissionsCompleted")
    private var postOnboardingPermissionsCompleted = false

    private var selectedColorScheme: ColorScheme? {
        WanderlustAppearance(rawValue: appearance)?.colorScheme
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(
                WanderlustL10n.string("World", table: .world),
                systemImage: "globe.americas.fill",
                value: 0
            ) {
                worldTab
            }

            Tab(
                WanderlustL10n.string("Trips", table: .trips),
                systemImage: "suitcase.fill",
                value: 1
            ) {
                tripsTab
            }

            Tab(
                WanderlustL10n.string("Passport", table: .passport),
                systemImage: "book.closed.fill",
                value: 2
            ) {
                passportTab
            }

            Tab(
                WanderlustL10n.string("Statistics", table: .statistics),
                systemImage: "chart.bar.fill",
                value: 3
            ) {
                statisticsTab
            }

            Tab(
                WanderlustL10n.string("Settings", table: .settings),
                systemImage: "gearshape.fill",
                value: 4
            ) {
                settingsTab
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.blue)
        .preferredColorScheme(selectedColorScheme)
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 2 {
                passportResetToCoverToken += 1
            }
        }
        .onAppear {
            #if DEBUG
            let interactionStart = CFAbsoluteTimeGetCurrent()
            #endif
            resetTransientNavigationStateOnFreshLaunch()
            #if DEBUG
            WanderlustDiagnostics.info(String(format: "content_interactive %.1fms", (CFAbsoluteTimeGetCurrent() - interactionStart) * 1000), category: .performance)
            #endif
        }
        .sheet(isPresented: $showStartJourney) {
            StartJourneyView(tripStore: tripStore)
        }
        .sheet(isPresented: $showSearch) {
            SearchView(tripStore: tripStore) { country in
                worldMapMode = .countries
                focusedCountry = country
                focusRequestID = UUID()
                showSearch = false
            }
        }
        .sheet(item: $selectedCountry) { country in
            CountryDetailSheet(
                country: country,
                tripStore: tripStore
            )
            .presentationDetents([
                .medium,
                .large
            ])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedCity) { city in
            CityDetailSheet(
                city: city,
                tripStore: tripStore
            )
            .presentationDetents([
                .medium,
                .large
            ])
            .presentationDragIndicator(.visible)
        }
        .alert(
            "Wanderlust",
            isPresented: Binding(
                get: {
                    tripStore.lastErrorMessage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        tripStore.clearError()
                    }
                }
            )
        ) {
            Button(
                String(localized: "OK"),
                role: .cancel
            ) {
                tripStore.clearError()
            }
        } message: {
            Text(
                tripStore.lastErrorMessage ??
                WanderlustL10n.string("An unknown error occurred.", table: .errors)
            )
        }
        .sheet(
            isPresented: Binding(
                get: { postOnboardingPermissionStep == .location },
                set: { isPresented in
                    if !isPresented {
                        advanceFromLocationPermission()
                    }
                }
            )
        ) {
            PostOnboardingLocationPermissionView(
                authorizationStatus: CLLocationManager().authorizationStatus,
                onAllow: {
                    locationPermissionCoordinator.requestWhenInUse {
                        advanceFromLocationPermission()
                    }
                },
                onOpenSettings: {
                    openAppSettings()
                },
                onContinue: {
                    advanceFromLocationPermission()
                }
            )
            .interactiveDismissDisabled()
        }
        .sheet(
            isPresented: Binding(
                get: { postOnboardingPermissionStep == .notifications },
                set: { isPresented in
                    if !isPresented {
                        completePostOnboardingPermissionFlow()
                    }
                }
            )
        ) {
            PostOnboardingNotificationPermissionView(
                onAllow: {
                    Task {
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(
                            options: [.alert, .badge, .sound]
                        )
                        await MainActor.run {
                            completePostOnboardingPermissionFlow()
                        }
                    }
                },
                onOpenSettings: {
                    openAppSettings()
                },
                onContinue: {
                    completePostOnboardingPermissionFlow()
                }
            )
            .interactiveDismissDisabled()
        }
    }

    private func resetTransientNavigationStateOnFreshLaunch() {
        guard !didResetInitialTransientState else { return }
        didResetInitialTransientState = true
        selectedTab = 0
        showStartJourney = false
        showSearch = false
        selectedCountry = nil
        focusedCountry = nil
        selectedCity = nil
        worldMapMode = .countries
        hasWorldMapRendered = false
        MapCameraMemory.lastPosition = nil
        MapCameraMemory.didCenterOnLaunch = false
        MapCameraMemory.shouldApplyPendingInitialLocation = false
        MapCameraMemory.activeSearchFocusRequestID = nil
    }

    // MARK: - World

    private var worldTab: some View {
        NavigationStack {
            ZStack {
                MapView(
                    trips: tripStore.trips,
                    homeCountry: cleanHomeCountry,
                    mode: worldMapMode,
                    focusedCountry: focusedCountry,
                    focusRequestID: focusRequestID,
                    showHomeHighlight: homeCountryHighlight,
                    onCountryTap: { country in
                        selectedCountry = country
                    },
                    onMapReady: {
                        handleWorldMapReady()
                    }
                )

                VStack {
                    HStack(spacing: 12) {
                        WorldMapModeSwitch(selection: $worldMapMode)
                            .frame(maxWidth: 240)

                        Spacer()

                        if worldMapMode == .countries {
                            Button {
                                showSearch = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.blue)
                                    .frame(width: 44, height: 44)
                                    .wanderlustGlassSurface(
                                        radius: WanderlustRadius.capsule,
                                        isInteractive: true
                                    )
                                    .shadow(radius: 4)
                            }
                            .accessibilityLabel(String(localized: "Search"))
                            .transition(.scale.combined(with: .opacity))
                        }

                        Button {
                            showStartJourney = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                                .wanderlustGlassSurface(
                                    radius: WanderlustRadius.capsule,
                                    isInteractive: true
                                )
                                .shadow(radius: 4)
                        }
                        .accessibilityLabel(WanderlustL10n.string("Start Journey", table: .trips, fallback: "Start Journey"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)

                    Spacer()
                }
            }
            .toolbar(
                .hidden,
                for: .navigationBar
            )
        }
    }

    // MARK: - Trips

    private var tripsTab: some View {
        NavigationStack {
            TripsView(tripStore: tripStore)
        }
    }

    // MARK: - Passport

    private var passportTab: some View {
        NavigationStack {
            PassportView(
                tripStore: tripStore,
                resetToCoverToken: passportResetToCoverToken
            )
        }
    }

    // MARK: - Statistics

    private var statisticsTab: some View {
        NavigationStack {
            StatisticsView(tripStore: tripStore)
        }
    }

    // MARK: - Settings

    private var settingsTab: some View {
        NavigationStack {
            SettingsView()
        }
    }

    // MARK: - Computed Data

    private var cleanHomeCountry: String {
        let cleaned =
            homeCountry.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            return ""
        }

        if let country =
            GeoJSONLoader.shared.country(withISOCode: cleaned) ??
            GeoJSONLoader.shared.country(named: cleaned) {
            return country.isoCode
        }

        return cleaned
    }

    // MARK: - Helpers

    private func handleWorldMapReady() {
        guard !hasWorldMapRendered else { return }
        hasWorldMapRendered = true
        permissionFlowTask?.cancel()
        permissionFlowTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run {
                startPostOnboardingPermissionFlowIfNeeded()
            }
        }
    }

    private func startPostOnboardingPermissionFlowIfNeeded() {
        guard hasWorldMapRendered,
              !postOnboardingPermissionsCompleted,
              postOnboardingPermissionStep == .none
        else {
            return
        }

        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            advanceFromLocationPermission()
        case .notDetermined, .denied, .restricted:
            postOnboardingPermissionStep = .location
        @unknown default:
            advanceFromLocationPermission()
        }
    }

    private func advanceFromLocationPermission() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    completePostOnboardingPermissionFlow()
                case .notDetermined, .denied:
                    postOnboardingPermissionStep = .notifications
                @unknown default:
                    completePostOnboardingPermissionFlow()
                }
            }
        }
    }

    private func completePostOnboardingPermissionFlow() {
        postOnboardingPermissionStep = .none
        postOnboardingPermissionsCompleted = true
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

// MARK: - Post Onboarding Permissions

private struct PostOnboardingLocationPermissionView: View {
    let authorizationStatus: CLAuthorizationStatus
    let onAllow: () -> Void
    let onOpenSettings: () -> Void
    let onContinue: () -> Void

    private var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    var body: some View {
        PermissionPromptView(
            icon: isDenied ? "location.slash.fill" : "location.fill",
            color: .blue,
            title: isDenied
                ? WanderlustL10n.string("Location Access Is Off", table: .errors)
                : WanderlustL10n.string("Enable Location", table: .settings),
            message: isDenied
                ? WanderlustL10n.string("Wanderlust can continue without location access. You can enable it later in iPhone Settings.", table: .settings)
                : WanderlustL10n.string("Wanderlust uses your location to show your current position.\nYou can use Wanderlust without location access.", table: .settings),
            primaryTitle: isDenied
                ? WanderlustL10n.string("Open Settings", table: .settings)
                : WanderlustL10n.string("Allow Location", table: .settings),
            secondaryTitle: String(localized: "Not Now"),
            primaryAction: isDenied ? onOpenSettings : onAllow,
            secondaryAction: onContinue
        )
    }
}

private struct PostOnboardingNotificationPermissionView: View {
    let onAllow: () -> Void
    let onOpenSettings: () -> Void
    let onContinue: () -> Void

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var isDenied: Bool {
        authorizationStatus == .denied
    }

    var body: some View {
        PermissionPromptView(
            icon: isDenied ? "bell.slash.fill" : "bell.badge.fill",
            color: .orange,
            title: isDenied
                ? WanderlustL10n.string("Notifications Are Off", table: .errors)
                : WanderlustL10n.string("Enable Notifications", table: .settings),
            message: isDenied
                ? WanderlustL10n.string("Wanderlust can continue without notifications. You can enable them later in iPhone Settings.", table: .settings)
                : WanderlustL10n.string("Wanderlust can remind you to keep your trips and travel records up to date. You can use Wanderlust without notifications and change this later in iPhone Settings.", table: .settings),
            primaryTitle: isDenied
                ? WanderlustL10n.string("Open Settings", table: .settings)
                : WanderlustL10n.string("Allow Notifications", table: .settings),
            secondaryTitle: String(localized: "Not Now"),
            primaryAction: isDenied ? onOpenSettings : onAllow,
            secondaryAction: onContinue
        )
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
    }
}

private struct PermissionPromptView: View {
    let icon: String
    let color: Color
    let title: String
    let message: String
    let primaryTitle: String
    let secondaryTitle: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 132, height: 132)

                    Image(systemName: icon)
                        .wanderlustDecorativeFont(54, weight: .semibold)
                        .foregroundStyle(color)
                }

                VStack(spacing: 12) {
                    Text(title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 14) {
                Button(action: primaryAction) {
                    Text(primaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(color)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button(action: secondaryAction) {
                    Text(secondaryTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 44)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

private struct WorldMapModeSwitch: View {
    @Binding var selection: WorldMapMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(WorldMapMode.allCases) { mode in
                Button {
                    guard selection != mode else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        selection = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == mode ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if selection == mode {
                        Capsule(style: .continuous)
                            .fill(Color(.systemBackground).opacity(0.78))
                            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                    }
                }
            }
        }
        .padding(5)
        .frame(height: 50)
        .wanderlustGlassSurface(radius: WanderlustRadius.medium, isInteractive: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(WanderlustL10n.string("Map Mode", table: .settings))
    }
}

// MARK: - Country Detail Sheet

private struct CountryDetailSheet: View {
    let country: Country

    @ObservedObject
    var tripStore: TripStore

    @Environment(\.dismiss)
    private var dismiss

    @State private var editingTrip: Trip?

    private var cities: [VisitedCity] {
        tripStore.cities(
            inCountry: country.isoCode
        )
    }

    private var trips: [Trip] {
        tripStore.trips(
            visitingCountry: country.isoCode
        )
        .sorted { first, second in
            if first.startDate != second.startDate {
                return first.startDate < second.startDate
            }
            return first.displayTitle.localizedCaseInsensitiveCompare(second.displayTitle) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Text(country.flagEmoji)
                            .wanderlustDecorativeFont(44)

                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            Text(country.displayName)
                                .font(.title2.bold())

                            HStack(spacing: 10) {
                                WanderlustInlineCount(
                                    systemImage: "building.2",
                                    text: PluralizationFormatter.compactCities(cities.count)
                                )
                                WanderlustInlineCount(
                                    systemImage: "suitcase.fill",
                                    text: PluralizationFormatter.compactTrips(trips.count)
                                )
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if !cities.isEmpty {
                    Section(WanderlustL10n.string("Cities", table: .trips)) {
                        ForEach(cities) { city in
                            VStack(
                                alignment: .leading,
                                spacing: 5
                            ) {
                                Text(city.localizedName)
                                    .font(.headline)

                                let periods = visitPeriods(for: city)
                                if !periods.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(periods) { period in
                                            Text(
                                                WanderlustDateFormatter.dateRange(
                                                    start: period.startDate,
                                                    end: period.endDate
                                                )
                                            )
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if !trips.isEmpty {
                    Section(WanderlustL10n.string("Trips", table: .trips)) {
                        ForEach(trips) { trip in
                            NavigationLink {
                                TripDetailView(
                                    tripID: trip.id,
                                    tripStore: tripStore
                                )
                            } label: {
                                TripSummaryRow(
                                    trip: trip
                                )
                            }
                            .swipeActions(
                                edge: .trailing,
                                allowsFullSwipe: false
                            ) {
                                Button(
                                    role: .destructive
                                ) {
                                    tripStore.deleteTrip(
                                        trip
                                    )
                                } label: {
                                    Label(
                                        String(localized: "Delete"),
                                        systemImage: "trash"
                                    )
                                }
                                .tint(.red)

                                Button {
                                    editingTrip = trip
                                } label: {
                                    Label(
                                        String(localized: "Edit"),
                                        systemImage: "pencil"
                                    )
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle(country.displayName)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button {
                        dismiss()
                    } label: {
                        Text(String(localized: "Done"))
                    }
                    .tint(.blue)
                    .fontWeight(.regular)
                }
            }
        }
        .sheet(item: $editingTrip) { trip in
            EditTripView(trip: trip)
        }
    }

    private func visitPeriods(for city: VisitedCity) -> [VisitPeriod] {
        trips
            .flatMap { trip in
                trip.cities
                    .filter { citiesMatch($0, city) }
                    .flatMap(\.sortedPeriods)
            }
            .sorted { first, second in
                if first.startDate != second.startDate {
                    return first.startDate < second.startDate
                }
                return first.endDate < second.endDate
            }
    }

    private func citiesMatch(_ first: VisitedCity, _ second: VisitedCity) -> Bool {
        if let firstGeonameID = first.geonameID,
           let secondGeonameID = second.geonameID {
            return firstGeonameID == secondGeonameID
        }

        let firstCountryCode = first.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let secondCountryCode = second.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let countriesMatch = !firstCountryCode.isEmpty && firstCountryCode == secondCountryCode

        return countriesMatch &&
            first.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(
                    second.name.trimmingCharacters(in: .whitespacesAndNewlines)
                ) == .orderedSame
    }
}

// MARK: - City Detail Sheet

private struct CityDetailSheet: View {
    let city: VisitedCity

    @ObservedObject
    var tripStore: TripStore

    @Environment(\.dismiss)
    private var dismiss

    @State private var editingTrip: Trip?

    private var trips: [Trip] {
        tripStore.trips(
            visitingCity: city
        )
        .sorted { first, second in
            if first.startDate != second.startDate {
                return first.startDate < second.startDate
            }
            return first.displayTitle.localizedCaseInsensitiveCompare(second.displayTitle) == .orderedAscending
        }
    }

    private var currentCity: VisitedCity {
        trips
            .flatMap(\.cities)
            .first { citiesMatch($0, city) } ?? city
    }

    private var visitPeriods: [VisitPeriod] {
        trips
            .flatMap { trip in
                trip.cities
                    .filter { citiesMatch($0, city) }
                    .flatMap(\.sortedPeriods)
            }
            .sorted { first, second in
                if first.startDate != second.startDate {
                    return first.startDate < second.startDate
                }
                return first.endDate < second.endDate
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {
                        Text(currentCity.localizedName)
                            .font(.title2.bold())

                        Text(currentCity.localizedCountryName)
                            .foregroundStyle(.secondary)

                        WanderlustInlineCount(
                            systemImage: "suitcase.fill",
                            text: PluralizationFormatter.compactTrips(trips.count)
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                if !visitPeriods.isEmpty {
                    Section(WanderlustL10n.string("Visit Period", table: .trips)) {
                        ForEach(visitPeriods) { period in
                            Text(WanderlustDateFormatter.dateRange(
                                start: period.startDate,
                                end: period.endDate
                            ))
                        }
                        if !currentCity.notes.isEmpty {
                            Text(currentCity.notes)
                        }
                    }
                }

                if !trips.isEmpty {
                    Section(WanderlustL10n.string("Trips", table: .trips)) {
                        ForEach(trips) { trip in
                            NavigationLink {
                                TripDetailView(
                                    tripID: trip.id,
                                    tripStore: tripStore
                                )
                            } label: {
                                TripSummaryRow(
                                    trip: trip
                                )
                            }
                            .swipeActions(
                                edge: .trailing,
                                allowsFullSwipe: false
                            ) {
                                Button(
                                    role: .destructive
                                ) {
                                    tripStore.deleteTrip(
                                        trip
                                    )
                                } label: {
                                    Label(
                                        String(localized: "Delete"),
                                        systemImage: "trash"
                                    )
                                }
                                .tint(.red)

                                Button {
                                    editingTrip = trip
                                } label: {
                                    Label(
                                        String(localized: "Edit"),
                                        systemImage: "pencil"
                                    )
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle(currentCity.localizedName)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button {
                        dismiss()
                    } label: {
                        Text(String(localized: "Done"))
                    }
                    .fontWeight(.regular)
                }
            }
        }
        .sheet(item: $editingTrip) { trip in
            EditTripView(trip: trip)
        }
    }

    private func citiesMatch(_ first: VisitedCity, _ second: VisitedCity) -> Bool {
        if let firstGeonameID = first.geonameID,
           let secondGeonameID = second.geonameID {
            return firstGeonameID == secondGeonameID
        }

        let firstCountryCode = first.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let secondCountryCode = second.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let countriesMatch = !firstCountryCode.isEmpty && firstCountryCode == secondCountryCode

        return countriesMatch &&
            first.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(
                    second.name.trimmingCharacters(in: .whitespacesAndNewlines)
                ) == .orderedSame
    }
}

// MARK: - Trip Summary Row

private struct TripSummaryRow: View {
    let trip: Trip

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            Text(trip.dateRangeText)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 12) {
                WanderlustInlineCount(
                    systemImage: "building.2",
                    text: PluralizationFormatter.compactCities(trip.cityCount)
                )

                if trip.flightCount > 0 {
                    WanderlustInlineCount(
                        systemImage: "airplane",
                        text: PluralizationFormatter.compactFlights(trip.flightCount)
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}
