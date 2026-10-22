import CoreLocation
import Foundation

struct FlightRouteValidation: Equatable {
    let routeExists: Bool
    let airlineCodes: [String]

    static let unavailable = FlightRouteValidation(routeExists: false, airlineCodes: [])
}

protocol FlightDataProvider {
    func validateRoute(origin: String, destination: String) async -> FlightRouteValidation
    func airlineCandidates(origin: String, destination: String) async -> [Airline]
    func flightNumberSuggestions(origin: String, destination: String, airlineCode: String?) async -> [String]
}

struct LocalRouteDataProvider: FlightDataProvider {
    func validateRoute(origin: String, destination: String) async -> FlightRouteValidation {
        guard let route = try? await WanderlustStaticDataStore.shared.directRoute(from: origin, to: destination) else {
            return .unavailable
        }
        return FlightRouteValidation(routeExists: true, airlineCodes: route.airlines)
    }

    func airlineCandidates(origin: String, destination: String) async -> [Airline] {
        let validation = await validateRoute(origin: origin, destination: destination)
        var airlines: [Airline] = []
        for code in validation.airlineCodes {
            if let airline = try? await WanderlustStaticDataStore.shared.airline(matching: code) {
                airlines.append(airline)
            }
        }
        return airlines.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func flightNumberSuggestions(origin: String, destination: String, airlineCode: String?) async -> [String] {
        []
    }
}

struct RemoteFlightDataProvider: FlightDataProvider {
    func validateRoute(origin: String, destination: String) async -> FlightRouteValidation {
        .unavailable
    }

    func airlineCandidates(origin: String, destination: String) async -> [Airline] {
        []
    }

    func flightNumberSuggestions(origin: String, destination: String, airlineCode: String?) async -> [String] {
        []
    }
}

protocol RouteGeometryProvider {
    func coordinates(for flight: Flight) async -> [CLLocationCoordinate2D]
}

struct ApproximateRouteGeometryProvider: RouteGeometryProvider {
    func coordinates(for flight: Flight) async -> [CLLocationCoordinate2D] {
        flight.routeCoordinates()
    }
}

struct LiveRouteGeometryProvider: RouteGeometryProvider {
    func coordinates(for flight: Flight) async -> [CLLocationCoordinate2D] {
        []
    }
}
