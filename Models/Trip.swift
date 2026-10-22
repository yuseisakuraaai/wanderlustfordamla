import Foundation
import CoreLocation

enum WanderlustDateFormatter {
    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
    }

    static func dateRange(start: Date, end: Date) -> String {
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return date(start)
        }

        return "\(date(start)) – \(date(end))"
    }

    static func yearMonth(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        let year = components.year ?? Calendar.current.component(.year, from: date)
        let month = components.month ?? Calendar.current.component(.month, from: date)
        return String(format: "%04d.%02d", year, month)
    }
}

struct VisitPeriod: Identifiable, Codable, Hashable {
    let id: UUID
    var startDate: Date
    var endDate: Date

    nonisolated init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = max(endDate, startDate)
    }

}

enum CityVisitDatePlanner {
    static func normalizedPeriod(
        _ period: VisitPeriod,
        tripStart: Date,
        tripEnd: Date,
        calendar: Calendar = .current
    ) -> VisitPeriod {
        let effectiveStart = calendar.startOfDay(for: min(tripStart, tripEnd))
        let effectiveEnd = calendar.startOfDay(for: max(tripStart, tripEnd))
        let requestedStart = calendar.startOfDay(for: period.startDate)
        let requestedEnd = calendar.startOfDay(for: period.endDate)
        let start = min(max(requestedStart, effectiveStart), effectiveEnd)
        let end = min(max(requestedEnd, start), effectiveEnd)
        return VisitPeriod(id: period.id, startDate: start, endDate: end)
    }

    static func normalizedCities(
        _ cities: [VisitedCity],
        tripStart: Date,
        tripEnd: Date,
        calendar: Calendar = .current
    ) -> [VisitedCity] {
        cities
            .map { city in
                var copy = city
                copy.periods = copy.periods
                    .map {
                        normalizedPeriod(
                            $0,
                            tripStart: tripStart,
                            tripEnd: tripEnd,
                            calendar: calendar
                        )
                    }
                    .sorted { $0.startDate < $1.startDate }
                return copy
            }
            .sortedByVisitDate()
    }

    static func earliestAvailablePeriod(
        in cities: [VisitedCity],
        tripStart: Date,
        tripEnd: Date,
        excluding cityID: UUID? = nil,
        periodID: UUID? = nil,
        calendar: Calendar = .current
    ) -> VisitPeriod? {
        guard tripEnd >= tripStart else { return nil }
        let start = calendar.startOfDay(for: tripStart)
        return VisitPeriod(startDate: start, endDate: start)
    }

    static func hasAnyAvailableDate(
        in cities: [VisitedCity],
        tripStart: Date,
        tripEnd: Date,
        excluding cityID: UUID? = nil,
        calendar: Calendar = .current
    ) -> Bool {
        tripEnd >= tripStart
    }
}

extension Array where Element == VisitedCity {
    func sortedByVisitDate() -> [VisitedCity] {
        sorted {
            let first = $0.earliestVisitDate ?? .distantFuture
            let second = $1.earliestVisitDate ?? .distantFuture
            if first != second {
                return first < second
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: - Transportation

enum TransportationType: String, Codable, Hashable, CaseIterable, Identifiable {
    case airplane
    case train
    case bus
    case car
    case bicycle
    case walking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .airplane:
            return WanderlustL10n.string("Airplane", table: .trips)
        case .train:
            return WanderlustL10n.string("Train", table: .trips)
        case .bus:
            return WanderlustL10n.string("Bus", table: .trips, fallback: "Bus")
        case .car:
            return WanderlustL10n.string("Car", table: .trips)
        case .bicycle:
            return WanderlustL10n.string("Bicycle", table: .trips)
        case .walking:
            return WanderlustL10n.string("Walking", table: .trips)
        }
    }

    var systemImage: String {
        switch self {
        case .airplane:
            return "airplane"
        case .train:
            return "train.side.front.car"
        case .bus:
            return "bus.fill"
        case .car:
            return "car.fill"
        case .bicycle:
            return "bicycle"
        case .walking:
            return "figure.walk"
        }
    }

    var sortOrder: Int {
        switch self {
        case .airplane: return 0
        case .train: return 1
        case .bus: return 2
        case .car: return 3
        case .bicycle: return 4
        case .walking: return 5
        }
    }
}

// MARK: - Flight

enum FlightDirection: String, Codable, Hashable, CaseIterable {
    case outbound
    case returnFlight
    case tripOutbound
    case tripReturn
    case additional

    var title: String {
        switch self {
        case .outbound:
            return WanderlustL10n.string("Outbound Flight", table: .trips)
        case .returnFlight:
            return WanderlustL10n.string("Return Flight", table: .trips)
        case .tripOutbound:
            return WanderlustL10n.string("Outbound Flight", table: .trips)
        case .tripReturn:
            return WanderlustL10n.string("Return Flight", table: .trips)
        case .additional:
            return WanderlustL10n.string("Trip Flight", table: .trips, fallback: "Trip Flight")
        }
    }

    var sortOrder: Int {
        switch self {
        case .outbound:
            return 0
        case .returnFlight:
            return 1
        case .tripOutbound:
            return 2
        case .tripReturn:
            return 3
        case .additional:
            return 4
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.outbound.rawValue:
            self = .outbound
        case Self.returnFlight.rawValue, "return":
            self = .returnFlight
        case Self.tripOutbound.rawValue:
            self = .tripOutbound
        case Self.tripReturn.rawValue:
            self = .tripReturn
        case Self.additional.rawValue, "other":
            self = .additional
        default:
            self = .additional
        }
    }
}

struct FlightLeg: Identifiable, Codable, Hashable {
    let id: UUID
    var airlineName: String
    var airlineCode: String
    var flightNumber: String
    var departureAirportName: String
    var departureAirportCode: String
    var departureAirportID: String
    var departureTimeZoneIdentifier: String
    var departureLatitude: Double
    var departureLongitude: Double
    var arrivalAirportName: String
    var arrivalAirportCode: String
    var arrivalAirportID: String
    var arrivalTimeZoneIdentifier: String
    var arrivalLatitude: Double
    var arrivalLongitude: Double
    var departureLocalDate: Date
    var arrivalLocalDate: Date?

    init(
        id: UUID = UUID(),
        airlineName: String = "",
        airlineCode: String = "",
        flightNumber: String = "",
        departureAirportName: String = "",
        departureAirportCode: String = "",
        departureAirportID: String = "",
        departureTimeZoneIdentifier: String = "",
        departureLatitude: Double = 0,
        departureLongitude: Double = 0,
        arrivalAirportName: String = "",
        arrivalAirportCode: String = "",
        arrivalAirportID: String = "",
        arrivalTimeZoneIdentifier: String = "",
        arrivalLatitude: Double = 0,
        arrivalLongitude: Double = 0,
        departureLocalDate: Date = Date(),
        arrivalLocalDate: Date? = nil
    ) {
        self.id = id
        self.airlineName = airlineName
        self.airlineCode = airlineCode
        self.flightNumber = flightNumber
        self.departureAirportName = departureAirportName
        self.departureAirportCode = departureAirportCode
        self.departureAirportID = departureAirportID
        self.departureTimeZoneIdentifier = departureTimeZoneIdentifier
        self.departureLatitude = departureLatitude
        self.departureLongitude = departureLongitude
        self.arrivalAirportName = arrivalAirportName
        self.arrivalAirportCode = arrivalAirportCode
        self.arrivalAirportID = arrivalAirportID
        self.arrivalTimeZoneIdentifier = arrivalTimeZoneIdentifier
        self.arrivalLatitude = arrivalLatitude
        self.arrivalLongitude = arrivalLongitude
        self.departureLocalDate = departureLocalDate
        self.arrivalLocalDate = arrivalLocalDate
    }

    var departureDate: Date {
        Flight.absoluteDate(
            fromLocalDate: departureLocalDate,
            timeZoneIdentifier: resolvedDepartureTimeZoneIdentifier
        )
    }

    var arrivalDate: Date? {
        guard let arrivalLocalDate else { return nil }
        return Flight.absoluteDate(
            fromLocalDate: arrivalLocalDate,
            timeZoneIdentifier: resolvedArrivalTimeZoneIdentifier
        )
    }

    var resolvedDepartureTimeZoneIdentifier: String {
        Flight.resolvedTimeZoneIdentifier(
            storedIdentifier: departureTimeZoneIdentifier,
            airportCode: departureAirportCode
        )
    }

    var resolvedArrivalTimeZoneIdentifier: String {
        Flight.resolvedTimeZoneIdentifier(
            storedIdentifier: arrivalTimeZoneIdentifier,
            airportCode: arrivalAirportCode
        )
    }

    var departureCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: departureLatitude, longitude: departureLongitude)
    }

    var arrivalCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: arrivalLatitude, longitude: arrivalLongitude)
    }

    var displayFlightNumber: String {
        let code = airlineCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = flightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return [code, number].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var localizedAirlineName: String {
        WanderlustL10n.airlineName(code: airlineCode, fallback: airlineName)
    }

    var localizedDepartureAirportName: String {
        WanderlustL10n.airportName(iataCode: departureAirportCode, fallback: departureAirportName)
    }

    var localizedArrivalAirportName: String {
        WanderlustL10n.airportName(iataCode: arrivalAirportCode, fallback: arrivalAirportName)
    }
}

typealias FlightSegment = FlightLeg

struct FlightDurationCalculator {
    let departureLocalDate: Date
    let arrivalLocalDate: Date
    let departureTimeZoneIdentifier: String
    let arrivalTimeZoneIdentifier: String

    var departureAbsoluteDate: Date {
        Flight.absoluteDate(
            fromLocalDate: departureLocalDate,
            timeZoneIdentifier: departureTimeZoneIdentifier
        )
    }

    var arrivalAbsoluteDate: Date {
        Flight.absoluteDate(
            fromLocalDate: arrivalLocalDate,
            timeZoneIdentifier: arrivalTimeZoneIdentifier
        )
    }

    var durationComponents: DateComponents? {
        let departure = departureAbsoluteDate
        let arrival = arrivalAbsoluteDate
        guard arrival > departure else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.dateComponents([.hour, .minute], from: departure, to: arrival)
    }

    var durationText: String? {
        guard let components = durationComponents else { return nil }
        return PluralizationFormatter.flightDuration(
            hours: components.hour ?? 0,
            minutes: components.minute ?? 0
        )
    }
}

struct Flight: Identifiable, Codable, Hashable {
    let id: UUID
    var direction: FlightDirection
    var customTitle: String
    var tripFlightGroupID: UUID?

    var airlineName: String
    var airlineCode: String
    var flightNumber: String

    var departureAirportName: String
    var departureAirportCode: String
    var departureAirportID: String
    var departureTimeZoneIdentifier: String
    var departureLatitude: Double
    var departureLongitude: Double

    var arrivalAirportName: String
    var arrivalAirportCode: String
    var arrivalAirportID: String
    var arrivalTimeZoneIdentifier: String
    var arrivalLatitude: Double
    var arrivalLongitude: Double

    var departureLocalDate: Date
    var arrivalLocalDate: Date?
    var legs: [FlightLeg]

    var departureDate: Date {
        Self.absoluteDate(
            fromLocalDate: departureLocalDate,
            timeZoneIdentifier: resolvedDepartureTimeZoneIdentifier
        )
    }

    var arrivalDate: Date? {
        guard let arrivalLocalDate else { return nil }
        return Self.absoluteDate(
            fromLocalDate: arrivalLocalDate,
            timeZoneIdentifier: resolvedArrivalTimeZoneIdentifier
        )
    }

    var resolvedDepartureTimeZoneIdentifier: String {
        Self.resolvedTimeZoneIdentifier(
            storedIdentifier: departureTimeZoneIdentifier,
            airportCode: departureAirportCode
        )
    }

    var resolvedArrivalTimeZoneIdentifier: String {
        Self.resolvedTimeZoneIdentifier(
            storedIdentifier: arrivalTimeZoneIdentifier,
            airportCode: arrivalAirportCode
        )
    }

    init(
        id: UUID = UUID(),
        direction: FlightDirection = .additional,
        customTitle: String = "",
        tripFlightGroupID: UUID? = nil,
        airlineName: String = "",
        airlineCode: String = "",
        flightNumber: String = "",
        departureAirportName: String = "",
        departureAirportCode: String = "",
        departureAirportID: String = "",
        departureTimeZoneIdentifier: String = "",
        departureLatitude: Double = 0,
        departureLongitude: Double = 0,
        arrivalAirportName: String = "",
        arrivalAirportCode: String = "",
        arrivalAirportID: String = "",
        arrivalTimeZoneIdentifier: String = "",
        arrivalLatitude: Double = 0,
        arrivalLongitude: Double = 0,
        departureDate: Date = Date(),
        arrivalDate: Date? = nil,
        departureLocalDate: Date? = nil,
        arrivalLocalDate: Date? = nil
    ) {
        self.id = id
        self.direction = direction
        self.customTitle = customTitle
        self.tripFlightGroupID = tripFlightGroupID
        self.airlineName = airlineName
        self.airlineCode = airlineCode
        self.flightNumber = flightNumber
        self.departureAirportName = departureAirportName
        self.departureAirportCode = departureAirportCode
        self.departureAirportID = departureAirportID
        self.departureTimeZoneIdentifier = departureTimeZoneIdentifier
        self.departureLatitude = departureLatitude
        self.departureLongitude = departureLongitude
        self.arrivalAirportName = arrivalAirportName
        self.arrivalAirportCode = arrivalAirportCode
        self.arrivalAirportID = arrivalAirportID
        self.arrivalTimeZoneIdentifier = arrivalTimeZoneIdentifier
        self.arrivalLatitude = arrivalLatitude
        self.arrivalLongitude = arrivalLongitude
        let resolvedDepartureTimeZoneIdentifier = Self.resolvedTimeZoneIdentifier(
            storedIdentifier: departureTimeZoneIdentifier,
            airportCode: departureAirportCode
        )
        let resolvedArrivalTimeZoneIdentifier = Self.resolvedTimeZoneIdentifier(
            storedIdentifier: arrivalTimeZoneIdentifier,
            airportCode: arrivalAirportCode
        )
        self.departureLocalDate = departureLocalDate ?? Self.localDisplayDate(
            fromAbsoluteDate: departureDate,
            timeZoneIdentifier: resolvedDepartureTimeZoneIdentifier
        )
        self.arrivalLocalDate = arrivalLocalDate ?? arrivalDate.map {
            Self.localDisplayDate(
                fromAbsoluteDate: $0,
                timeZoneIdentifier: resolvedArrivalTimeZoneIdentifier
            )
        }
        self.legs = [
            FlightLeg(
                airlineName: airlineName,
                airlineCode: airlineCode,
                flightNumber: flightNumber,
                departureAirportName: departureAirportName,
                departureAirportCode: departureAirportCode,
                departureAirportID: departureAirportID,
                departureTimeZoneIdentifier: departureTimeZoneIdentifier,
                departureLatitude: departureLatitude,
                departureLongitude: departureLongitude,
                arrivalAirportName: arrivalAirportName,
                arrivalAirportCode: arrivalAirportCode,
                arrivalAirportID: arrivalAirportID,
                arrivalTimeZoneIdentifier: arrivalTimeZoneIdentifier,
                arrivalLatitude: arrivalLatitude,
                arrivalLongitude: arrivalLongitude,
                departureLocalDate: self.departureLocalDate,
                arrivalLocalDate: self.arrivalLocalDate
            )
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case direction
        case customTitle
        case tripFlightGroupID
        case airlineName
        case airlineCode
        case flightNumber
        case departureAirportName
        case departureAirportCode
        case departureAirportID
        case departureTimeZoneIdentifier
        case departureLatitude
        case departureLongitude
        case arrivalAirportName
        case arrivalAirportCode
        case arrivalAirportID
        case arrivalTimeZoneIdentifier
        case arrivalLatitude
        case arrivalLongitude
        case departureDate
        case arrivalDate
        case departureLocalDate
        case arrivalLocalDate
        case legs
        case segments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        direction = try container.decodeIfPresent(FlightDirection.self, forKey: .direction) ?? .additional
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle) ?? ""
        tripFlightGroupID = try container.decodeIfPresent(UUID.self, forKey: .tripFlightGroupID)
        airlineName = try container.decodeIfPresent(String.self, forKey: .airlineName) ?? ""
        airlineCode = try container.decodeIfPresent(String.self, forKey: .airlineCode) ?? ""
        flightNumber = try container.decodeIfPresent(String.self, forKey: .flightNumber) ?? ""
        departureAirportName = try container.decodeIfPresent(String.self, forKey: .departureAirportName) ?? ""
        departureAirportCode = try container.decodeIfPresent(String.self, forKey: .departureAirportCode) ?? ""
        departureAirportID = try container.decodeIfPresent(String.self, forKey: .departureAirportID) ?? departureAirportCode
        departureTimeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .departureTimeZoneIdentifier) ?? ""
        departureLatitude = try container.decodeIfPresent(Double.self, forKey: .departureLatitude) ?? 0
        departureLongitude = try container.decodeIfPresent(Double.self, forKey: .departureLongitude) ?? 0
        arrivalAirportName = try container.decodeIfPresent(String.self, forKey: .arrivalAirportName) ?? ""
        arrivalAirportCode = try container.decodeIfPresent(String.self, forKey: .arrivalAirportCode) ?? ""
        arrivalAirportID = try container.decodeIfPresent(String.self, forKey: .arrivalAirportID) ?? arrivalAirportCode
        arrivalTimeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .arrivalTimeZoneIdentifier) ?? ""
        arrivalLatitude = try container.decodeIfPresent(Double.self, forKey: .arrivalLatitude) ?? 0
        arrivalLongitude = try container.decodeIfPresent(Double.self, forKey: .arrivalLongitude) ?? 0
        let decodedDepartureDate = try container.decodeIfPresent(Date.self, forKey: .departureDate) ?? Date()
        let decodedArrivalDate = try container.decodeIfPresent(Date.self, forKey: .arrivalDate)
        let resolvedDepartureTimeZoneIdentifier = Self.resolvedTimeZoneIdentifier(
            storedIdentifier: departureTimeZoneIdentifier,
            airportCode: departureAirportCode
        )
        let resolvedArrivalTimeZoneIdentifier = Self.resolvedTimeZoneIdentifier(
            storedIdentifier: arrivalTimeZoneIdentifier,
            airportCode: arrivalAirportCode
        )
        departureLocalDate = try container.decodeIfPresent(Date.self, forKey: .departureLocalDate) ??
            Self.localDisplayDate(
                fromAbsoluteDate: decodedDepartureDate,
                timeZoneIdentifier: resolvedDepartureTimeZoneIdentifier
            )
        arrivalLocalDate = try container.decodeIfPresent(Date.self, forKey: .arrivalLocalDate) ??
            decodedArrivalDate.map {
                Self.localDisplayDate(
                    fromAbsoluteDate: $0,
                    timeZoneIdentifier: resolvedArrivalTimeZoneIdentifier
                )
            }
        let decodedLegs = try container.decodeIfPresent([FlightLeg].self, forKey: .segments) ??
            container.decodeIfPresent([FlightLeg].self, forKey: .legs) ?? []
        if decodedLegs.isEmpty {
            legs = [
                FlightLeg(
                    airlineName: airlineName,
                    airlineCode: airlineCode,
                    flightNumber: flightNumber,
                    departureAirportName: departureAirportName,
                    departureAirportCode: departureAirportCode,
                    departureAirportID: departureAirportID,
                    departureTimeZoneIdentifier: departureTimeZoneIdentifier,
                    departureLatitude: departureLatitude,
                    departureLongitude: departureLongitude,
                    arrivalAirportName: arrivalAirportName,
                    arrivalAirportCode: arrivalAirportCode,
                    arrivalAirportID: arrivalAirportID,
                    arrivalTimeZoneIdentifier: arrivalTimeZoneIdentifier,
                    arrivalLatitude: arrivalLatitude,
                    arrivalLongitude: arrivalLongitude,
                    departureLocalDate: departureLocalDate,
                    arrivalLocalDate: arrivalLocalDate
                )
            ]
        } else {
            legs = decodedLegs
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(direction, forKey: .direction)
        try container.encode(customTitle, forKey: .customTitle)
        try container.encodeIfPresent(tripFlightGroupID, forKey: .tripFlightGroupID)
        try container.encode(airlineName, forKey: .airlineName)
        try container.encode(airlineCode, forKey: .airlineCode)
        try container.encode(flightNumber, forKey: .flightNumber)
        try container.encode(departureAirportName, forKey: .departureAirportName)
        try container.encode(departureAirportCode, forKey: .departureAirportCode)
        try container.encode(departureAirportID, forKey: .departureAirportID)
        try container.encode(departureTimeZoneIdentifier, forKey: .departureTimeZoneIdentifier)
        try container.encode(departureLatitude, forKey: .departureLatitude)
        try container.encode(departureLongitude, forKey: .departureLongitude)
        try container.encode(arrivalAirportName, forKey: .arrivalAirportName)
        try container.encode(arrivalAirportCode, forKey: .arrivalAirportCode)
        try container.encode(arrivalAirportID, forKey: .arrivalAirportID)
        try container.encode(arrivalTimeZoneIdentifier, forKey: .arrivalTimeZoneIdentifier)
        try container.encode(arrivalLatitude, forKey: .arrivalLatitude)
        try container.encode(arrivalLongitude, forKey: .arrivalLongitude)
        try container.encode(departureDate, forKey: .departureDate)
        try container.encodeIfPresent(arrivalDate, forKey: .arrivalDate)
        try container.encode(departureLocalDate, forKey: .departureLocalDate)
        try container.encodeIfPresent(arrivalLocalDate, forKey: .arrivalLocalDate)
        try container.encode(effectiveLegs, forKey: .legs)
        try container.encode(effectiveLegs, forKey: .segments)
    }

    var departureCoordinate: CLLocationCoordinate2D {
        guard let firstLeg = effectiveLegs.first else {
            return CLLocationCoordinate2D(
                latitude: departureLatitude,
                longitude: departureLongitude
            )
        }
        return firstLeg.departureCoordinate
    }

    var arrivalCoordinate: CLLocationCoordinate2D {
        guard let lastLeg = effectiveLegs.last else {
            return CLLocationCoordinate2D(
                latitude: arrivalLatitude,
                longitude: arrivalLongitude
            )
        }
        return lastLeg.arrivalCoordinate
    }

    var effectiveLegs: [FlightLeg] {
        let sourceLegs = legs.isEmpty ? [legacyLeg] : legs
        let cleanedLegs = sourceLegs.filter { leg in
            let departureCode = leg.departureAirportCode
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            let arrivalCode = leg.arrivalAirportCode
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            let departureID = leg.departureAirportID
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            let arrivalID = leg.arrivalAirportID
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            return !(departureCode == arrivalCode && departureID == arrivalID)
        }
        return cleanedLegs.isEmpty ? [legacyLeg] : cleanedLegs
    }

    private var legacyLeg: FlightLeg {
        FlightLeg(
            airlineName: airlineName,
            airlineCode: airlineCode,
            flightNumber: flightNumber,
            departureAirportName: departureAirportName,
            departureAirportCode: departureAirportCode,
            departureAirportID: departureAirportID,
            departureTimeZoneIdentifier: departureTimeZoneIdentifier,
            departureLatitude: departureLatitude,
            departureLongitude: departureLongitude,
            arrivalAirportName: arrivalAirportName,
            arrivalAirportCode: arrivalAirportCode,
            arrivalAirportID: arrivalAirportID,
            arrivalTimeZoneIdentifier: arrivalTimeZoneIdentifier,
            arrivalLatitude: arrivalLatitude,
            arrivalLongitude: arrivalLongitude,
            departureLocalDate: departureLocalDate,
            arrivalLocalDate: arrivalLocalDate
        )
    }

    var routeTitle: String {
        let codes = [effectiveLegs.first?.departureAirportCode] + effectiveLegs.map(\.arrivalAirportCode)
        let cleanedCodes = codes.compactMap { code -> String? in
            let cleanedCode = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return cleanedCode.isEmpty ? nil : cleanedCode
        }
        return cleanedCodes.isEmpty ? "\(departureAirportCode) → \(arrivalAirportCode)" : cleanedCodes.joined(separator: " → ")
    }

    var directionTitle: String {
        let title = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if direction == .additional, !title.isEmpty {
            return title
        }
        return direction.title
    }

    var localizedAirlineName: String {
        WanderlustL10n.airlineName(code: airlineCode, fallback: airlineName)
    }

    var localizedDepartureAirportName: String {
        WanderlustL10n.airportName(iataCode: departureAirportCode, fallback: departureAirportName)
    }

    var localizedArrivalAirportName: String {
        WanderlustL10n.airportName(iataCode: arrivalAirportCode, fallback: arrivalAirportName)
    }

    var displayFlightNumber: String {
        if effectiveLegs.count > 1, let firstLeg = effectiveLegs.first {
            let firstNumber = firstLeg.displayFlightNumber
            return firstNumber.isEmpty ? WanderlustL10n.string("Connecting flight", table: .trips) : "\(firstNumber) +\(effectiveLegs.count - 1)"
        }

        let code = airlineCode.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let number = flightNumber.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return [code, number]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var durationText: String? {
        let calculator: FlightDurationCalculator
        if let firstLeg = effectiveLegs.first,
           let lastLeg = effectiveLegs.last,
           let lastArrivalLocalDate = lastLeg.arrivalLocalDate {
            calculator = FlightDurationCalculator(
                departureLocalDate: firstLeg.departureLocalDate,
                arrivalLocalDate: lastArrivalLocalDate,
                departureTimeZoneIdentifier: firstLeg.resolvedDepartureTimeZoneIdentifier,
                arrivalTimeZoneIdentifier: lastLeg.resolvedArrivalTimeZoneIdentifier
            )
        } else if let arrivalLocalDate {
            calculator = FlightDurationCalculator(
                departureLocalDate: departureLocalDate,
                arrivalLocalDate: arrivalLocalDate,
                departureTimeZoneIdentifier: resolvedDepartureTimeZoneIdentifier,
                arrivalTimeZoneIdentifier: resolvedArrivalTimeZoneIdentifier
            )
        } else {
            return nil
        }

        guard let components = calculator.durationComponents else { return nil }
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        return PluralizationFormatter.flightDuration(hours: hours, minutes: minutes)
    }

    var hasValidTimeZoneDuration: Bool {
        guard let lastArrivalDate = effectiveLegs.last?.arrivalDate ?? arrivalDate else { return false }
        return lastArrivalDate > (effectiveLegs.first?.departureDate ?? departureDate)
    }

    var departureDisplayText: String {
        formattedFlightDate(
            departureDate,
            timeZoneIdentifier: resolvedDepartureTimeZoneIdentifier
        )
    }

    var arrivalDisplayText: String? {
        guard let arrivalDate else { return nil }
        return formattedFlightDate(
            arrivalDate,
            timeZoneIdentifier: resolvedArrivalTimeZoneIdentifier
        )
    }

    static func absoluteDate(
        fromLocalDate localDate: Date,
        timeZoneIdentifier: String
    ) -> Date {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return localDate
        }

        let visibleComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: localDate
        )

        var airportCalendar = Calendar(identifier: .gregorian)
        airportCalendar.timeZone = timeZone

        return airportCalendar.date(from: visibleComponents) ?? localDate
    }

    static func resolvedTimeZoneIdentifier(
        storedIdentifier: String,
        airportCode: String
    ) -> String {
        let cleanedIdentifier = storedIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCode = airportCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let fallbackIdentifiers: [String: String] = [
            "HND": "Asia/Tokyo",
            "NRT": "Asia/Tokyo",
            "KIX": "Asia/Tokyo",
            "TTJ": "Asia/Tokyo",
            "ICN": "Asia/Seoul",
            "GMP": "Asia/Seoul",
            "LHR": "Europe/London",
            "LGW": "Europe/London",
            "CDG": "Europe/Paris",
            "ORY": "Europe/Paris",
            "IST": "Europe/Istanbul",
            "DLM": "Europe/Istanbul",
            "DXB": "Asia/Dubai",
            "DOH": "Asia/Qatar",
            "SIN": "Asia/Singapore",
            "BKK": "Asia/Bangkok",
            "JFK": "America/New_York",
            "LAX": "America/Los_Angeles"
        ]

        if cleanedIdentifier.contains("/"),
           TimeZone(identifier: cleanedIdentifier) != nil {
            return cleanedIdentifier
        }

        if let fallbackIdentifier = fallbackIdentifiers[cleanedCode] {
            return fallbackIdentifier
        }

        if let airportIdentifier = AirportTimeZoneLookup.timeZoneIdentifier(for: cleanedCode) {
            return airportIdentifier
        }

        if !cleanedIdentifier.isEmpty,
           TimeZone(identifier: cleanedIdentifier) != nil {
            return cleanedIdentifier
        }

        return "UTC"
    }

    static func localDisplayDate(
        fromAbsoluteDate absoluteDate: Date,
        timeZoneIdentifier: String
    ) -> Date {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return absoluteDate
        }

        var airportCalendar = Calendar(identifier: .gregorian)
        airportCalendar.timeZone = timeZone
        let visibleComponents = airportCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: absoluteDate
        )
        return Calendar.current.date(from: visibleComponents) ?? absoluteDate
    }

    static func localWallDate(
        fromPickerDate pickerDate: Date,
        timeZoneIdentifier: String
    ) -> Date {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return pickerDate
        }

        var airportCalendar = Calendar(identifier: .gregorian)
        airportCalendar.timeZone = timeZone
        let visibleComponents = airportCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: pickerDate
        )
        return Calendar.current.date(from: visibleComponents) ?? pickerDate
    }

    private func formattedFlightDate(
        _ date: Date,
        timeZoneIdentifier: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMMdjm")
        if let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            formatter.timeZone = timeZone
        }
        return formatter.string(from: date)
    }

    private static func timeZoneAbbreviation(
        for date: Date,
        timeZoneIdentifier: String
    ) -> String {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return ""
        }
        switch timeZoneIdentifier {
        case "Asia/Tokyo":
            return "JST"
        case "Europe/London":
            return timeZone.isDaylightSavingTime(for: date) ? "BST" : "GMT"
        case "Europe/Paris":
            return timeZone.isDaylightSavingTime(for: date) ? "CEST" : "CET"
        case "Europe/Istanbul":
            return "TRT"
        case "Europe/Athens", "Europe/Bucharest", "Europe/Helsinki", "Europe/Riga", "Europe/Sofia", "Europe/Tallinn", "Europe/Vilnius":
            return timeZone.isDaylightSavingTime(for: date) ? "EEST" : "EET"
        case "America/New_York":
            return timeZone.isDaylightSavingTime(for: date) ? "EDT" : "EST"
        case "America/Los_Angeles":
            return timeZone.isDaylightSavingTime(for: date) ? "PDT" : "PST"
        default:
            break
        }

        if let abbreviation = timeZone.abbreviation(for: date),
           !abbreviation.isEmpty {
            if abbreviation == "GMT+0" { return "GMT" }
            return abbreviation
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "zzz"
        return formatter.string(from: date)
    }

    func routeCoordinates(steps: Int = 140) -> [CLLocationCoordinate2D] {
        let validLegs = effectiveLegs.filter {
            $0.departureCoordinate.latitude != $0.arrivalCoordinate.latitude ||
            $0.departureCoordinate.longitude != $0.arrivalCoordinate.longitude
        }
        guard !validLegs.isEmpty else {
            return [departureCoordinate, arrivalCoordinate]
        }
        let stepsPerLeg = max(steps / validLegs.count, 12)
        return validLegs.enumerated().flatMap { index, leg in
            let coordinates = (0...stepsPerLeg).map { step in
                Self.greatCircleCoordinate(
                    from: leg.departureCoordinate,
                    to: leg.arrivalCoordinate,
                    progress: Double(step) / Double(stepsPerLeg)
                )
            }
            return index == 0 ? coordinates : Array(coordinates.dropFirst())
        }
    }

    func routeCoordinate(at progress: Double) -> CLLocationCoordinate2D {
        let validLegs = effectiveLegs.filter {
            $0.departureCoordinate.latitude != $0.arrivalCoordinate.latitude ||
            $0.departureCoordinate.longitude != $0.arrivalCoordinate.longitude
        }
        guard !validLegs.isEmpty else { return departureCoordinate }
        let value = min(max(progress, 0), 1)
        if value >= 1, let lastLeg = validLegs.last {
            return lastLeg.arrivalCoordinate
        }
        let scaledProgress = value * Double(validLegs.count)
        let legIndex = min(Int(scaledProgress), validLegs.count - 1)
        let legProgress = scaledProgress - Double(legIndex)
        let leg = validLegs[legIndex]
        return Self.greatCircleCoordinate(
            from: leg.departureCoordinate,
            to: leg.arrivalCoordinate,
            progress: legProgress
        )
    }

    private static func greatCircleCoordinate(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        progress: Double
    ) -> CLLocationCoordinate2D {
        let value = min(max(progress, 0), 1)
        let startLatitude = start.latitude * .pi / 180
        let startLongitude = start.longitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let endLongitude = end.longitude * .pi / 180

        let startVector = (
            x: cos(startLatitude) * cos(startLongitude),
            y: cos(startLatitude) * sin(startLongitude),
            z: sin(startLatitude)
        )

        let endVector = (
            x: cos(endLatitude) * cos(endLongitude),
            y: cos(endLatitude) * sin(endLongitude),
            z: sin(endLatitude)
        )

        let dotProduct = min(max(
            startVector.x * endVector.x +
            startVector.y * endVector.y +
            startVector.z * endVector.z,
            -1
        ), 1)

        let angle = acos(dotProduct)
        guard angle > 0.000001 else { return start }

        let sinAngle = sin(angle)
        let startWeight = sin((1 - value) * angle) / sinAngle
        let endWeight = sin(value * angle) / sinAngle

        let x = startWeight * startVector.x + endWeight * endVector.x
        let y = startWeight * startVector.y + endWeight * endVector.y
        let z = startWeight * startVector.z + endWeight * endVector.z

        return CLLocationCoordinate2D(
            latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
            longitude: Self.normalizedLongitude(atan2(y, x) * 180 / .pi)
        )
    }

    func routeBearingDegrees(at progress: Double) -> Double {
        let current = routeCoordinate(at: progress)
        let next = routeCoordinate(at: min(progress + 0.006, 1))
        let previous = routeCoordinate(at: max(progress - 0.006, 0))
        let target = progress >= 0.994 ? current : next
        let origin = progress >= 0.994 ? previous : current
        let latitude1 = origin.latitude * .pi / 180
        let latitude2 = target.latitude * .pi / 180
        let longitudeDelta = adjustedLongitudeDifference(
            from: origin.longitude,
            to: target.longitude
        ) * .pi / 180

        let y = sin(longitudeDelta) * cos(latitude2)
        let x = cos(latitude1) * sin(latitude2) - sin(latitude1) * cos(latitude2) * cos(longitudeDelta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func adjustedLongitudeDifference(from start: Double, to end: Double) -> Double {
        var difference = end - start
        if difference > 180 {
            difference -= 360
        } else if difference < -180 {
            difference += 360
        }
        return difference
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        var value = longitude
        if value > 180 {
            value -= 360
        } else if value < -180 {
            value += 360
        }
        return value
    }
}

extension Array where Element == Flight {
    func normalizedFlightList() -> [Flight] {
        var mergedByExactRoute: [String: Flight] = [:]
        var exactKeyOrder: [String] = []

        for flight in self {
            let exactKey = FlightListNormalizer.exactRouteKey(for: flight)
            if let existing = mergedByExactRoute[exactKey] {
                mergedByExactRoute[exactKey] = FlightListNormalizer.preferredFlight(existing, flight)
            } else {
                mergedByExactRoute[exactKey] = flight
                exactKeyOrder.append(exactKey)
            }
        }

        var mergedByOverallRoute: [String: Flight] = [:]
        var overallKeyOrder: [String] = []
        for exactKey in exactKeyOrder {
            guard let flight = mergedByExactRoute[exactKey] else { continue }
            let overallKey = FlightListNormalizer.overallRouteKey(for: flight)
            if let existing = mergedByOverallRoute[overallKey] {
                mergedByOverallRoute[overallKey] = FlightListNormalizer.preferredFlight(existing, flight)
            } else {
                mergedByOverallRoute[overallKey] = flight
                overallKeyOrder.append(overallKey)
            }
        }

        return overallKeyOrder
            .compactMap { mergedByOverallRoute[$0] }
    }

    var hasValidGroupedDepartureOrder: Bool {
        firstInvalidGroupedDepartureOrderFlight == nil
    }

    static var departureOrderValidationMessage: String {
        WanderlustL10n.string(
            "Flights must be in departure time order. Edit the departure times before saving this order.",
            table: .trips,
            fallback: "Flights must be in departure time order. Edit the departure times before saving this order."
        )
    }

    var departureOrderValidationMessage: String {
        guard let flight = firstInvalidGroupedDepartureOrderFlight else {
            return Self.departureOrderValidationMessage
        }

        let format = WanderlustL10n.string(
            "Edit this flight before saving:\n%@\nFlights must be in departure time order.",
            table: .trips,
            fallback: "Edit this flight before saving:\n%@\nFlights must be in departure time order."
        )
        return String(format: format, flight.departureOrderValidationSummary)
    }

    private var firstInvalidGroupedDepartureOrderFlight: Flight? {
        for flights in groupedForDepartureOrderValidation() {
            for (previous, next) in zip(flights, flights.dropFirst()) where previous.departureDate > next.departureDate {
                return next
            }
        }
        return nil
    }

    private func groupedForDepartureOrderValidation() -> [[Flight]] {
        var groups: [[Flight]] = []

        for direction in [FlightDirection.outbound, .returnFlight, .additional] {
            let directionFlights = filter { $0.direction == direction }
            if directionFlights.count > 1 {
                groups.append(directionFlights)
            }
        }

        for groupID in tripFlightGroupIDsForValidation() {
            for direction in [FlightDirection.tripOutbound, .tripReturn] {
                let directionFlights = filter {
                    $0.direction == direction && $0.tripFlightGroupID == groupID
                }
                if directionFlights.count > 1 {
                    groups.append(directionFlights)
                }
            }
        }

        return groups
    }

    private func tripFlightGroupIDsForValidation() -> [UUID] {
        var ids: [UUID] = []
        for flight in self where flight.direction == .tripOutbound || flight.direction == .tripReturn {
            guard let groupID = flight.tripFlightGroupID,
                  !ids.contains(groupID) else {
                continue
            }
            ids.append(groupID)
        }
        return ids
    }
}

private extension Flight {
    var departureOrderValidationSummary: String {
        let details = [displayFlightNumber, routeTitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ")

        guard !details.isEmpty else {
            return directionTitle
        }

        return "\(directionTitle): \(details)"
    }
}

private enum FlightListNormalizer {
    static func exactRouteKey(for flight: Flight) -> String {
        [
            baseKey(for: flight),
            routePathKey(for: flight)
        ].joined(separator: "|")
    }

    static func overallRouteKey(for flight: Flight) -> String {
        [
            baseKey(for: flight),
            airportKey(flight.effectiveLegs.first?.departureAirportID, fallback: flight.departureAirportID.isEmpty ? flight.departureAirportCode : flight.departureAirportID),
            airportKey(flight.effectiveLegs.last?.arrivalAirportID, fallback: flight.arrivalAirportID.isEmpty ? flight.arrivalAirportCode : flight.arrivalAirportID)
        ].joined(separator: "|")
    }

    static func preferredFlight(_ first: Flight, _ second: Flight) -> Flight {
        if first.effectiveLegs.count != second.effectiveLegs.count {
            return first.effectiveLegs.count > second.effectiveLegs.count ? first : second
        }

        let firstCompleteness = completenessScore(first)
        let secondCompleteness = completenessScore(second)
        if firstCompleteness != secondCompleteness {
            return firstCompleteness > secondCompleteness ? first : second
        }

        return first.departureDate >= second.departureDate ? first : second
    }

    private static func baseKey(for flight: Flight) -> String {
        [
            flight.direction.rawValue,
            flight.tripFlightGroupID?.uuidString ?? "",
            normalized(flight.airlineCode),
            normalized(flight.flightNumber),
            minuteKey(flight.departureDate)
        ].joined(separator: "|")
    }

    private static func routePathKey(for flight: Flight) -> String {
        let legs = flight.effectiveLegs
        let codes = [airportKey(legs.first?.departureAirportID, fallback: legs.first?.departureAirportCode ?? "")]
            + legs.map { airportKey($0.arrivalAirportID, fallback: $0.arrivalAirportCode) }
        if !codes.isEmpty {
            return codes.joined(separator: ">")
        }

        return [
            airportKey(flight.departureAirportID, fallback: flight.departureAirportCode),
            airportKey(flight.arrivalAirportID, fallback: flight.arrivalAirportCode)
        ].joined(separator: ">")
    }

    private static func completenessScore(_ flight: Flight) -> Int {
        let flightScore = [
            flight.airlineName,
            flight.airlineCode,
            flight.flightNumber,
            flight.departureAirportName,
            flight.departureAirportCode,
            flight.arrivalAirportName,
            flight.arrivalAirportCode
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        let legScore = flight.effectiveLegs.reduce(0) { result, leg in
            result + [
                leg.airlineName,
                leg.airlineCode,
                leg.flightNumber,
                leg.departureAirportName,
                leg.departureAirportCode,
                leg.arrivalAirportName,
                leg.arrivalAirportCode
            ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        }
        return flightScore + legScore
    }

    private static func airportKey(_ value: String?, fallback: String) -> String {
        let cleanedValue = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized(cleanedValue.isEmpty ? fallback : cleanedValue)
    }

    private static func minuteKey(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970 / 60.0))
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}

// MARK: - Visited City

struct VisitedCity: Identifiable, Codable, Hashable {
    let id: UUID

    var geonameID: Int?

    var name: String
    var countryName: String
    var countryCode: String

    var latitude: Double
    var longitude: Double

    var periods: [VisitPeriod]

    var notes: String

    @MainActor var localizedName: String {
        if let geonameID {
            return WanderlustNameResolver.cityName(for: geonameID, fallback: name)
        }

        if let resolvedID = WanderlustNameResolver.resolveCityID(
            name: name,
            countryCode: countryCode,
            latitude: latitude,
            longitude: longitude
        ) {
            return WanderlustL10n.cityName(id: String(resolvedID), fallback: name)
        }

        return WanderlustL10n.cityName(
            countryCode: countryCode,
            name: name,
            fallback: name
        )
    }

    @MainActor var localizedCountryName: String {
        WanderlustNameResolver.countryName(
            for: WanderlustNameResolver.normalizedCountryCode(
                countryCode,
                fallback: countryName
            ),
            fallback: countryName
        )
    }

    init(
        id: UUID = UUID(),
        geonameID: Int? = nil,
        name: String,
        countryName: String,
        countryCode: String = "",
        latitude: Double,
        longitude: Double,
        arrivalDate: Date? = nil,
        departureDate: Date? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.geonameID = geonameID
        self.name = name
        self.countryName = countryName
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        if let arrivalDate {
            self.periods = [
                VisitPeriod(
                    startDate: arrivalDate,
                    endDate: departureDate ?? arrivalDate
                )
            ]
        } else {
            self.periods = []
        }
        self.notes = notes
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }

    var arrivalDate: Date? {
        get {
            periods.map(\.startDate).min()
        }
        set {
            if let newValue {
                if periods.isEmpty {
                    periods = [VisitPeriod(startDate: newValue, endDate: newValue)]
                } else {
                    periods[0].startDate = newValue
                    if periods[0].endDate < newValue {
                        periods[0].endDate = newValue
                    }
                    sortPeriods()
                }
            } else {
                periods = []
            }
        }
    }

    var departureDate: Date? {
        get {
            periods.map(\.endDate).max()
        }
        set {
            guard let newValue else {
                periods = []
                return
            }
            if periods.isEmpty {
                periods = [VisitPeriod(startDate: newValue, endDate: newValue)]
            } else {
                periods[0].endDate = max(newValue, periods[0].startDate)
                sortPeriods()
            }
        }
    }

    var earliestVisitDate: Date? {
        periods.map(\.startDate).min()
    }

    var sortedPeriods: [VisitPeriod] {
        periods.sorted { $0.startDate < $1.startDate }
    }

    mutating func sortPeriods() {
        periods.sort { $0.startDate < $1.startDate }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case geonameID
        case name
        case countryName
        case countryCode
        case latitude
        case longitude
        case periods
        case arrivalDate
        case departureDate
        case notes
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        geonameID = try container.decodeIfPresent(Int.self, forKey: .geonameID)
        name = try container.decode(String.self, forKey: .name)
        countryName = try container.decodeIfPresent(String.self, forKey: .countryName) ?? ""
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode) ?? ""
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""

        if let decodedPeriods = try container.decodeIfPresent([VisitPeriod].self, forKey: .periods),
           !decodedPeriods.isEmpty {
            periods = decodedPeriods.sorted { $0.startDate < $1.startDate }
        } else if let arrivalDate = try container.decodeIfPresent(Date.self, forKey: .arrivalDate) {
            let departureDate = try container.decodeIfPresent(Date.self, forKey: .departureDate) ?? arrivalDate
            periods = [VisitPeriod(startDate: arrivalDate, endDate: departureDate)]
        } else {
            periods = []
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(geonameID, forKey: .geonameID)
        try container.encode(name, forKey: .name)
        try container.encode(countryName, forKey: .countryName)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(periods, forKey: .periods)
        try container.encode(notes, forKey: .notes)
    }
}

private enum AirportTimeZoneLookup {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var cachedTimeZonesByCode: [String: String]?

    static func timeZoneIdentifier(for airportCode: String) -> String? {
        let cleanedCode = airportCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanedCode.isEmpty else { return nil }
        return timeZonesByCode()[cleanedCode]
    }

    private static func timeZonesByCode() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }

        if let cachedTimeZonesByCode {
            return cachedTimeZonesByCode
        }

        let loadedTimeZones = loadTimeZonesByCode()
        cachedTimeZonesByCode = loadedTimeZones
        return loadedTimeZones
    }

    private static func loadTimeZonesByCode() -> [String: String] {
        guard let url = airportsJSONURL(),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let airports = object["airports"] as? [[String: Any]] else {
            return [:]
        }

        var timeZonesByCode: [String: String] = [:]
        for airport in airports {
            guard let timezone = stringValue(airport["timeZoneID"] ?? airport["timezone"]),
                  TimeZone(identifier: timezone) != nil else {
                continue
            }

            for key in ["iataCode", "icaoCode", "gpsCode", "ident", "id"] {
                if let code = stringValue(airport[key])?.uppercased(), !code.isEmpty {
                    timeZonesByCode[code] = timezone
                }
            }
        }

        return timeZonesByCode
    }

    private static func airportsJSONURL() -> URL? {
        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in bundles {
            if let url = bundle.url(forResource: "airports", withExtension: "json") {
                return url
            }
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

// MARK: - Trip Group

struct TripGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var notes: String
    var tripIDs: [UUID]
    var transportItems: [TripGroupTransportItem]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        tripIDs: [UUID],
        transportItems: [TripGroupTransportItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tripIDs = Self.uniqueTripIDs(tripIDs)
        self.transportItems = transportItems.sortedByDate()
        self.createdAt = createdAt
        self.updatedAt = max(updatedAt, createdAt)
    }

    static func defaultTitle(for trip: Trip) -> String {
        let cityNames = trip.cities
            .sortedByVisitDate()
            .map(\.localizedName)
            .filter { !$0.isEmpty }

        if !cityNames.isEmpty {
            return cityNames.prefix(3).joined(separator: "・")
        }

        if !trip.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return trip.title
        }

        return WanderlustDateFormatter.monthYear(trip.startDate)
    }

    static func singleTripGroup(for trip: Trip) -> TripGroup {
        TripGroup(
            id: trip.id,
            title: defaultTitle(for: trip),
            tripIDs: [trip.id],
            createdAt: trip.createdAt,
            updatedAt: trip.updatedAt
        )
    }

    private static func uniqueTripIDs(_ tripIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return tripIDs.filter { seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case tripIDs
        case transportItems
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tripIDs = Self.uniqueTripIDs(
            try container.decodeIfPresent([UUID].self, forKey: .tripIDs) ?? []
        )
        transportItems = (
            try container.decodeIfPresent([TripGroupTransportItem].self, forKey: .transportItems) ?? []
        ).sortedByDate()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(tripIDs, forKey: .tripIDs)
        try container.encode(transportItems, forKey: .transportItems)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct TripGroupTransportItem: Identifiable, Codable, Hashable {
    let id: UUID
    var transportationType: TransportationType
    var title: String
    var origin: String
    var destination: String
    var departureDate: Date
    var arrivalDate: Date?
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        transportationType: TransportationType,
        title: String = "",
        origin: String,
        destination: String,
        departureDate: Date,
        arrivalDate: Date? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.transportationType = transportationType
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.origin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        self.destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = max(updatedAt, createdAt)
    }

    var displayTitle: String {
        if !title.isEmpty {
            return title
        }

        let route = [origin, destination]
            .filter { !$0.isEmpty }
            .joined(separator: " → ")

        return route.isEmpty ? transportationType.title : route
    }
}

extension Array where Element == TripGroupTransportItem {
    func sortedByDate() -> [TripGroupTransportItem] {
        sorted { lhs, rhs in
            if lhs.departureDate != rhs.departureDate {
                return lhs.departureDate < rhs.departureDate
            }
            return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }
    }
}

// MARK: - Trip

struct Trip: Identifiable, Codable, Hashable {
    let id: UUID

    var title: String

    var startDate: Date
    var endDate: Date

    var notes: String

    var cities: [VisitedCity]
    var transportationTypes: [TransportationType]
    var flights: [Flight]

    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String = "",
        cities: [VisitedCity] = [],
        transportationTypes: [TransportationType] = [.airplane],
        flights: [Flight] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = max(endDate, startDate)
        self.notes = notes
        self.cities = cities
        let normalizedFlights = flights.normalizedFlightList()
        self.transportationTypes = Self.normalizedTransportationTypes(transportationTypes, flights: normalizedFlights)
        self.flights = normalizedFlights
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = max(updatedAt, createdAt)
    }

    // MARK: Temporary compatibility

    /*
     旧版WanderlustのAddTripViewやTripCardViewがまだ残っていても
     コンパイルできるようにするための互換Initializer。
     画面を新しくした後も残して問題ありません。
    */

    init(
        id: UUID = UUID(),
        place: String,
        country: String = "",
        date: Date,
        latitude: Double,
        longitude: Double,
        notes: String = "",
        imageData: Data? = nil,
        isFavorite: Bool = false
    ) {
        let city = VisitedCity(
            name: place,
            countryName: country,
            latitude: latitude,
            longitude: longitude,
            arrivalDate: date,
            departureDate: date,
            notes: notes
        )

        self.id = id
        self.title = place
        self.startDate = date
        self.endDate = date
        self.notes = notes
        self.cities = [city]
        self.transportationTypes = [.airplane]
        self.flights = []
        self.isFavorite = isFavorite
        self.createdAt = date
        self.updatedAt = date
    }

    // MARK: Derived information

    var visitedCountries: [String] {
        Array(
            Set(
                cities
                    .map {
                        $0.countryName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    }
                    .filter {
                        !$0.isEmpty &&
                        $0.lowercased() != "unknown"
                    }
            )
        )
        .sorted {
            $0.localizedCaseInsensitiveCompare($1) ==
            .orderedAscending
        }
    }

    var visitedCountryCodes: [String] {
        Array(
            Set(
                cities
                    .map {
                        $0.countryCode
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .uppercased()
                    }
                    .filter {
                        !$0.isEmpty
                    }
            )
        )
        .sorted()
    }

    var countryISO2: String? {
        visitedCountryCodes.first
    }

    var cityCount: Int {
        cities.count
    }

    var flightCount: Int {
        flights.count
    }

    var transportationSummary: String {
        transportationTypes
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.title)
            .joined(separator: ", ")
    }

    var dateRangeText: String {
        WanderlustDateFormatter.dateRange(start: startDate, end: endDate)
    }

    var displayTitle: String {
        WanderlustDateFormatter.monthYear(startDate)
    }

    // MARK: Legacy computed properties

    /*
     古い画面が trip.place / trip.country などを参照していても
     すぐに大量のエラーにならないための互換プロパティ。
    */

    var place: String {
        get {
            cities.first?.name ?? title
        }
        set {
            guard !cities.isEmpty else {
                cities.append(
                    VisitedCity(
                        name: newValue,
                        countryName: "",
                        latitude: 0,
                        longitude: 0
                    )
                )
                return
            }

            cities[0].name = newValue
        }
    }

    var country: String {
        get {
            cities.first?.countryName ?? ""
        }
        set {
            guard !cities.isEmpty else {
                cities.append(
                    VisitedCity(
                        name: title,
                        countryName: newValue,
                        latitude: 0,
                        longitude: 0
                    )
                )
                return
            }

            cities[0].countryName = newValue
        }
    }

    var date: Date {
        get {
            startDate
        }
        set {
            startDate = newValue

            if endDate < newValue {
                endDate = newValue
            }
        }
    }

    var latitude: Double {
        get {
            cities.first?.latitude ?? 0
        }
        set {
            guard !cities.isEmpty else {
                cities.append(
                    VisitedCity(
                        name: title,
                        countryName: "",
                        latitude: newValue,
                        longitude: 0
                    )
                )
                return
            }

            cities[0].latitude = newValue
        }
    }

    var longitude: Double {
        get {
            cities.first?.longitude ?? 0
        }
        set {
            guard !cities.isEmpty else {
                cities.append(
                    VisitedCity(
                        name: title,
                        countryName: "",
                        latitude: 0,
                        longitude: newValue
                    )
                )
                return
            }

            cities[0].longitude = newValue
        }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }

    var formattedLocation: String {
        if country.isEmpty {
            return place
        }

        return "\(place), \(country)"
    }

    var hasPhoto: Bool {
        false
    }

    var imageData: Data? {
        get {
            nil
        }
        set {
            // 写真機能は使用しないため保存しません。
        }
    }

    private static func normalizedTransportationTypes(
        _ types: [TransportationType]?,
        flights: [Flight]
    ) -> [TransportationType] {
        var uniqueTypes = Set(types ?? [])
        if !flights.isEmpty {
            uniqueTypes.insert(.airplane)
        }
        if uniqueTypes.isEmpty {
            uniqueTypes.insert(.airplane)
        }
        return uniqueTypes.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: Codable migration

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case startDate
        case endDate
        case notes
        case cities
        case transportationTypes
        case flights
        case isFavorite
        case createdAt
        case updatedAt

        // 旧版Tripのキー
        case place
        case country
        case date
        case latitude
        case longitude
        case imageData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        id = try container.decodeIfPresent(
            UUID.self,
            forKey: .id
        ) ?? UUID()

        isFavorite = try container.decodeIfPresent(
            Bool.self,
            forKey: .isFavorite
        ) ?? false

        /*
         新しいTrip形式なら、そのまま読み込みます。
        */

        if let decodedCities = try container.decodeIfPresent(
            [VisitedCity].self,
            forKey: .cities
        ) {
            title = try container.decodeIfPresent(
                String.self,
                forKey: .title
            ) ?? decodedCities.first?.name ?? "Untitled Trip"

            startDate = try container.decodeIfPresent(
                Date.self,
                forKey: .startDate
            ) ?? Date()

            endDate = try container.decodeIfPresent(
                Date.self,
                forKey: .endDate
            ) ?? startDate

            notes = try container.decodeIfPresent(
                String.self,
                forKey: .notes
            ) ?? ""

            cities = decodedCities

            flights = try container.decodeIfPresent(
                [Flight].self,
                forKey: .flights
            ) ?? []

            let decodedTransportationTypes = try container.decodeIfPresent(
                [TransportationType].self,
                forKey: .transportationTypes
            )
            transportationTypes = Self.normalizedTransportationTypes(
                decodedTransportationTypes,
                flights: flights
            )

            createdAt = try container.decodeIfPresent(
                Date.self,
                forKey: .createdAt
            ) ?? startDate

            updatedAt = try container.decodeIfPresent(
                Date.self,
                forKey: .updatedAt
            ) ?? createdAt

            return
        }

        /*
         旧版Trip形式を新形式へ自動変換します。
        */

        let oldPlace = try container.decodeIfPresent(
            String.self,
            forKey: .place
        ) ?? "Untitled Place"

        let oldCountry = try container.decodeIfPresent(
            String.self,
            forKey: .country
        ) ?? ""

        let oldDate = try container.decodeIfPresent(
            Date.self,
            forKey: .date
        ) ?? Date()

        let oldLatitude = try container.decodeIfPresent(
            Double.self,
            forKey: .latitude
        ) ?? 0

        let oldLongitude = try container.decodeIfPresent(
            Double.self,
            forKey: .longitude
        ) ?? 0

        let oldNotes = try container.decodeIfPresent(
            String.self,
            forKey: .notes
        ) ?? ""

        title = oldPlace
        startDate = oldDate
        endDate = oldDate
        notes = oldNotes

        cities = [
            VisitedCity(
                name: oldPlace,
                countryName: oldCountry,
                latitude: oldLatitude,
                longitude: oldLongitude,
                arrivalDate: oldDate,
                departureDate: oldDate,
                notes: oldNotes
            )
        ]

        flights = []
        transportationTypes = [.airplane]
        createdAt = oldDate
        updatedAt = oldDate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        try container.encode(
            id,
            forKey: .id
        )

        try container.encode(
            title,
            forKey: .title
        )

        try container.encode(
            startDate,
            forKey: .startDate
        )

        try container.encode(
            endDate,
            forKey: .endDate
        )

        try container.encode(
            notes,
            forKey: .notes
        )

        try container.encode(
            cities,
            forKey: .cities
        )

        try container.encode(
            transportationTypes,
            forKey: .transportationTypes
        )

        try container.encode(
            flights,
            forKey: .flights
        )

        try container.encode(
            isFavorite,
            forKey: .isFavorite
        )

        try container.encode(
            createdAt,
            forKey: .createdAt
        )

        try container.encode(
            updatedAt,
            forKey: .updatedAt
        )
    }
}
