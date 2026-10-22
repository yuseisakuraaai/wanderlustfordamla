import SwiftUI
import MapKit
import CoreLocation

// MARK: - Flight playback screen

struct FlightMapView: View {
    let flight: Flight
    let flights: [Flight]

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FlightPlaybackViewModel
    @State private var projectionRevision = 0
    @State private var preparationTask: Task<Void, Never>?

    init(flight: Flight) {
        self.flight = flight
        self.flights = [flight]
        _viewModel = StateObject(
            wrappedValue: FlightPlaybackViewModel(flight: flight)
        )
    }

    init(flights: [Flight]) {
        let sortedFlights = flights.sorted { $0.departureDate < $1.departureDate }
        let firstFlight = sortedFlights.first ?? Flight()
        self.flight = firstFlight
        self.flights = sortedFlights
        _viewModel = StateObject(
            wrappedValue: FlightPlaybackViewModel(flights: sortedFlights)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                playbackMap
                controlsOverlay

                if viewModel.isPreparingPlayback {
                    preparingOverlay
                } else if viewModel.preparationFailed {
                    failureOverlay
                }

            }
            .navigationTitle(viewModel.routeTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Close")) {
                        closeFlightPlayback()
                    }
                    .disabled(viewModel.isCloseDisabled)
                }
            }
            .onAppear {
                startPreparationIfNeeded()
            }
            .onDisappear {
                preparationTask?.cancel()
                preparationTask = nil
                viewModel.cancelPreparation()
                viewModel.stop()
            }
            .onChange(of: viewModel.cameraPosition.positionedByUser) { _, positionedByUser in
                guard positionedByUser else { return }
                viewModel.userDidMoveMap()
            }
        }
    }

    // MARK: Map and unified screen-space overlays

    private var playbackMap: some View {
        MapReader { proxy in
            ZStack {
                Map(
                    position: $viewModel.cameraPosition,
                    interactionModes: .all
                )
                .mapStyle(
                    .standard(
                        elevation: .flat,
                        emphasis: .muted,
                        pointsOfInterest: .excludingAll,
                        showsTraffic: false
                    )
                )
                .onMapCameraChange(frequency: .onEnd) { _ in
                    projectionRevision &+= 1
                }

                if viewModel.cameraFollowMode == .following,
                   viewModel.routeGeometry != nil,
                   let markerState = viewModel.currentMarkerState {
                    FlightPlaybackOverlay(
                        traveledCoordinates: viewModel.traveledCoordinates,
                        remainingCoordinates: viewModel.remainingCoordinates,
                        markerState: markerState,
                        airports: viewModel.airportAnnotations,
                        markerLabel: viewModel.aircraftLabel,
                        proxy: proxy,
                        projectionRevision: projectionRevision
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: Controls

    private var controlsOverlay: some View {
        VStack {
            flightInformationCard

            if viewModel.shouldShowResumeFollowing {
                resumeFollowingButton
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()
            playbackControls
        }
        .padding()
    }

    private var resumeFollowingButton: some View {
        Button {
            viewModel.resumeFollowing()
        } label: {
            Label(
                String(localized: "Resume Following"),
                systemImage: "location.fill"
            )
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, WanderlustSpacing.large)
            .padding(.vertical, WanderlustSpacing.medium)
            .wanderlustGlassSurface(
                radius: WanderlustRadius.capsule,
                isInteractive: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Resume Following"))
    }

    private var flightInformationCard: some View {
        let informationSpacing: CGFloat = 5
        return VStack(alignment: .leading, spacing: 0) {
            Text(airportRouteText)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(routeAirportCount >= 4 ? 2 : 1)
                .minimumScaleFactor(routeAirportCount >= 4 ? 0.82 : 0.68)
                .multilineTextAlignment(.leading)
                .allowsTightening(true)

            if !airlineFlightText.isEmpty {
                Text(airlineFlightText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.top, informationSpacing)
            }

            HStack(alignment: .center, spacing: 10) {
                if !dateDurationText.isEmpty {
                    Text(dateDurationText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 8)

                progressCapsule
            }
            .padding(.top, informationSpacing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .wanderlustGlassSurface(radius: WanderlustRadius.xLarge)
    }

    private var progressCapsule: some View {
        Text(viewModel.progress.formatted(.percent.precision(.fractionLength(0))))
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel(
                String(
                    format: String(localized: "Progress %d percent"),
                    Int((viewModel.progress * 100).rounded())
                )
            )
    }

    private var airportRouteText: String {
        var parts: [String] = []
        let sortedFlights = flights.sorted { $0.departureDate < $1.departureDate }
        if let first = sortedFlights.first?.effectiveLegs.first {
            parts.append(airportDisplayName(
                localizedName: first.localizedDepartureAirportName,
                englishName: first.departureAirportName,
                code: first.departureAirportCode
            ))
        }
        for flight in sortedFlights {
            for leg in flight.effectiveLegs {
                parts.append(airportDisplayName(
                    localizedName: leg.localizedArrivalAirportName,
                    englishName: leg.arrivalAirportName,
                    code: leg.arrivalAirportCode
                ))
            }
        }
        return parts
            .map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
            .joined(separator: " → ")
    }

    private var routeAirportCount: Int {
        let sortedFlights = flights.sorted { $0.departureDate < $1.departureDate }
        guard !sortedFlights.isEmpty else { return 0 }
        return sortedFlights.reduce(1) { count, flight in
            count + flight.effectiveLegs.count
        }
    }

    private func airportDisplayName(localizedName: String, englishName: String, code: String) -> String {
        let localized = localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localized.isEmpty, localized.localizedCaseInsensitiveCompare(code) != .orderedSame {
            return localized
        }

        let english = englishName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !english.isEmpty { return english }

        let cleanedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return cleanedCode.isEmpty ? "Airport" : cleanedCode
    }

    private var airlineFlightText: String {
        let currentFlight = viewModel.currentFlightForDisplay
        let name = currentFlight.localizedAirlineName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let number = currentFlight.displayFlightNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch (name.isEmpty, number.isEmpty) {
        case (true, true): return ""
        case (true, _): return number
        case (_, true): return name
        default: return "\(name) • \(number)"
        }
    }

    private var dateDurationText: String {
        guard flights.count > 1 else {
            return flight.durationText ?? ""
        }
        let duration = totalDurationText
        return duration.isEmpty
            ? String(format: WanderlustL10n.string("%d flights", table: .trips, fallback: "%d flights"), flights.count)
            : duration
    }

    private var totalDurationText: String {
        let sortedFlights = flights.sorted { $0.departureDate < $1.departureDate }
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

    private var playbackControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Text(viewModel.departureAirportCode)
                    .font(.headline.monospaced())
                    .frame(width: 44, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { viewModel.progress },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if editing {
                            viewModel.pause()
                        }
                    }
                )
                .accessibilityLabel(String(localized: "Flight progress"))

                Text(viewModel.arrivalAirportCode)
                    .font(.headline.monospaced())
                    .frame(width: 44, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)

                Button {
                    viewModel.rewind()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(String(localized: "Reset"))

                Spacer(minLength: 0)

                Button {
                    viewModel.togglePlayback()
                } label: {
                    if viewModel.isPreparingRoute {
                        ProgressView()
                            .frame(minWidth: 130)
                            .padding(.vertical, 6)
                    } else {
                        Label(
                            viewModel.playbackButtonTitle,
                            systemImage: viewModel.playbackButtonSystemImage
                        )
                        .fontWeight(.semibold)
                        .frame(minWidth: 130)
                        .padding(.vertical, 6)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.isRouteReady)
                .accessibilityLabel(viewModel.playbackButtonTitle)

                Spacer(minLength: 0)

                speedMenuButton

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .wanderlustGlassSurface(radius: WanderlustRadius.xLarge)
        .disabled(viewModel.isPreparingPlayback)
    }

    private var speedMenuButton: some View {
        let speeds: [Double] = [0.5, 1.0, 1.5]
        return Menu {
            Picker(
                String(localized: "Playback speed"),
                selection: Binding(
                    get: { viewModel.playbackSpeed },
                    set: { viewModel.setSpeed($0) }
                )
            ) {
                ForEach(speeds, id: \.self) { speed in
                    Text(speedLabel(for: speed))
                        .tag(speed)
                }
            }
        } label: {
            Text(speedLabel(for: viewModel.playbackSpeed))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.bordered)
        .menuOrder(.fixed)
        .accessibilityLabel(String(localized: "Playback speed"))
    }

    private func speedLabel(for speed: Double) -> String {
        speed.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(speed))×"
            : String(format: "%.1f×", speed)
    }

    // MARK: Loading / error overlays

    private func closeFlightPlayback() {
        preparationTask?.cancel()
        preparationTask = nil
        viewModel.cancelPreparation()
        viewModel.stop()
        dismiss()
    }

    private func startPreparationIfNeeded() {
        guard preparationTask == nil else { return }
        preparationTask = Task { @MainActor in
            await viewModel.prepareIfNeeded()
            preparationTask = nil
        }
    }

    private var preparingOverlay: some View {
        ZStack {
            Color.black.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)

                Text(WanderlustL10n.string("Preparing flight…", table: .general))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .wanderlustGlassSurface(radius: WanderlustRadius.xLarge)
            .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
        }
        .transition(.opacity)
        .zIndex(1000)
        .allowsHitTesting(false)
    }

    private var failureOverlay: some View {
        ZStack {
            Color.black.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(WanderlustL10n.string("Unable to show flight", table: .general))
                        .font(.headline)

                    Text(WanderlustL10n.string("Route information could not be loaded. Please try again.", table: .general))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    Button(WanderlustL10n.string("Close", table: .general)) {
                        viewModel.stop()
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button(WanderlustL10n.string("Retry", table: .settings, fallback: String(localized: "Retry"))) {
                        Task { await viewModel.retryPreparation() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .wanderlustGlassSurface(radius: WanderlustRadius.xLarge)
            .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
            .padding(.horizontal, 40)
        }
        .transition(.opacity)
        .zIndex(1000)
    }
}

// MARK: - Unified overlay

private struct FlightPlaybackOverlay: View {
    let traveledCoordinates: [CLLocationCoordinate2D]
    let remainingCoordinates: [CLLocationCoordinate2D]
    let markerState: FlightMarkerState
    let airports: [FlightAirportAnnotation]
    let markerLabel: String
    let proxy: MapProxy
    let projectionRevision: Int

    var body: some View {
        let traveledCoordinates = overlayTraveledCoordinates
        let remainingCoordinates = overlayRemainingCoordinates

        GeometryReader { geometry in
            let markerPoint = projectedPoint(
                for: markerState.coordinate,
                fallbackSize: geometry.size
            )

            ZStack {
                Canvas { context, _ in
                    func makePath(_ coords: [CLLocationCoordinate2D]) -> Path {
                        var path = Path()
                        var isFirst = true
                        for coord in coords {
                            guard let point = proxy.convert(coord, to: .local) else { continue }
                            if isFirst {
                                path.move(to: point)
                                isFirst = false
                            } else {
                                path.addLine(to: point)
                            }
                        }
                        return path
                    }

                    let remainingPath = makePath(remainingCoordinates)
                    if !remainingPath.isEmpty {
                        context.stroke(
                            remainingPath,
                            with: .color(.blue.opacity(0.65)),
                            style: StrokeStyle(
                                lineWidth: 6,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: [12, 10]
                            )
                        )
                    }

                    let traveledPath = makePath(traveledCoordinates)
                    if !traveledPath.isEmpty {
                        context.stroke(
                            traveledPath,
                            with: .color(.blue.opacity(0.92)),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
                .allowsHitTesting(false)

                ForEach(airports) { airport in
                    if let point = proxy.convert(airport.coordinate, to: .local) {
                        AirportMapLabel(
                            name: airport.name,
                            code: airport.code,
                            labelPlacement: airport.labelPlacement
                        )
                        .position(point)
                        .zIndex(20)
                    }
                }

                ForEach(airports) { airport in
                    if let point = proxy.convert(airport.coordinate, to: .local) {
                        AirportPinDot()
                            .position(point)
                            .zIndex(30)
                    }
                }

                FlightMarkerView(
                    label: markerLabel,
                    rotation: markerState.rotation
                )
                .position(markerPoint)
                .zIndex(40)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var overlayTraveledCoordinates: [CLLocationCoordinate2D] {
        guard !traveledCoordinates.isEmpty else {
            return [markerState.coordinate]
        }

        var coordinates = traveledCoordinates
        if coordinates.last?.distance(to: markerState.coordinate) ?? .infinity > 0.5 {
            coordinates.append(markerState.coordinate)
        } else {
            coordinates[coordinates.count - 1] = markerState.coordinate
        }
        return coordinates
    }

    private var overlayRemainingCoordinates: [CLLocationCoordinate2D] {
        guard !remainingCoordinates.isEmpty else {
            return [markerState.coordinate]
        }

        var coordinates = remainingCoordinates
        if coordinates.first?.distance(to: markerState.coordinate) ?? .infinity > 0.5 {
            coordinates.insert(markerState.coordinate, at: 0)
        } else {
            coordinates[0] = markerState.coordinate
        }
        return coordinates
    }

    private func projectedPoint(
        for coordinate: CLLocationCoordinate2D,
        fallbackSize size: CGSize
    ) -> CGPoint {
        proxy.convert(coordinate, to: .local) ??
            CGPoint(x: size.width / 2, y: size.height / 2)
    }
}

// MARK: - Airport and marker views

private struct FlightMarkerView: View {
    let label: String
    let rotation: Angle

    var body: some View {
        ZStack {
            Image(systemName: "airplane")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(rotation)
                .padding(11)
                .background(.blue, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.9), lineWidth: 2)
                }
                .shadow(radius: 7)
                .zIndex(1)

            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 74)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .offset(y: 43)
                .zIndex(2)
        }
        .frame(width: 104, height: 112)
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

private struct AirportMapLabel: View {
    let name: String
    let code: String
    let labelPlacement: AirportLabelPlacement

    var body: some View {
        labelBubble
            .offset(labelOffset)
            .frame(width: 128, height: 56)
            .accessibilityLabel(displayNameOrCode)
            .transaction { transaction in
                transaction.animation = nil
            }
    }

    private var labelBubble: some View {
        Text(displayNameOrCode)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.primary)
            .frame(width: 96)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 0.5)
            }
            .overlay(alignment: tailAlignment) {
                AirportLabelTail()
                    .fill(.ultraThinMaterial)
                    .frame(width: 9, height: 9)
                    .rotationEffect(.degrees(tailRotation))
                    .offset(tailOffset)
            }
    }

    private var labelOffset: CGSize {
        switch labelPlacement {
        case .left:
            return CGSize(width: -57, height: -7)
        case .right:
            return CGSize(width: 57, height: -7)
        }
    }

    private var tailAlignment: Alignment {
        labelPlacement == .left ? .trailing : .leading
    }

    private var tailOffset: CGSize {
        labelPlacement == .left
            ? CGSize(width: 5, height: 0)
            : CGSize(width: -5, height: 0)
    }

    private var tailRotation: Double {
        labelPlacement == .left ? 90 : -90
    }

    private var displayNameOrCode: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmedCode.isEmpty ? "APT" : trimmedCode
    }
}

private struct AirportPinDot: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.94))
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.14), radius: 4, y: 1)

            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
        }
        .frame(width: 18, height: 18)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct AirportLabelTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
