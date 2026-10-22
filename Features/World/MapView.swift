import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - World Map Mode

enum WorldMapMode:
    String,
    CaseIterable,
    Identifiable
{
    case countries
    case cities

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .countries:
            return String(localized: "Countries")

        case .cities:
            return WanderlustL10n.string("Cities", table: .trips)
        }
    }
}

// MARK: - Map View

struct MapView: View {
    let trips: [Trip]
    let homeCountry: String
    let mode: WorldMapMode
    var focusedCountry: Country? = nil
    var focusRequestID: UUID? = nil
    var showHomeHighlight: Bool = true
    var onCountryTap: ((Country) -> Void)? = nil
    var onMapReady: (() -> Void)? = nil

    @State private var cameraPosition:
        MapCameraPosition = MapCameraMemory.lastPosition ?? MapView.defaultCameraPosition

    @State private var selectedCity:
        MapCitySelection?

    @StateObject private var locationManager =
        WanderlustLocationManager()

    @ObservedObject private var geoJSONLoader =
        GeoJSONLoader.shared

    @State private var showLocationDeniedAlert = false
    @State private var pendingFocusedISO2: String?
    @State private var focusTask: Task<Void, Never>?
    @State private var cachedCitySelections: [MapCitySelection] = []
    @State private var cachedVisitedCountries: [Country] = []
    @State private var cachedTripsSignature = ""
    @State private var cachedVisitedCountriesSignature = ""
    @State private var countryPreparationTask: Task<Void, Never>?
    @State private var didNotifyMapReady = false

    @Environment(\.colorScheme) private var colorScheme

    private var selectedHomeCountry:
        Country? {
        let cleaned =
            homeCountry
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard !cleaned.isEmpty else {
            return nil
        }

        return geoJSONLoader.country(withISOCode: cleaned) ??
            geoJSONLoader.country(named: cleaned)
    }

    private var tripsSignature: String {
        trips.map { trip in
            tripChangeSignature(for: trip)
        }
        .joined(separator: "|")
    }

    private func tripChangeSignature(for trip: Trip) -> String {
        [
            trip.id.uuidString,
            String(trip.updatedAt.timeIntervalSince1970),
            String(trip.startDate.timeIntervalSince1970),
            String(trip.endDate.timeIntervalSince1970),
            String(trip.cities.count),
            String(trip.flights.count)
        ]
        .joined(separator: ":")
    }

    private func buildCitySelections() -> [MapCitySelection] {
        var selections:
            [String: MapCitySelection] = [:]

        for trip in trips {
            for city in trip.cities {
                let key =
                    cityDeduplicationKey(
                        city
                    )

                if var existing =
                    selections[key] {
                    if !existing.trips.contains(
                        where: {
                            $0.id == trip.id
                        }
                    ) {
                        existing.trips.append(
                            trip
                        )

                        existing.trips.sort {
                            $0.startDate >
                            $1.startDate
                        }

                        selections[key] =
                            existing
                    }
                } else {
                    selections[key] =
                        MapCitySelection(
                            city: city,
                            trips: [trip]
                        )
                }
            }
        }

        return selections.values
            .sorted {
                let leftCountryName =
                    $0.city.localizedCountryName
                let rightCountryName =
                    $1.city.localizedCountryName

                if leftCountryName !=
                    rightCountryName {
                    return leftCountryName
                        .localizedCaseInsensitiveCompare(
                            rightCountryName
                        ) ==
                        .orderedAscending
                }

                return $0.city.localizedName
                    .localizedCaseInsensitiveCompare(
                        $1.city.localizedName
                    ) ==
                    .orderedAscending
            }
    }

    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(
                    position: $cameraPosition,
                    bounds: MapCameraBounds(
                        minimumDistance: 1_800_000,
                        maximumDistance: 20_000_000
                    ),
                    interactionModes: .all
                ) {
                    homeCountryMapContent

                    if mode == .countries {
                        countryMapContent
                    }

                    if mode == .cities {
                        cityMapContent
                    }
                }
                .mapStyle(
                    .standard(
                        elevation: .flat,
                        emphasis: .muted,
                        pointsOfInterest:
                            .excludingAll,
                        showsTraffic: false
                    )
                )
                .ignoresSafeArea()
                .onMapCameraChange(frequency: .onEnd) { context in
                    MapCameraMemory.lastPosition = .region(context.region)
                }
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { event in
                            handleMapTap(at: event.location, proxy: proxy)
                        }
                )
            }

            mapLegend
            locationButtonOverlay
        }
        .sheet(
            item: $selectedCity
        ) { selection in
            MapCityDetailSheet(
                selection: selection
            )
            .presentationDetents([
                .fraction(0.34),
                .medium,
                .large
            ])
            .presentationDragIndicator(
                .visible
            )
        }
        .onAppear {
            #if DEBUG
            MapCameraMemory.logFirstMapDisplayIfNeeded()
            #endif
            refreshCitySelectionsIfNeeded()
            prepareCountryFillCache(force: true, notifyWhenReady: true)
            locationManager.refreshAuthorization()
            if let focusedCountry {
                requestFocus(on: focusedCountry)
            } else if locationManager.isAuthorized,
               !MapCameraMemory.didCenterOnLaunch {
                MapCameraMemory.didCenterOnLaunch = true
                centerOnUserLocation(animated: false)
            }
        }
        .onChange(of: focusedCountry?.id) {
            if let focusedCountry {
                requestFocus(on: focusedCountry)
            }
        }
        .onChange(of: tripsSignature) {
            refreshCitySelectionsIfNeeded(force: true)
            prepareCountryFillCache(force: true)
        }
        .onChange(of: mode) { _, newMode in
            #if DEBUG
            let start = CFAbsoluteTimeGetCurrent()
            defer {
                print(String(format: "[WanderlustPerformance] world_mode_switch_%@ %.1fms", newMode.rawValue, (CFAbsoluteTimeGetCurrent() - start) * 1000))
            }
            #endif
            if newMode == .cities {
                refreshCitySelectionsIfNeeded()
            } else {
                prepareCountryFillCache()
            }
        }
        .onChange(of: focusRequestID) {
            if let focusedCountry {
                requestFocus(on: focusedCountry)
            }
        }
        .onChange(of: GeoJSONLoader.shared.countries.count) {
            prepareCountryFillCache(force: true)
            applyPendingFocusIfPossible()
        }
        .onChange(of: locationManager.authorizationStatus) {
            if locationManager.isAuthorized,
               locationManager.shouldCenterAfterAuthorization {
                locationManager.shouldCenterAfterAuthorization = false
                MapCameraMemory.didCenterOnLaunch = true
                centerOnUserLocation(animated: false)
            }
        }
        .onChange(of: locationManager.currentLocation?.timestamp) {
            if MapCameraMemory.shouldApplyPendingInitialLocation {
                MapCameraMemory.shouldApplyPendingInitialLocation = false
                centerOnUserLocation(animated: false)
            }
        }
        .alert(
            WanderlustL10n.string("Location Access Needed", table: .errors),
            isPresented: $showLocationDeniedAlert
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(WanderlustL10n.string("Enable location access in Settings to show your current location on the map.", table: .errors))
        }
        .onDisappear {
            focusTask?.cancel()
            focusTask = nil
            countryPreparationTask?.cancel()
            countryPreparationTask = nil
        }
    }

    // MARK: - Location Button Overlay

    private var locationButtonOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    handleLocationButton()
                } label: {
                    Image(systemName: locationManager.isAuthorized ? "location.fill" : "location")
                        .wanderlustFont(16, relativeTo: .callout, weight: .semibold)
                        .foregroundStyle(locationManager.isDenied ? Color.secondary : Color.blue)
                        .frame(width: 44, height: 44)
                        // Liquid Glass 自体が影を持つため、手動 shadow は重ねない。
                        .wanderlustGlassSurface(radius: WanderlustRadius.capsule, isInteractive: true)
                }
                .accessibilityLabel(WanderlustL10n.string("Current Location", table: .settings))
                .padding(.trailing, 16)
                .padding(.bottom, 76)
            }
        }
    }

    // MARK: - Country Map Content

    @MapContentBuilder
    private var homeCountryMapContent:
        some MapContent {
        if showHomeHighlight,
           let selectedHomeCountry {
            ForEach(
                Array(
                    selectedHomeCountry
                        .polygonParts
                        .enumerated()
                ),
                id: \.offset
            ) { item in
                MapPolygon(
                    mkPolygon(
                        for: selectedHomeCountry,
                        partIndex: item.offset,
                        polygon: item.element
                    )
                )
                .foregroundStyle(
                    Color.orange.opacity(0.72)
                )
                .stroke(
                    countryBorderColor(for: selectedHomeCountry),
                    lineWidth: countryBorderWidth(for: selectedHomeCountry)
                )
            }
        }
    }

    @MapContentBuilder
    private var countryMapContent:
        some MapContent {
        ForEach(
            cachedVisitedCountries
        ) { country in
            ForEach(
                Array(
                    country.polygonParts
                        .enumerated()
                ),
                id: \.offset
            ) { item in
                MapPolygon(
                    mkPolygon(
                        for: country,
                        partIndex: item.offset,
                        polygon: item.element
                    )
                )
                .foregroundStyle(
                    showHomeHighlight && isHomeCountry(country)
                    ? Color.orange.opacity(0.72)
                    : (colorScheme == .dark
                        ? Color.blue.opacity(0.60)
                        : Color.purple.opacity(0.65))
                )
                .stroke(
                    countryBorderColor(for: country),
                    lineWidth: countryBorderWidth(for: country)
                )
            }
        }

        UserAnnotation()
    }

    // MARK: - City Map Content

    @MapContentBuilder
    private var cityMapContent:
        some MapContent {
        ForEach(
            cachedCitySelections
        ) { selection in
            Annotation(
                "",
                coordinate:
                    selection.city.coordinate,
                anchor: .center
            ) {
                Button {
                    selectedCity =
                        selection
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(
                                    .red.opacity(
                                        0.78
                                    )
                                )
                                .frame(
                                    width: 28,
                                    height: 28
                                )

                            Circle()
                                .stroke(
                                    .white,
                                    lineWidth: 3
                                )
                                .frame(
                                    width: 28,
                                    height: 28
                                )

                            Circle()
                                .fill(.white)
                                .frame(
                                    width: 7,
                                    height: 7
                                )
                        }
                        .shadow(radius: 4)

                        Text(
                            selection.city.localizedName
                        )
                        .font(
                            .caption2
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            .primary
                        )
                        .lineLimit(1)
                        .padding(
                            .horizontal,
                            7
                        )
                        .padding(
                            .vertical,
                            4
                        )
                        .background(
                            .ultraThinMaterial
                        )
                        .clipShape(
                            Capsule()
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    PluralizationFormatter.cityAccessibilityLabel(
                        city: selection.city.localizedName,
                        country: selection.city.localizedCountryName
                    )
                )
            }
        }

        UserAnnotation()
    }

    // MARK: - Legend

    private var mapLegend:
        some View {
        VStack {
            Spacer()

            HStack(spacing: 16) {
                if mode == .countries {
                    if showHomeHighlight && selectedHomeCountry != nil {
                        Label(
                            WanderlustL10n.string("Home Country", table: .account),
                            systemImage: "house.fill"
                        )
                        .foregroundStyle(.orange)
                    }

                    Label(
                        WanderlustL10n.string("Visited", table: .trips),
                        systemImage: "circle.fill"
                    )
                    .foregroundStyle(colorScheme == .dark ? Color.blue : Color.purple)
                } else {
                    Label(
                        WanderlustL10n.string("Visited", table: .trips),
                        systemImage: "circle.fill"
                    )
                    .foregroundStyle(.red)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .wanderlustGlassSurface(radius: WanderlustRadius.capsule)
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
            .padding(.bottom, 20)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private func mkPolygon(
        for country: Country,
        partIndex: Int,
        polygon: CountryPolygon
    ) -> MKPolygon {
        MapPolygonCache.polygon(
            countryID: country.id,
            partIndex: partIndex,
            polygon: polygon
        )
    }

    private func countryBorderColor(for country: Country) -> Color {
        let isFocused = focusedCountry.map { countriesMatch(country, $0) } ?? false
        if colorScheme == .dark {
            return isFocused ? Color.white.opacity(0.58) : Color.white.opacity(0.34)
        }

        return isFocused ? Color.black.opacity(0.50) : Color.black.opacity(0.30)
    }

    private func countryBorderWidth(for country: Country) -> CGFloat {
        let isFocused = focusedCountry.map { countriesMatch(country, $0) } ?? false
        return isFocused ? 1.05 : 0.65
    }

    private func isHomeCountry(
        _ country: Country
    ) -> Bool {
        guard let selectedHomeCountry else {
            return false
        }

        return countriesMatch(
            country,
            selectedHomeCountry
        )
    }

    private func countriesMatch(
        _ first: Country,
        _ second: Country
    ) -> Bool {
        if !first.isoCode.isEmpty,
           !second.isoCode.isEmpty {
            return first.isoCode
                .localizedCaseInsensitiveCompare(
                    second.isoCode
                ) ==
                .orderedSame
        }

        return first.name
            .localizedCaseInsensitiveCompare(
                second.name
            ) ==
            .orderedSame
    }

    private func cityDeduplicationKey(
        _ city: VisitedCity
    ) -> String {
        if let geonameID =
            city.geonameID {
            return "geoname-\(geonameID)"
        }

        return [
            normalized(city.name),
            WanderlustNameResolver.normalizedCountryCode(
                city.countryCode,
                fallback: city.countryName
            ),
            normalized(
                city.countryName
            )
        ]
        .joined(separator: "|")
    }

    private func refreshCitySelectionsIfNeeded(force: Bool = false) {
        let signature = tripsSignature
        guard force || cachedTripsSignature != signature else {
            return
        }

        #if DEBUG
        let start = CFAbsoluteTimeGetCurrent()
        #endif
        cachedCitySelections = buildCitySelections()
        cachedTripsSignature = signature
        refreshSelectedCityIfNeeded()
        #if DEBUG
        print(String(format: "[WanderlustPerformance] city_selection_cache %.1fms (%d cities)", (CFAbsoluteTimeGetCurrent() - start) * 1000, cachedCitySelections.count))
        #endif
    }

    private func refreshSelectedCityIfNeeded() {
        guard let selectedCity else {
            return
        }

        self.selectedCity = cachedCitySelections.first {
            $0.id == selectedCity.id
        }
    }

    private func refreshVisitedCountriesIfNeeded(force: Bool = false) {
        guard !geoJSONLoader.countries.isEmpty else {
            return
        }

        let signature = "\(tripsSignature)#countries:\(geoJSONLoader.countries.count)"
        guard force || cachedVisitedCountriesSignature != signature else {
            return
        }

        #if DEBUG
        let start = CFAbsoluteTimeGetCurrent()
        #endif
        // 塗りつぶし対象は VisitedCountryAggregator が同定した国のうち
        // GeoJSON に存在するものだけ。訪問国「数」の表示には使わない
        // （数は VisitedCountryAggregator.visitedCountryCount を使う）。
        let countries = VisitedCountryAggregator.mappableCountries(in: trips)
        cachedVisitedCountries = countries
        cachedVisitedCountriesSignature = signature
        MapPolygonCache.prewarm(countries: countries)
        #if DEBUG
        print(String(format: "[WanderlustPerformance] visited_country_cache %.1fms (%d countries)", (CFAbsoluteTimeGetCurrent() - start) * 1000, countries.count))
        #endif
    }

    private func prepareCountryFillCache(force: Bool = false, notifyWhenReady: Bool = false) {
        let signature = "\(tripsSignature)#countries:\(geoJSONLoader.countries.count)"
        if !force,
           !geoJSONLoader.countries.isEmpty,
           cachedVisitedCountriesSignature == signature {
            notifyMapReadyIfNeeded(shouldNotify: notifyWhenReady)
            return
        }

        countryPreparationTask?.cancel()
        countryPreparationTask = Task { @MainActor in
            #if DEBUG
            let start = CFAbsoluteTimeGetCurrent()
            #endif
            if geoJSONLoader.countries.isEmpty {
                await geoJSONLoader.loadIfNeededAsync()
            }

            guard !Task.isCancelled else {
                return
            }

            refreshVisitedCountriesIfNeeded(force: force)
            notifyMapReadyIfNeeded(shouldNotify: notifyWhenReady)
            #if DEBUG
            print(String(format: "[WanderlustPerformance] country_fill_prepare %.1fms (force=%@ countries=%d visited=%d)", (CFAbsoluteTimeGetCurrent() - start) * 1000, force.description, geoJSONLoader.countries.count, cachedVisitedCountries.count))
            #endif
            countryPreparationTask = nil
        }
    }

    private func notifyMapReadyIfNeeded(shouldNotify: Bool) {
        guard shouldNotify, !didNotifyMapReady else {
            return
        }

        didNotifyMapReady = true
        onMapReady?()
    }

    private func normalized(
        _ text: String
    ) -> String {
        text
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive
                ],
                locale: Locale(
                    identifier:
                        "en_US_POSIX"
                )
            )
            .lowercased()
    }

    private func handleLocationButton() {
        if locationManager.isAuthorized {
            centerOnUserLocation(animated: true)
            return
        }

        if locationManager.isDenied {
            showLocationDeniedAlert = true
            return
        }

        locationManager.requestWhenInUseAuthorization()
    }

    private func handleMapTap(at point: CGPoint, proxy: MapProxy) {
        guard mode == .countries,
              let onCountryTap,
              let coordinate = proxy.convert(point, from: .local) else {
            return
        }

        if let visitedCountry = cachedVisitedCountries
            .filter({ country in
                country.fullGeometryBounds?.contains(coordinate: coordinate) == true &&
                    country.contains(coordinate: coordinate)
            })
            .min(by: { $0.approximateArea < $1.approximateArea }) {
            onCountryTap(visitedCountry)
        }
    }

    private func centerOnUserLocation(animated: Bool) {
        let fallback = MapView.defaultCameraPosition
        let update = {
            guard let coordinate = locationManager.currentLocation?.coordinate else {
                MapCameraMemory.shouldApplyPendingInitialLocation = true
                cameraPosition = fallback
                return
            }

            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 82, longitudeDelta: 82)
                )
            )
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.55), update)
        } else {
            update()
        }
    }

    private func requestFocus(on country: Country) {
        pendingFocusedISO2 = country.iso2
        focusTask?.cancel()

        let requestID = UUID()
        MapCameraMemory.activeSearchFocusRequestID = requestID
        MapCameraMemory.didCenterOnLaunch = true
        MapCameraMemory.shouldApplyPendingInitialLocation = false

        focusTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,
                  MapCameraMemory.activeSearchFocusRequestID == requestID else {
                return
            }
            applyPendingFocusIfPossible()
            if MapCameraMemory.activeSearchFocusRequestID == requestID {
                focusTask = nil
            }
        }
    }

    private func applyPendingFocusIfPossible() {
        guard let pendingFocusedISO2 else {
            return
        }

        guard let country = GeoJSONLoader.shared.country(withISOCode: pendingFocusedISO2) ??
                focusedCountry else {
            return
        }

        focus(on: country)
        self.pendingFocusedISO2 = nil
    }

    private func focus(on country: Country) {
        guard let box = country.searchBoundingBox else {
            pendingFocusedISO2 = country.iso2
            return
        }

        MapCameraMemory.didCenterOnLaunch = true
        MapCameraMemory.shouldApplyPendingInitialLocation = false

        let latitudeDelta = max(
            min((box.maximumLatitude - box.minimumLatitude) * 1.7, 95),
            12
        )

        let longitudeDelta = max(
            min((box.maximumLongitude - box.minimumLongitude) * 1.7, 130),
            12
        )

        withAnimation(.easeInOut(duration: 0.72)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: box.center,
                    span: MKCoordinateSpan(
                        latitudeDelta: latitudeDelta,
                        longitudeDelta: longitudeDelta
                    )
                )
            )
        }
    }

    private static var defaultCameraPosition: MapCameraPosition {
        .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 25, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 110, longitudeDelta: 110)
            )
        )
    }
}

@MainActor
enum MapCameraMemory {
    static var lastPosition: MapCameraPosition?
    static var didCenterOnLaunch = false
    static var shouldApplyPendingInitialLocation = false
    static var activeSearchFocusRequestID: UUID?
    #if DEBUG
    private static var didLogFirstMapDisplay = false

    static func logFirstMapDisplayIfNeeded() {
        guard !didLogFirstMapDisplay else {
            return
        }

        didLogFirstMapDisplay = true
        #if DEBUG
        WanderlustDiagnostics.info("first_map_display", category: .performance)
        #endif
    }
    #endif
}

@MainActor
enum MapPolygonCache {
    private static var polygons: [String: MKPolygon] = [:]

    static func prewarm(countries: [Country]) {
        #if DEBUG
        let start = CFAbsoluteTimeGetCurrent()
        #endif

        for country in countries {
            for (partIndex, part) in country.polygonParts.enumerated() {
                _ = polygon(countryID: country.id, partIndex: partIndex, polygon: part)
            }
        }

        #if DEBUG
        print(String(format: "[WanderlustPerformance] country_polygon_prewarm %.1fms count=%d", (CFAbsoluteTimeGetCurrent() - start) * 1000, polygons.count))
        #endif
    }

    static func polygon(
        countryID: String,
        partIndex: Int,
        polygon: CountryPolygon
    ) -> MKPolygon {
        let key = "\(countryID)-\(partIndex)-\(polygon.exterior.count)-\(polygon.holes.reduce(0) { $0 + $1.count })"
        if let cached = polygons[key] {
            return cached
        }

        let holes = polygon.holes.map {
            MKPolygon(coordinates: $0, count: $0.count)
        }
        let mkPolygon = MKPolygon(
            coordinates: polygon.exterior,
            count: polygon.exterior.count,
            interiorPolygons: holes.isEmpty ? nil : holes
        )
        polygons[key] = mkPolygon
        return mkPolygon
    }
}

@MainActor
private final class WanderlustLocationManager:
    NSObject,
    ObservableObject,
    CLLocationManagerDelegate
{
    @Published var authorizationStatus:
        CLAuthorizationStatus

    @Published var currentLocation:
        CLLocation?

    var shouldCenterAfterAuthorization = false

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse ||
        authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied ||
        authorizationStatus == .restricted
    }

    func refreshAuthorization() {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            manager.requestLocation()
        }
    }

    func requestWhenInUseAuthorization() {
        shouldCenterAfterAuthorization = true
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if isAuthorized {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            currentLocation = locations.last
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {}
}

// MARK: - City Selection

private struct MapCitySelection:
    Identifiable
{
    let city: VisitedCity
    var trips: [Trip]

    var id: String {
        if let geonameID =
            city.geonameID {
            return "geoname-\(geonameID)"
        }

        return [
            city.name,
            city.countryCode,
            city.countryName
        ]
        .joined(separator: "|")
    }
}

// MARK: - Map City Detail Sheet

private struct MapCityDetailSheet:
    View
{
    let selection:
        MapCitySelection

    @Environment(\.dismiss)
    private var dismiss

    @ObservedObject private var tripStore = TripStore.shared

    @State private var editingTrip: Trip?

    var body: some View {
        NavigationStack {
            List {
                cityHeaderSection
                visitInformationSection
                tripsSection
            }
            .navigationTitle(
                selection.city.localizedName
            )
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
            .sheet(item: $editingTrip) { trip in
                EditTripView(trip: trip)
            }
        }
    }

    private var cityHeaderSection:
        some View {
        Section {
            HStack(spacing: 14) {
                Text(
                    flagEmoji(
                        countryCode:
                            selection.city
                                .countryCode
                    )
                )
                .wanderlustDecorativeFont(42)

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text(
                        selection.city.localizedName
                    )
                    .font(
                        .title2.bold()
                    )

                    Text(
                        selection.city
                            .localizedCountryName
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var visitInformationSection:
        some View {
        let periods = visitPeriods
        let notes = selection.city.notes
        if !periods.isEmpty || !notes.isEmpty {
            Section(WanderlustL10n.string("Visit Period", table: .trips)) {
                ForEach(Array(periods.enumerated()), id: \.offset) { _, period in
                    Text(visitPeriodText(start: period.start, end: period.end))
                        .font(.subheadline)
                }
                if !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var visitPeriods: [(start: Date, end: Date?)] {
        selection.trips.flatMap { trip -> [(start: Date, end: Date?)] in
            let city: VisitedCity?
            if let geonameID = selection.city.geonameID {
                city = trip.cities.first { $0.geonameID == geonameID }
            } else {
                city = trip.cities.first {
                    $0.name.localizedCaseInsensitiveCompare(selection.city.name) == .orderedSame
                }
            }
            guard let city else { return [] }
            return city.sortedPeriods.map { period in
                (start: period.startDate, end: period.endDate)
            }
        }
        .sorted {
            if $0.start != $1.start {
                return $0.start < $1.start
            }
            return ($0.end ?? $0.start) < ($1.end ?? $1.start)
        }
    }

    private func visitPeriodText(start: Date, end: Date?) -> String {
        guard let end else { return WanderlustDateFormatter.date(start) }
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return WanderlustDateFormatter.date(start)
        }
        return WanderlustDateFormatter.dateRange(start: start, end: end)
    }

    private var tripsSection:
        some View {
        Section(WanderlustL10n.string("Trips", table: .trips)) {
            ForEach(
                sortedTrips
            ) { trip in
                NavigationLink {
                    TripDetailView(trip: trip, tripStore: tripStore)
                } label: {
                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {
                        Text(trip.dateRangeText)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        HStack(spacing: 10) {
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
                        .foregroundStyle(
                            .secondary
                        )
                    }
                    .padding(.vertical, 4)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        tripStore.deleteTrip(trip)
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
            }
        }
    }

    private var sortedTrips: [Trip] {
        selection.trips.sorted { first, second in
            if first.startDate != second.startDate {
                return first.startDate < second.startDate
            }
            return first.displayTitle.localizedCaseInsensitiveCompare(second.displayTitle) == .orderedAscending
        }
    }

    private func flagEmoji(
        countryCode: String
    ) -> String {
        let code =
            countryCode
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .uppercased()

        guard code.count == 2 else {
            return "🌍"
        }

        return code.unicodeScalars
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

// MARK: - Flight Detail Row

private struct FlightDetailRow: View {
    let flight: Flight

    var body: some View {
        HStack(spacing: 14) {
            Image(
                systemName:
                    "airplane.circle.fill"
            )
            .font(.title2)
            .foregroundStyle(.blue)

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                HStack {
                    Text(
                        flight
                            .displayFlightNumber
                            .isEmpty
                        ? WanderlustL10n.string("Flight", table: .trips)
                        : flight
                            .displayFlightNumber
                    )
                    .font(.headline)

                    Spacer()

                    Text(
                        flight.routeTitle
                    )
                    .font(
                        .headline
                            .monospaced()
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Label(flight.departureDisplayText, systemImage: "airplane.departure")

                    if let arrivalDisplayText = flight.arrivalDisplayText {
                        Label(arrivalDisplayText, systemImage: "airplane.arrival")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let durationText = flight.durationText {
                    Label(durationText, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    MapView(
        trips: [],
        homeCountry: "Japan",
        mode: .countries
    )
}
