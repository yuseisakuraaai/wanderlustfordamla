import Foundation
import Combine

@MainActor
final class SearchIndexStore: ObservableObject {
    static let shared = SearchIndexStore()

    @Published private(set) var isWarmed = false
    @Published private(set) var lastWarmDuration: TimeInterval = 0
    @Published private(set) var lastError: String?

    private init() {}

    func warmIfNeeded() async {
        guard !isWarmed else { return }
        let start = CFAbsoluteTimeGetCurrent()
        lastWarmDuration = CFAbsoluteTimeGetCurrent() - start
        isWarmed = true
        lastError = nil
        WanderlustDiagnostics.info("search indexes stay cold until first use", category: .search)
    }

    func searchCities(query: String, countryCode: String? = nil, limit: Int = 10) async -> [WanderlustCity] {
        do {
            return try await WanderlustStaticDataStore.shared.searchCities(
                query: query,
                countryCode: countryCode,
                limit: limit
            )
        } catch {
            WanderlustDiagnostics.warning("SQLite city search unavailable: \(error.localizedDescription)", category: .search)
            await CityDataLoader.shared.loadIfNeeded()
            return CityDataLoader.shared.search(query: query, countryCode: countryCode, limit: limit)
        }
    }

    func searchAirports(query: String, countryCode: String? = nil, commercialOnly: Bool = true, limit: Int = 10) async -> [Airport] {
        do {
            let normalizedCountry = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            let fetchLimit = normalizedCountry.isEmpty ? limit : limit + 50
            let results = try await WanderlustStaticDataStore.shared.searchAirports(query: query, limit: fetchLimit)
            return results.filter { airport in
                (normalizedCountry.isEmpty || airport.normalizedCountryCode == normalizedCountry) &&
                (!commercialOnly || airport.scheduledService)
            }
            .prefix(limit)
            .map { $0 }
        } catch {
            WanderlustDiagnostics.warning("SQLite airport search unavailable: \(error.localizedDescription)", category: .search)
            await AirportDataLoader.shared.loadIfNeeded()
            return AirportDataLoader.shared.search(query: query, countryCode: countryCode, commercialOnly: commercialOnly, limit: limit)
        }
    }

    func searchAirlines(query: String, activeOnly: Bool = true, limit: Int = 10) async -> [Airline] {
        do {
            let results = try await WanderlustStaticDataStore.shared.searchAirlines(query: query, limit: limit)
            return activeOnly ? results.filter(\.isActive) : results
        } catch {
            WanderlustDiagnostics.warning("SQLite airline search unavailable: \(error.localizedDescription)", category: .search)
            await AirlineDataLoader.shared.loadIfNeeded()
            return AirlineDataLoader.shared.search(query: query, activeOnly: activeOnly, limit: limit)
        }
    }

    func directRoute(from origin: String, to destination: String) async -> WanderlustRoute? {
        do {
            return try await WanderlustStaticDataStore.shared.directRoute(from: origin, to: destination)
        } catch {
            WanderlustDiagnostics.warning("SQLite route lookup unavailable: \(error.localizedDescription)", category: .search)
            await RouteDataStore.shared.loadIfNeeded()
            return RouteDataStore.shared.directRoute(from: origin, to: destination)
        }
    }

    func connectionCandidates(from origin: String, to destination: String, limit: Int = 10) async -> [WanderlustRouteConnectionCandidate] {
        await RouteDataStore.shared.loadIfNeeded()
        await AirportDataLoader.shared.loadIfNeeded()
        return RouteDataStore.shared.connectionCandidates(
            from: origin,
            to: destination,
            airportLookup: { code in
                AirportDataLoader.shared.airport(withIATACode: code) ??
                AirportDataLoader.shared.airport(withICAOCode: code) ??
                AirportDataLoader.shared.airport(withID: code)
            },
            limit: limit
        )
    }
}
