import Combine
import SwiftUI
import MapKit
import CoreLocation

// MARK: - FlightPlaybackViewModel

@MainActor
final class FlightPlaybackViewModel: ObservableObject {
    enum PlaybackState: Equatable {
        case idle
        case playing
        case paused
        case completed
    }

    enum CameraFollowMode: Equatable {
        case following
        case manual
    }

    let flights: [Flight]
    let flight: Flight

    @Published var progress: Double = 0
    @Published var playbackState: PlaybackState = .idle
    @Published var cameraFollowMode: CameraFollowMode = .following
    @Published var cameraPosition: MapCameraPosition = .automatic
    @Published var routeGeometry: FlightRouteGeometry?
    @Published var traveledCoordinates: [CLLocationCoordinate2D] = []
    @Published var remainingCoordinates: [CLLocationCoordinate2D] = []
    @Published var markerState: FlightMarkerState?
    @Published var airportAnnotations: [FlightAirportAnnotation] = []
    @Published var isPreparingRoute = true
    @Published var isPreparingPlayback = true
    @Published var preparationFailed = false
    @Published var playbackSpeed: Double = 1.0

    private var playbackTask: Task<Void, Never>?
    private var hasPrepared = false
    private var lastCameraProgressUpdate = Date.distantPast.timeIntervalSinceReferenceDate
    private var lastRouteSplitSegmentIndex: Int?

    private static let progressFrameNanoseconds: UInt64 = 33_333_333
    private static let cameraUpdateInterval: TimeInterval = 1.0 / 30.0
    private static let preparationTimeoutNanoseconds: UInt64 = 12_000_000_000
    private static let metersPerPlaybackSecond: CLLocationDistance = 900_000
    private static let layoverDwellFraction: Double = 0.025

    init(flight: Flight) {
        self.flight = flight
        self.flights = [flight]

        prepareInitialGeometry()
    }

    init(flights: [Flight]) {
        let sortedFlights = flights.sorted { $0.departureDate < $1.departureDate }
        self.flights = sortedFlights
        self.flight = sortedFlights.first ?? Flight()

        prepareInitialGeometry()
    }

    private func prepareInitialGeometry() {
        guard !flights.isEmpty else {
            isPreparingRoute = false
            isPreparingPlayback = false
            preparationFailed = true
            return
        }

        if let geometry = Self.makeRouteGeometry(
            from: Self.routeCoordinates(for: flights, steps: 360)
        ) {
            routeGeometry = geometry
            isPreparingRoute = false
            airportAnnotations = Self.makeAirportAnnotations(
                flights: flights,
                geometry: geometry
            )
            cameraPosition = Self.cameraPosition(
                for: geometry.markerState(at: 0).coordinate,
                distance: geometry.cameraDistance
            )
            refreshPlaybackMapContent(forceSplit: true)
        }
    }

    var isRouteReady: Bool {
        routeGeometry != nil && !isPreparingRoute
    }

    var shouldShowResumeFollowing: Bool {
        cameraFollowMode == .manual
    }

    var currentMarkerState: FlightMarkerState? {
        markerState ?? routeGeometry?.markerState(at: progress)
    }

    var isCloseDisabled: Bool {
        isPreparingPlayback && !preparationFailed
    }

    var aircraftLabel: String {
        let number = currentFlightForDisplay.displayFlightNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !number.isEmpty { return number }

        let route = routeTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return route.isEmpty
            ? "\(departureAirportCode)-\(arrivalAirportCode)"
            : route
    }

    var routeTitle: String {
        let codes = [departureAirportCode] + flights.map(\.arrivalAirportCode)
        let cleaned = codes.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        .filter { !$0.isEmpty }
        return cleaned.isEmpty ? flight.routeTitle : cleaned.joined(separator: " → ")
    }

    var departureAirportCode: String {
        flights.first?.departureAirportCode ?? flight.departureAirportCode
    }

    var arrivalAirportCode: String {
        flights.last?.arrivalAirportCode ?? flight.arrivalAirportCode
    }

    var currentFlightForDisplay: Flight {
        guard flights.count > 1,
              routeGeometry != nil else {
            return flight
        }

        return flights[Self.flightIndex(forPlaybackProgress: progress, flights: flights)]
    }

    var playbackButtonTitle: String {
        switch playbackState {
        case .playing:
            return WanderlustL10n.string("Pause", table: .trips)
        case .completed:
            return WanderlustL10n.string("Replay", table: .trips)
        case .idle, .paused:
            return WanderlustL10n.string("Play", table: .trips)
        }
    }

    var playbackButtonSystemImage: String {
        playbackState == .playing ? "pause.fill" : "play.fill"
    }

    func prepareIfNeeded() async {
        guard !hasPrepared else { return }
        hasPrepared = true
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.preparationTimeoutNanoseconds)
            await MainActor.run {
                self?.failPreparation()
            }
        }
        defer { timeoutTask.cancel() }

        if routeGeometry == nil {
            isPreparingRoute = true
        }

        await AirportDataLoader.shared.loadIfNeeded()
        guard !Task.isCancelled else { return }

        if routeGeometry == nil {
            routeGeometry = Self.makeRouteGeometry(
                from: Self.routeCoordinates(for: flights, steps: 360)
            )
        }

        guard let geometry = routeGeometry else {
            failPreparation()
            return
        }

        airportAnnotations = Self.makeAirportAnnotations(
            flights: flights,
            geometry: geometry
        )
        isPreparingRoute = false
        progress = 0
        preparationFailed = false
        refreshPlaybackMapContent(forceSplit: true)
        moveCameraToCurrentMarker(animated: false)
        withAnimation(.easeOut(duration: 0.25)) {
            isPreparingPlayback = false
        }
    }

    func retryPreparation() async {
        hasPrepared = false
        preparationFailed = false
        isPreparingPlayback = true
        await prepareIfNeeded()
    }

    func togglePlayback() {
        switch playbackState {
        case .playing:
            pause()
        case .completed:
            replay()
        case .idle, .paused:
            play()
        }
    }

    func play() {
        guard routeGeometry != nil else { return }
        guard playbackState != .playing else { return }

        if progress >= 1 {
            progress = 0
        }

        playbackTask?.cancel()
        cameraFollowMode = .following
        playbackState = .playing
        moveCameraToCurrentMarker(animated: false)

        let startProgress = progress
        let remainingFraction = max(1 - startProgress, 0)
        let baseDuration = Self.playbackDuration(for: routeGeometry?.totalDistance ?? 0)
        let duration = max(baseDuration * remainingFraction / playbackSpeed, 0.05)
        let startTime = Date().timeIntervalSinceReferenceDate

        playbackTask = Task(priority: .high) { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSinceReferenceDate - startTime
                let fraction = min(max(elapsed / duration, 0), 1)
                let newProgress = startProgress + remainingFraction * fraction

                self.applyProgress(newProgress)

                if fraction >= 1 {
                    self.progress = 1
                    self.refreshPlaybackMapContent(forceSplit: true)
                    self.playbackState = .completed
                    self.playbackTask = nil
                    return
                }

                try? await Task.sleep(nanoseconds: Self.progressFrameNanoseconds)
            }
        }
    }

    func pause() {
        playbackTask?.cancel()
        playbackTask = nil
        if playbackState == .playing {
            playbackState = .paused
            if cameraFollowMode == .following {
                moveCameraToCurrentMarker(animated: false)
            }
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        if playbackState == .playing {
            playbackState = .paused
        }
    }

    func cancelPreparation() {
        playbackTask?.cancel()
        playbackTask = nil
        hasPrepared = false
        preparationFailed = false
        isPreparingRoute = false
        isPreparingPlayback = false
    }

    func rewind() {
        playbackTask?.cancel()
        playbackTask = nil
        playbackState = .idle
        cameraFollowMode = .following
        progress = 0
        refreshPlaybackMapContent(forceSplit: true)
        moveCameraToCurrentMarker(animated: false)
    }

    func replay() {
        playbackTask?.cancel()
        playbackTask = nil
        progress = 0
        playbackState = .idle
        cameraFollowMode = .following
        refreshPlaybackMapContent(forceSplit: true)
        moveCameraToCurrentMarker(animated: false)
        play()
    }

    func seek(to value: Double) {
        playbackTask?.cancel()
        playbackTask = nil

        let clamped = min(max(value, 0), 1)
        progress = clamped
        refreshPlaybackMapContent(forceSplit: true)
        playbackState = clamped >= 1 ? .completed : .paused
        moveCameraToCurrentMarker(animated: false)
    }

    func userDidMoveMap() {
        cameraFollowMode = .manual
        pause()
    }

    func resumeFollowing() {
        cameraFollowMode = .following
        moveCameraToCurrentMarker(animated: false)
    }

    func setSpeed(_ speed: Double) {
        guard speed > 0 else { return }
        let wasPlaying = playbackState == .playing
        playbackSpeed = speed
        if wasPlaying {
            playbackTask?.cancel()
            playbackTask = nil
            playbackState = .paused
            play()
        }
    }

    private func applyProgress(_ value: Double) {
        progress = min(max(value, 0), 1)
        refreshPlaybackMapContent(forceSplit: false)
        let now = Date().timeIntervalSinceReferenceDate
        if cameraFollowMode == .following,
           now - lastCameraProgressUpdate >= Self.cameraUpdateInterval {
            moveCameraToCurrentMarker(animated: false)
        }
    }

    private func refreshPlaybackMapContent(forceSplit: Bool) {
        guard let geometry = routeGeometry else {
            markerState = nil
            traveledCoordinates = []
            remainingCoordinates = []
            return
        }

        let sample = geometry.sample(at: routeProgress)
        markerState = FlightMarkerState(
            coordinate: sample.coordinate,
            rotation: .degrees(sample.heading - 90)
        )

        guard forceSplit || sample.segmentIndex != lastRouteSplitSegmentIndex else { return }
        lastRouteSplitSegmentIndex = sample.segmentIndex
        let split = geometry.split(at: routeProgress)
        traveledCoordinates = split.traveled
        remainingCoordinates = split.remaining
    }

    private func failPreparation() {
        guard isPreparingPlayback else { return }
        playbackTask?.cancel()
        playbackTask = nil
        isPreparingRoute = false
        preparationFailed = true
        withAnimation(.easeOut(duration: 0.25)) {
            isPreparingPlayback = false
        }
    }

    private static func playbackDuration(for distance: CLLocationDistance) -> TimeInterval {
        let distanceBasedDuration = distance / metersPerPlaybackSecond
        return min(max(distanceBasedDuration, 4.0), 24.0)
    }

    private func moveCameraToCurrentMarker(animated: Bool) {
        guard let geometry = routeGeometry else { return }
        let marker = markerState ?? geometry.markerState(at: routeProgress)
        let nextPosition = Self.cameraPosition(
            for: marker.coordinate,
            distance: geometry.cameraDistance
        )

        lastCameraProgressUpdate = Date().timeIntervalSinceReferenceDate
        if animated {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                cameraPosition = nextPosition
            }
        } else {
            cameraPosition = nextPosition
        }
    }

    static func cameraPosition(
        for coordinate: CLLocationCoordinate2D,
        distance: CLLocationDistance
    ) -> MapCameraPosition {
        .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: distance,
                heading: 0,
                pitch: 0
            )
        )
    }

    private static func makeRouteGeometry(
        from coordinates: [CLLocationCoordinate2D]
    ) -> FlightRouteGeometry? {
        let valid = sanitize(coordinates)
        guard valid.count >= 2 else { return nil }
        return FlightRouteGeometry(coordinates: valid)
    }

    private static func sanitize(
        _ coordinates: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []

        for coordinate in coordinates.compactMap(validCoordinate) {
            if let previous = result.last,
               previous.distance(to: coordinate) < 1 {
                continue
            }
            result.append(coordinate)
        }
        return result
    }

    private var routeProgress: Double {
        Self.routeProgress(forPlaybackProgress: progress, flights: flights)
    }

    private static func routeCoordinates(for flights: [Flight], steps: Int) -> [CLLocationCoordinate2D] {
        let sortedFlights = flights.sorted { $0.departureDate < $1.departureDate }
        guard !sortedFlights.isEmpty else { return [] }
        let stepsPerFlight = max(steps / sortedFlights.count, 48)
        return sortedFlights.enumerated().flatMap { index, flight in
            let coordinates = flight.routeCoordinates(steps: stepsPerFlight)
            return index == 0 ? coordinates : Array(coordinates.dropFirst())
        }
    }

    private static func routeDistance(for flight: Flight) -> CLLocationDistance {
        let coordinates = sanitize(flight.routeCoordinates(steps: 24))
        guard coordinates.count >= 2 else { return 0 }
        return zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
            total + pair.0.distance(to: pair.1)
        }
    }

    private static func routeProgress(forPlaybackProgress progress: Double, flights: [Flight]) -> Double {
        let clamped = min(max(progress, 0), 1)
        guard flights.count > 1 else { return clamped }

        let distances = flights.map { max(routeDistance(for: $0), 1) }
        let totalDistance = distances.reduce(0, +)
        guard totalDistance > 0 else { return clamped }

        let dwellCount = max(flights.count - 1, 0)
        let totalDwell = min(Double(dwellCount) * layoverDwellFraction, 0.18)
        let movingTimeline = max(1 - totalDwell, 0.1)

        var timelineCursor = 0.0
        var routeCursor = 0.0

        for index in distances.indices {
            let routeShare = distances[index] / totalDistance
            let movementDuration = routeShare * movingTimeline
            let movementEnd = timelineCursor + movementDuration

            if clamped <= movementEnd {
                let local = movementDuration > 0
                    ? (clamped - timelineCursor) / movementDuration
                    : 1
                return routeCursor + routeShare * min(max(local, 0), 1)
            }

            timelineCursor = movementEnd
            routeCursor += routeShare

            if index < dwellCount {
                let dwellEnd = timelineCursor + layoverDwellFraction
                if clamped <= dwellEnd {
                    return routeCursor
                }
                timelineCursor = dwellEnd
            }
        }

        return 1
    }

    private static func flightIndex(forPlaybackProgress progress: Double, flights: [Flight]) -> Int {
        let clamped = min(max(progress, 0), 1)
        guard flights.count > 1 else { return 0 }

        let distances = flights.map { max(routeDistance(for: $0), 1) }
        let totalDistance = distances.reduce(0, +)
        guard totalDistance > 0 else { return 0 }

        let dwellCount = max(flights.count - 1, 0)
        let totalDwell = min(Double(dwellCount) * layoverDwellFraction, 0.18)
        let movingTimeline = max(1 - totalDwell, 0.1)
        var timelineCursor = 0.0

        for index in distances.indices {
            let movementDuration = (distances[index] / totalDistance) * movingTimeline
            let movementEnd = timelineCursor + movementDuration
            if clamped <= movementEnd {
                return index
            }

            timelineCursor = movementEnd

            if index < dwellCount {
                let dwellEnd = timelineCursor + layoverDwellFraction
                if clamped <= dwellEnd {
                    return min(index + 1, flights.count - 1)
                }
                timelineCursor = dwellEnd
            }
        }

        return flights.count - 1
    }

    nonisolated static func validCoordinate(
        _ coordinate: CLLocationCoordinate2D?
    ) -> CLLocationCoordinate2D? {
        guard let coordinate,
              CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude)
        else { return nil }
        return coordinate
    }

    private static func fallbackGreatCircleRoute(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        steps: Int
    ) -> [CLLocationCoordinate2D] {
        let startVector = UnitVector(coordinate: start)
        let endVector = UnitVector(coordinate: end)
        let dot = min(max(startVector.dot(endVector), -1), 1)
        let omega = acos(dot)

        guard omega.isFinite, omega > 0.000_001 else {
            return [start, end]
        }

        let sineOmega = sin(omega)
        return (0...steps).map { step in
            let t = Double(step) / Double(max(steps, 1))
            let firstWeight = sin((1 - t) * omega) / sineOmega
            let secondWeight = sin(t * omega) / sineOmega
            return UnitVector(
                x: firstWeight * startVector.x + secondWeight * endVector.x,
                y: firstWeight * startVector.y + secondWeight * endVector.y,
                z: firstWeight * startVector.z + secondWeight * endVector.z
            ).coordinate
        }
    }

    static func makeAirportAnnotations(
        flight: Flight,
        geometry: FlightRouteGeometry,
        departure: CLLocationCoordinate2D?,
        arrival: CLLocationCoordinate2D?
    ) -> [FlightAirportAnnotation] {
        var annotations: [FlightAirportAnnotation] = []

        if let departure = validCoordinate(departure) {
            annotations.append(
                FlightAirportAnnotation(
                    id: "departure-\(flight.id.uuidString)",
                    name: airportDisplayName(
                        localizedName: flight.localizedDepartureAirportName,
                        englishName: flight.effectiveLegs.first?.departureAirportName ?? flight.departureAirportName,
                        code: flight.departureAirportCode
                    ),
                    code: flight.departureAirportCode,
                    coordinate: departure,
                    labelPlacement: labelPlacement(
                        airport: departure,
                        routeNeighbor: geometry.coordinates.dropFirst().first
                    )
                )
            )
        }

        if let arrival = validCoordinate(arrival) {
            annotations.append(
                FlightAirportAnnotation(
                    id: "arrival-\(flight.id.uuidString)",
                    name: airportDisplayName(
                        localizedName: flight.localizedArrivalAirportName,
                        englishName: flight.effectiveLegs.last?.arrivalAirportName ?? flight.arrivalAirportName,
                        code: flight.arrivalAirportCode
                    ),
                    code: flight.arrivalAirportCode,
                    coordinate: arrival,
                    labelPlacement: labelPlacement(
                        airport: arrival,
                        routeNeighbor: geometry.coordinates.dropLast().last
                    )
                )
            )
        }

        for leg in flight.effectiveLegs.dropLast() {
            guard let coordinate = validCoordinate(leg.arrivalCoordinate) else {
                continue
            }
            annotations.append(
                FlightAirportAnnotation(
                    id: "layover-\(leg.id.uuidString)",
                    name: airportDisplayName(
                        localizedName: leg.localizedArrivalAirportName,
                        englishName: leg.arrivalAirportName,
                        code: leg.arrivalAirportCode
                    ),
                    code: leg.arrivalAirportCode,
                    coordinate: coordinate,
                    labelPlacement: labelPlacement(
                        airport: coordinate,
                        routeNeighbor: validCoordinate(leg.departureCoordinate)
                    )
                )
            )
        }

        return annotations
    }

    static func makeAirportAnnotations(
        flights: [Flight],
        geometry: FlightRouteGeometry
    ) -> [FlightAirportAnnotation] {
        var annotations: [FlightAirportAnnotation] = []
        var seenKeys: Set<String> = []

        func appendAirport(id: String, name: String, code: String, coordinate: CLLocationCoordinate2D) {
            guard let coordinate = validCoordinate(coordinate) else { return }
            let cleanedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let key = cleanedCode.isEmpty
                ? "\(coordinate.latitude.rounded()):\(coordinate.longitude.rounded())"
                : cleanedCode
            guard seenKeys.insert(key).inserted else { return }

            let neighbor = nearestRouteNeighbor(to: coordinate, in: geometry.coordinates)
            annotations.append(
                FlightAirportAnnotation(
                    id: id,
                    name: airportDisplayName(
                        localizedName: name,
                        englishName: name,
                        code: cleanedCode
                    ),
                    code: cleanedCode,
                    coordinate: coordinate,
                    labelPlacement: labelPlacement(
                        airport: coordinate,
                        routeNeighbor: neighbor
                    )
                )
            )
        }

        for flight in flights.sorted(by: { $0.departureDate < $1.departureDate }) {
            if let firstLeg = flight.effectiveLegs.first {
                appendAirport(
                    id: "departure-\(flight.id.uuidString)",
                    name: firstLeg.localizedDepartureAirportName,
                    code: firstLeg.departureAirportCode,
                    coordinate: firstLeg.departureCoordinate
                )
            }

            for leg in flight.effectiveLegs {
                appendAirport(
                    id: "arrival-\(leg.id.uuidString)",
                    name: leg.localizedArrivalAirportName,
                    code: leg.arrivalAirportCode,
                    coordinate: leg.arrivalCoordinate
                )
            }
        }

        return annotations
    }

    private static func nearestRouteNeighbor(
        to airport: CLLocationCoordinate2D,
        in coordinates: [CLLocationCoordinate2D]
    ) -> CLLocationCoordinate2D? {
        guard coordinates.count > 1 else { return nil }
        let nearestIndex = coordinates.indices.min {
            coordinates[$0].distance(to: airport) < coordinates[$1].distance(to: airport)
        } ?? 0
        if nearestIndex + 1 < coordinates.count {
            return coordinates[nearestIndex + 1]
        }
        if nearestIndex > 0 {
            return coordinates[nearestIndex - 1]
        }
        return nil
    }

    static func airportDisplayName(localizedName: String, englishName: String, code: String) -> String {
        let cleanedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let localized = localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localized.isEmpty, localized.localizedCaseInsensitiveCompare(cleanedCode) != .orderedSame {
            return localized
        }

        let english = englishName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !english.isEmpty { return english }

        return cleanedCode
    }

    private static func labelPlacement(
        airport: CLLocationCoordinate2D,
        routeNeighbor: CLLocationCoordinate2D?
    ) -> AirportLabelPlacement {
        guard let neighbor = validCoordinate(routeNeighbor) else {
            return .left
        }

        let longitudeDelta = adjustedLongitudeDifference(
            from: airport.longitude,
            to: neighbor.longitude
        )
        let averageLatitude = (airport.latitude + neighbor.latitude) / 2
        let projectedX = longitudeDelta * cos(averageLatitude * .pi / 180)
        return projectedX >= 0 ? .left : .right
    }

    private static func adjustedLongitudeDifference(
        from start: Double,
        to end: Double
    ) -> Double {
        var difference = end - start
        if difference > 180 {
            difference -= 360
        } else if difference < -180 {
            difference += 360
        }
        return difference
    }
}

// MARK: - Route geometry

struct FlightRouteGeometry {
    let coordinates: [CLLocationCoordinate2D]
    let cumulativeDistances: [CLLocationDistance]
    let totalDistance: CLLocationDistance
    let cameraDistance: CLLocationDistance
    let routeCenter: CLLocationCoordinate2D

    init(coordinates: [CLLocationCoordinate2D]) {
        self.coordinates = coordinates

        var distances: [CLLocationDistance] = [0]
        var accumulated: CLLocationDistance = 0
        var minLatitude = 90.0
        var maxLatitude = -90.0
        var minLongitude = 180.0
        var maxLongitude = -180.0

        for coordinate in coordinates {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        for pair in zip(coordinates, coordinates.dropFirst()) {
            accumulated += pair.0.distance(to: pair.1)
            distances.append(accumulated)
        }

        cumulativeDistances = distances
        totalDistance = max(accumulated, 1)
        cameraDistance = min(max(totalDistance * 1.05, 1_200_000), 10_500_000)
        routeCenter = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
    }

    func markerState(at progress: Double) -> FlightMarkerState {
        let sample = sample(at: progress)
        return FlightMarkerState(
            coordinate: sample.coordinate,
            rotation: .degrees(sample.heading - 90)
        )
    }

    func split(at progress: Double) -> (
        traveled: [CLLocationCoordinate2D],
        remaining: [CLLocationCoordinate2D]
    ) {
        guard coordinates.count >= 2 else {
            return (coordinates, coordinates)
        }

        let sample = sample(at: progress)
        let segmentIndex = sample.segmentIndex

        var traveled = Array(coordinates.prefix(segmentIndex + 1))
        if traveled.last?.distance(to: sample.coordinate) ?? .infinity > 0.5 {
            traveled.append(sample.coordinate)
        }

        var remaining: [CLLocationCoordinate2D] = [sample.coordinate]
        remaining.append(contentsOf: coordinates.suffix(from: min(segmentIndex + 1, coordinates.count - 1)))

        return (traveled, remaining)
    }

    func sample(at progress: Double) -> RouteSample {
        guard coordinates.count >= 2 else {
            return RouteSample(
                coordinate: coordinates.first ?? CLLocationCoordinate2D(),
                heading: 0,
                segmentIndex: 0
            )
        }

        let clamped = min(max(progress, 0), 1)
        let targetDistance = clamped * totalDistance
        let located = coordinate(atDistance: targetDistance)
        let heading = smoothedHeading(atDistance: targetDistance, fallbackSegmentIndex: located.segmentIndex)

        return RouteSample(
            coordinate: located.coordinate,
            heading: heading,
            segmentIndex: located.segmentIndex
        )
    }

    private func coordinate(atDistance distance: CLLocationDistance) -> (coordinate: CLLocationCoordinate2D, segmentIndex: Int) {
        let target = min(max(distance, 0), totalDistance)
        let index = segmentIndex(for: target)
        let startDistance = cumulativeDistances[index]
        let endDistance = cumulativeDistances[index + 1]
        let segmentDistance = max(endDistance - startDistance, 1)
        let fraction = min(max((target - startDistance) / segmentDistance, 0), 1)
        let start = coordinates[index]
        let end = coordinates[index + 1]
        return (start.interpolated(toward: end, fraction: fraction), index)
    }

    private func smoothedHeading(atDistance distance: CLLocationDistance, fallbackSegmentIndex: Int) -> Double {
        let window = min(max(totalDistance / 720, 1_000), 50_000)
        let before = coordinate(atDistance: max(distance - window, 0)).coordinate
        let after = coordinate(atDistance: min(distance + window, totalDistance)).coordinate

        if before.distance(to: after) > 1 {
            return before.bearing(to: after)
        }

        let start = coordinates[fallbackSegmentIndex]
        let end = coordinates[min(fallbackSegmentIndex + 1, coordinates.count - 1)]
        return start.bearing(to: end)
    }

    private func segmentIndex(for distance: CLLocationDistance) -> Int {
        var lower = 0
        var upper = cumulativeDistances.count - 1

        while lower < upper {
            let middle = (lower + upper) / 2
            if cumulativeDistances[middle] < distance {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        return min(max(lower - 1, 0), coordinates.count - 2)
    }
}

struct RouteSample {
    let coordinate: CLLocationCoordinate2D
    let heading: Double
    let segmentIndex: Int
}

struct FlightMarkerState {
    let coordinate: CLLocationCoordinate2D
    let rotation: Angle
}

// MARK: - Airport annotation model

struct FlightAirportAnnotation: Identifiable {
    let id: String
    let name: String
    let code: String
    let coordinate: CLLocationCoordinate2D
    let labelPlacement: AirportLabelPlacement
}

enum AirportLabelPlacement {
    case left
    case right
}

// MARK: - Coordinate math

struct UnitVector {
    let x: Double
    let y: Double
    let z: Double

    init(x: Double, y: Double, z: Double) {
        let length = sqrt(x * x + y * y + z * z)
        if length > 0 {
            self.x = x / length
            self.y = y / length
            self.z = z / length
        } else {
            self.x = 1
            self.y = 0
            self.z = 0
        }
    }

    init(coordinate: CLLocationCoordinate2D) {
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180
        self.init(
            x: cos(latitude) * cos(longitude),
            y: cos(latitude) * sin(longitude),
            z: sin(latitude)
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
            longitude: atan2(y, x) * 180 / .pi
        )
    }

    func dot(_ other: UnitVector) -> Double {
        x * other.x + y * other.y + z * other.z
    }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(
                from: CLLocation(
                    latitude: other.latitude,
                    longitude: other.longitude
                )
            )
    }

    func interpolated(
        toward other: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        let clamped = min(max(fraction, 0), 1)
        var longitudeDifference = other.longitude - longitude
        if longitudeDifference > 180 {
            longitudeDifference -= 360
        } else if longitudeDifference < -180 {
            longitudeDifference += 360
        }

        var resultLongitude = longitude + longitudeDifference * clamped
        if resultLongitude > 180 {
            resultLongitude -= 360
        } else if resultLongitude < -180 {
            resultLongitude += 360
        }

        return CLLocationCoordinate2D(
            latitude: latitude + (other.latitude - latitude) * clamped,
            longitude: resultLongitude
        )
    }

    func bearing(to other: CLLocationCoordinate2D) -> Double {
        let latitude1 = latitude * .pi / 180
        let latitude2 = other.latitude * .pi / 180
        var longitudeDelta = other.longitude - longitude
        if longitudeDelta > 180 {
            longitudeDelta -= 360
        } else if longitudeDelta < -180 {
            longitudeDelta += 360
        }
        longitudeDelta *= .pi / 180

        let y = sin(longitudeDelta) * cos(latitude2)
        let x = cos(latitude1) * sin(latitude2)
            - sin(latitude1) * cos(latitude2) * cos(longitudeDelta)
        return (atan2(y, x) * 180 / .pi + 360)
            .truncatingRemainder(dividingBy: 360)
    }
}
