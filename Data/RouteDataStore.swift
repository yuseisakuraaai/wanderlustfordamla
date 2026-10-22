import Foundation
import Combine
import CoreLocation

struct WanderlustRoute: Codable, Hashable, Sendable {
    let from: String
    let to: String
    let airlines: [String]

    var normalizedFrom: String { Self.normalizedCode(from) }
    var normalizedTo: String { Self.normalizedCode(to) }

    private static func normalizedCode(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

struct WanderlustRouteConnectionCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let origin: String
    let connection: String
    let destination: String
    let firstLegAirlines: [String]
    let secondLegAirlines: [String]
    let sharedAirlines: [String]
    let estimatedDistanceMeters: CLLocationDistance

    var airportCodes: [String] { [origin, connection, destination] }

    var preferredAirlineCodes: [String] {
        let shared = sharedAirlines
        guard shared.isEmpty else { return shared }
        return Array((firstLegAirlines + secondLegAirlines).uniquedPreservingOrder().prefix(6))
    }
}

@MainActor
final class RouteDataStore: ObservableObject {
    static let shared = RouteDataStore()

    @Published private(set) var isLoaded = false
    @Published private(set) var loadingError: String?
    @Published private(set) var routeCount = 0
    @Published private(set) var airportCount = 0
    @Published private(set) var lastLoadDuration: TimeInterval = 0
    @Published private(set) var estimatedMemoryBytes = 0

    private var routesByOrigin: [String: [WanderlustRoute]] = [:]
    private var routeByPair: [String: WanderlustRoute] = [:]
    private var routesByDestination: [String: [WanderlustRoute]] = [:]
    private var routesByAirline: [String: [WanderlustRoute]] = [:]
    private var loadTask: Task<RouteIndexes, Error>?

    private init() {}

    func loadIfNeeded() async {
        guard !isLoaded else { return }
        if let loadTask {
            do {
                apply(try await loadTask.value)
            } catch {
                apply(error: error)
            }
            return
        }

        loadingError = nil
        let task = Task.detached(priority: .utility) {
            try Self.loadRoutesFromBundle()
        }
        loadTask = task

        do {
            apply(try await task.value)
        } catch {
            apply(error: error)
        }

        loadTask = nil
    }

    func releaseMemory() {
        loadTask?.cancel()
        loadTask = nil
        routesByOrigin = [:]
        routeByPair = [:]
        routesByDestination = [:]
        routesByAirline = [:]
        routeCount = 0
        airportCount = 0
        lastLoadDuration = 0
        estimatedMemoryBytes = 0
        loadingError = nil
        isLoaded = false
    }

    func directRoute(from origin: String, to destination: String) -> WanderlustRoute? {
        routeByPair[pairKey(origin, destination)]
    }

    func airlineCodes(from origin: String, to destination: String) -> [String] {
        directRoute(from: origin, to: destination)?.airlines ?? []
    }

    func routes(from origin: String) -> [WanderlustRoute] {
        routesByOrigin[normalizedCode(origin)] ?? []
    }

    func routes(to destination: String) -> [WanderlustRoute] {
        routesByDestination[normalizedCode(destination)] ?? []
    }

    func routes(operatedBy airlineCode: String) -> [WanderlustRoute] {
        routesByAirline[normalizedCode(airlineCode)] ?? []
    }

    func connectionCandidates(
        from origin: String,
        to destination: String,
        airportLookup: (String) -> Airport?,
        limit: Int = 10
    ) -> [WanderlustRouteConnectionCandidate] {
        let originCode = normalizedCode(origin)
        let destinationCode = normalizedCode(destination)
        guard !originCode.isEmpty,
              !destinationCode.isEmpty,
              originCode != destinationCode else {
            return []
        }

        return (routesByOrigin[originCode] ?? [])
            .compactMap { firstLeg -> WanderlustRouteConnectionCandidate? in
                let connection = firstLeg.normalizedTo
                guard connection != originCode,
                      connection != destinationCode,
                      let secondLeg = routeByPair[pairKey(connection, destinationCode)] else {
                    return nil
                }

                let firstAirlines = firstLeg.airlines.map(normalizedCode).filter { !$0.isEmpty }
                let secondAirlines = secondLeg.airlines.map(normalizedCode).filter { !$0.isEmpty }
                let shared = firstAirlines.filter { secondAirlines.contains($0) }.uniquedPreservingOrder()
                let distance = Self.totalDistance(
                    airportCodes: [originCode, connection, destinationCode],
                    airportLookup: airportLookup
                )

                return WanderlustRouteConnectionCandidate(
                    id: "\(originCode)-\(connection)-\(destinationCode)",
                    origin: originCode,
                    connection: connection,
                    destination: destinationCode,
                    firstLegAirlines: firstAirlines,
                    secondLegAirlines: secondAirlines,
                    sharedAirlines: shared,
                    estimatedDistanceMeters: distance
                )
            }
            .sorted { first, second in
                if first.sharedAirlines.isEmpty != second.sharedAirlines.isEmpty {
                    return !first.sharedAirlines.isEmpty
                }
                if first.estimatedDistanceMeters != second.estimatedDistanceMeters {
                    return first.estimatedDistanceMeters < second.estimatedDistanceMeters
                }
                return first.connection < second.connection
            }
            .prefix(max(1, limit))
            .map { $0 }
    }

    private func apply(_ indexes: RouteIndexes) {
        routesByOrigin = indexes.routesByOrigin
        routeByPair = indexes.routeByPair
        routesByDestination = indexes.routesByDestination
        routesByAirline = indexes.routesByAirline
        routeCount = indexes.routeCount
        airportCount = indexes.airportCount
        lastLoadDuration = indexes.loadDuration
        estimatedMemoryBytes = indexes.estimatedMemoryBytes
        loadingError = nil
        isLoaded = true
    }

    private func apply(error: Error) {
        routesByOrigin = [:]
        routeByPair = [:]
        routesByDestination = [:]
        routesByAirline = [:]
        routeCount = 0
        airportCount = 0
        lastLoadDuration = 0
        estimatedMemoryBytes = 0
        loadingError = error.localizedDescription
        isLoaded = false
        #if DEBUG
        WanderlustDiagnostics.error(
            error,
            category: .route,
            message: "route data load failed"
        )
        #endif
    }

    private nonisolated static func loadRoutesFromBundle() throws -> RouteIndexes {
        let start = CFAbsoluteTimeGetCurrent()
        guard let url = Bundle.main.url(forResource: "routes", withExtension: "json") else {
            throw RouteDataStoreError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw RouteDataStoreError.emptyFile }

        let payload = try JSONDecoder().decode(RoutePayload.self, from: data)
        var routesByOrigin: [String: [WanderlustRoute]] = [:]
        var routeByPair: [String: WanderlustRoute] = [:]
        var routesByDestination: [String: [WanderlustRoute]] = [:]
        var routesByAirline: [String: [WanderlustRoute]] = [:]

        for rawRoute in payload.routes {
            let route = WanderlustRoute(
                from: normalizedCode(rawRoute.from),
                to: normalizedCode(rawRoute.to),
                airlines: rawRoute.airlines.map(normalizedCode).filter { !$0.isEmpty }.uniquedPreservingOrder()
            )
            guard !route.from.isEmpty, !route.to.isEmpty else { continue }
            routesByOrigin[route.from, default: []].append(route)
            routeByPair[pairKey(route.from, route.to)] = route
            routesByDestination[route.to, default: []].append(route)
            for airline in route.airlines {
                routesByAirline[airline, default: []].append(route)
            }
        }

        let routeCount = routeByPair.count
        let airportCount = Set(payload.routes.flatMap { [normalizedCode($0.from), normalizedCode($0.to)] }).filter { !$0.isEmpty }.count
        let estimatedMemoryBytes = routeCount * 180 + routesByAirline.values.reduce(0) { $0 + $1.count * 32 }

        let indexes = RouteIndexes(
            routesByOrigin: routesByOrigin,
            routeByPair: routeByPair,
            routesByDestination: routesByDestination,
            routesByAirline: routesByAirline,
            routeCount: routeCount,
            airportCount: payload.airportCount ?? airportCount,
            loadDuration: CFAbsoluteTimeGetCurrent() - start,
            estimatedMemoryBytes: estimatedMemoryBytes
        )
        return indexes
    }

    private nonisolated static func normalizedCode(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private nonisolated func normalizedCode(_ value: String) -> String {
        Self.normalizedCode(value)
    }

    private nonisolated static func pairKey(_ origin: String, _ destination: String) -> String {
        "\(normalizedCode(origin))-\(normalizedCode(destination))"
    }

    private nonisolated func pairKey(_ origin: String, _ destination: String) -> String {
        Self.pairKey(origin, destination)
    }

    private nonisolated static func totalDistance(
        airportCodes: [String],
        airportLookup: (String) -> Airport?
    ) -> CLLocationDistance {
        var total: CLLocationDistance = 0
        for pair in zip(airportCodes, airportCodes.dropFirst()) {
            guard let origin = airportLookup(pair.0),
                  let destination = airportLookup(pair.1) else {
                total += 99_000_000
                continue
            }
            let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
            total += originLocation.distance(from: destinationLocation)
        }
        return total
    }
}

private struct RoutePayload: Decodable {
    let schemaVersion: Int?
    let airportCount: Int?
    let routeCount: Int?
    let routes: [WanderlustRoute]

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
        airportCount = try container.decodeIfPresent(Int.self, forKey: .airportCount)
        routeCount = try container.decodeIfPresent(Int.self, forKey: .routeCount)
        routes = try container.decode([WanderlustRoute].self, forKey: .routes)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case airportCount
        case routeCount
        case routes
    }
}

private struct RouteIndexes: Sendable {
    let routesByOrigin: [String: [WanderlustRoute]]
    let routeByPair: [String: WanderlustRoute]
    let routesByDestination: [String: [WanderlustRoute]]
    let routesByAirline: [String: [WanderlustRoute]]
    let routeCount: Int
    let airportCount: Int
    let loadDuration: TimeInterval
    let estimatedMemoryBytes: Int
}

private struct RouteIndexCachePayload: Codable, Sendable {
    let routesByOrigin: [String: [WanderlustRoute]]
    let routeByPair: [String: WanderlustRoute]
    let routesByDestination: [String: [WanderlustRoute]]
    let routesByAirline: [String: [WanderlustRoute]]
    let routeCount: Int
    let airportCount: Int
    let estimatedMemoryBytes: Int

    nonisolated init(indexes: RouteIndexes) {
        routesByOrigin = indexes.routesByOrigin
        routeByPair = indexes.routeByPair
        routesByDestination = indexes.routesByDestination
        routesByAirline = indexes.routesByAirline
        routeCount = indexes.routeCount
        airportCount = indexes.airportCount
        estimatedMemoryBytes = indexes.estimatedMemoryBytes
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        routesByOrigin = try container.decode([String: [WanderlustRoute]].self, forKey: .routesByOrigin)
        routeByPair = try container.decode([String: WanderlustRoute].self, forKey: .routeByPair)
        routesByDestination = try container.decode([String: [WanderlustRoute]].self, forKey: .routesByDestination)
        routesByAirline = try container.decode([String: [WanderlustRoute]].self, forKey: .routesByAirline)
        routeCount = try container.decode(Int.self, forKey: .routeCount)
        airportCount = try container.decode(Int.self, forKey: .airportCount)
        estimatedMemoryBytes = try container.decode(Int.self, forKey: .estimatedMemoryBytes)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(routesByOrigin, forKey: .routesByOrigin)
        try container.encode(routeByPair, forKey: .routeByPair)
        try container.encode(routesByDestination, forKey: .routesByDestination)
        try container.encode(routesByAirline, forKey: .routesByAirline)
        try container.encode(routeCount, forKey: .routeCount)
        try container.encode(airportCount, forKey: .airportCount)
        try container.encode(estimatedMemoryBytes, forKey: .estimatedMemoryBytes)
    }

    nonisolated func indexes(loadDuration: TimeInterval) -> RouteIndexes {
        RouteIndexes(
            routesByOrigin: routesByOrigin,
            routeByPair: routeByPair,
            routesByDestination: routesByDestination,
            routesByAirline: routesByAirline,
            routeCount: routeCount,
            airportCount: airportCount,
            loadDuration: loadDuration,
            estimatedMemoryBytes: estimatedMemoryBytes
        )
    }

    private enum CodingKeys: String, CodingKey {
        case routesByOrigin
        case routeByPair
        case routesByDestination
        case routesByAirline
        case routeCount
        case airportCount
        case estimatedMemoryBytes
    }
}

enum RouteDataStoreError: LocalizedError {
    case fileNotFound
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            "routes.json was not found in the app bundle."
        case .emptyFile:
            "The route data file is empty."
        }
    }
}

private extension Array where Element: Hashable {
    nonisolated func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
