import Foundation
import CoreLocation

// MARK: - Country Polygon

struct CountryPolygon: Identifiable, Sendable {
    let id: String
    let exterior: [CLLocationCoordinate2D]
    let holes: [[CLLocationCoordinate2D]]

    nonisolated init(
        id: String = UUID().uuidString,
        exterior: [CLLocationCoordinate2D],
        holes: [[CLLocationCoordinate2D]] = []
    ) {
        self.id = id
        self.exterior = exterior
        self.holes = holes.filter {
            $0.count >= 3
        }
    }

    nonisolated var isValid: Bool {
        exterior.count >= 3
    }

    nonisolated var coordinateCount: Int {
        exterior.count +
        holes.reduce(0) { result, ring in
            result + ring.count
        }
    }

    nonisolated var boundingBox: CountryBoundingBox? {
        CountryBoundingBox(coordinates: exterior)
    }

    nonisolated var approximateArea: Double {
        guard exterior.count >= 3 else {
            return 0
        }

        var area = 0.0
        var previous = exterior[exterior.count - 1]

        for current in exterior {
            let averageLatitude = (previous.latitude + current.latitude) / 2
            let latitudeScale = max(cos(averageLatitude * .pi / 180), 0.05)
            let previousX = previous.longitude * latitudeScale
            let currentX = current.longitude * latitudeScale
            area += (previousX * current.latitude) - (currentX * previous.latitude)
            previous = current
        }

        return abs(area) / 2
    }

    nonisolated var centerCoordinate: CLLocationCoordinate2D {
        boundingBox?.center ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    nonisolated func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        guard Self.ringContains(
            coordinate,
            ring: exterior
        ) else {
            return false
        }

        let isInsideHole = holes.contains { hole in
            Self.ringContains(
                coordinate,
                ring: hole
            )
        }

        return !isInsideHole
    }

    nonisolated private static func ringContains(
        _ point: CLLocationCoordinate2D,
        ring: [CLLocationCoordinate2D]
    ) -> Bool {
        guard ring.count >= 3 else {
            return false
        }

        var isInside = false
        var previousIndex = ring.count - 1

        for currentIndex in ring.indices {
            let currentPoint = ring[currentIndex]
            let previousPoint = ring[previousIndex]

            let crossesLatitude =
                (currentPoint.latitude > point.latitude) !=
                (previousPoint.latitude > point.latitude)

            if crossesLatitude {
                let denominator =
                    previousPoint.latitude -
                    currentPoint.latitude

                if denominator != 0 {
                    let intersectionLongitude =
                        (
                            previousPoint.longitude -
                            currentPoint.longitude
                        ) *
                        (
                            point.latitude -
                            currentPoint.latitude
                        ) /
                        denominator +
                        currentPoint.longitude

                    if point.longitude <
                        intersectionLongitude {
                        isInside.toggle()
                    }
                }
            }

            previousIndex = currentIndex
        }

        return isInside
    }
}

// MARK: - Japanese Country Search

enum JapaneseCountryReadingAliases {
    nonisolated static func aliases(
        for iso2: String
    ) -> [String] {
        aliasesByISO2[iso2.uppercased()] ?? []
    }

    nonisolated static func matchingISO2Codes(
        for normalizedQueries: [String]
    ) -> [String] {
        aliasesByISO2.compactMap { iso2, aliases in
            let normalizedAliases = normalizedAliases(for: aliases)
            let matches = normalizedAliases.contains { alias in
                normalizedQueries.contains { query in
                    alias == query || alias.hasPrefix(query)
                }
            }
            return matches ? iso2 : nil
        }
        .sorted()
    }

    private nonisolated static func normalizedAliases(
        for aliases: [String]
    ) -> [String] {
        var normalized: [String] = []
        for alias in aliases {
            normalized.append(
                contentsOf: JapaneseKanaRomajiSearch.normalizedQueryVariants(
                    alias,
                    normalizer: GeoJSONLoader.normalizeSearchText
                )
            )
        }
        return normalized
    }

    private nonisolated static let aliasesByISO2: [String: [String]] = [
        "CN": ["ちゅうごく", "chugoku", "chuugoku"],
        "GB": ["いぎりす", "igirisu", "eikoku"],
        "HK": ["ほんこん", "honkon", "hong kong"],
        "JP": ["にほん", "にっぽん", "nihon", "nippon"],
        "KP": ["きたちょうせん", "kitachosen", "kita chosen"],
        "KR": ["かんこく", "kankoku", "daikanminkoku"],
        "MO": ["まかお", "makao", "macau"],
        "TW": ["たいわん", "taiwan"],
        "US": ["あめりか", "amerika", "beikoku"]
    ]
}

enum CountrySearchRank {
    nonisolated static func priority(
        for iso2: String
    ) -> Int {
        priorityByISO2[iso2.uppercased()] ?? Int.max
    }

    private nonisolated static let priorityByISO2: [String: Int] = [
        "JP": 0,
        "US": 1,
        "GB": 2,
        "FR": 3,
        "IT": 4,
        "ES": 5,
        "DE": 6,
        "KR": 7,
        "TW": 8,
        "TH": 9,
        "SG": 10,
        "AU": 11,
        "CA": 12,
        "CN": 13,
        "HK": 14,
        "VN": 15,
        "ID": 16,
        "MY": 17,
        "PH": 18,
        "AE": 19,
        "TR": 20,
        "NL": 21,
        "CH": 22,
        "AT": 23,
        "BE": 24,
        "SE": 25,
        "NO": 26,
        "DK": 27,
        "FI": 28,
        "NZ": 29,
        "MX": 30,
        "BR": 31,
        "IN": 32,
        "EG": 33,
        "ZA": 34,
        "CU": 35,
        "CY": 36,
        "KG": 37,
        "KI": 38
    ]
}

// MARK: - Bounding Box

struct CountryBoundingBox: Sendable {
    let minimumLatitude: Double
    let maximumLatitude: Double
    let minimumLongitude: Double
    let maximumLongitude: Double

    nonisolated init?(
        coordinates: [CLLocationCoordinate2D]
    ) {
        guard let firstCoordinate =
                coordinates.first else {
            return nil
        }

        var minimumLatitude =
            firstCoordinate.latitude

        var maximumLatitude =
            firstCoordinate.latitude

        var minimumLongitude =
            firstCoordinate.longitude

        var maximumLongitude =
            firstCoordinate.longitude

        for coordinate in
            coordinates.dropFirst() {
            minimumLatitude = min(
                minimumLatitude,
                coordinate.latitude
            )

            maximumLatitude = max(
                maximumLatitude,
                coordinate.latitude
            )

            minimumLongitude = min(
                minimumLongitude,
                coordinate.longitude
            )

            maximumLongitude = max(
                maximumLongitude,
                coordinate.longitude
            )
        }

        self.minimumLatitude =
            minimumLatitude

        self.maximumLatitude =
            maximumLatitude

        self.minimumLongitude =
            minimumLongitude

        self.maximumLongitude =
            maximumLongitude
    }

    nonisolated init?(
        polygons: [CountryPolygon]
    ) {
        let boxes = polygons.compactMap {
            $0.boundingBox
        }

        guard let firstBox =
                boxes.first else {
            return nil
        }

        minimumLatitude =
            boxes.dropFirst().reduce(
                firstBox.minimumLatitude
            ) { result, box in
                min(
                    result,
                    box.minimumLatitude
                )
            }

        maximumLatitude =
            boxes.dropFirst().reduce(
                firstBox.maximumLatitude
            ) { result, box in
                max(
                    result,
                    box.maximumLatitude
                )
            }

        minimumLongitude =
            boxes.dropFirst().reduce(
                firstBox.minimumLongitude
            ) { result, box in
                min(
                    result,
                    box.minimumLongitude
                )
            }

        maximumLongitude =
            boxes.dropFirst().reduce(
                firstBox.maximumLongitude
            ) { result, box in
                max(
                    result,
                    box.maximumLongitude
                )
            }
    }

    nonisolated var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude:
                (
                    minimumLatitude +
                    maximumLatitude
                ) / 2,
            longitude:
                (
                    minimumLongitude +
                    maximumLongitude
                ) / 2
        )
    }

    nonisolated var latitudeSpan: Double {
        maximumLatitude - minimumLatitude
    }

    nonisolated var longitudeSpan: Double {
        maximumLongitude - minimumLongitude
    }

    nonisolated func contains(
        coordinate: CLLocationCoordinate2D
    ) -> Bool {
        coordinate.latitude >=
            minimumLatitude &&
        coordinate.latitude <=
            maximumLatitude &&
        coordinate.longitude >=
            minimumLongitude &&
        coordinate.longitude <=
            maximumLongitude
    }

    nonisolated func expanded(
        byDegrees degrees: Double
    ) -> CountryBoundingBox {
        CountryBoundingBox(
            minimumLatitude: minimumLatitude - degrees,
            maximumLatitude: maximumLatitude + degrees,
            minimumLongitude: minimumLongitude - degrees,
            maximumLongitude: maximumLongitude + degrees
        )
    }

    nonisolated private init(
        minimumLatitude: Double,
        maximumLatitude: Double,
        minimumLongitude: Double,
        maximumLongitude: Double
    ) {
        self.minimumLatitude = minimumLatitude
        self.maximumLatitude = maximumLatitude
        self.minimumLongitude = minimumLongitude
        self.maximumLongitude = maximumLongitude
    }
}

// MARK: - Country

struct Country: Identifiable, Sendable {
    let iso2: String
    let iso3: String
    let continent: String
    let polygonParts: [CountryPolygon]

    nonisolated var id: String { iso2 }

    nonisolated init(
        iso2: String = "",
        iso3: String = "",
        continent: String = "",
        polygonParts: [CountryPolygon]
    ) {
        let cleanedISO2 =
            Self.clean(iso2)
                .uppercased()

        let cleanedISO3 =
            Self.clean(iso3)
                .uppercased()

        self.iso2 = cleanedISO2
        self.iso3 = cleanedISO3

        self.continent =
            Self.clean(continent)

        self.polygonParts =
            polygonParts.filter {
                $0.isValid
            }
    }

    // MARK: - Compatibility Initializer

    nonisolated init(
        name: String,
        isoCode: String = "",
        continent: String = "",
        polygons: [[CLLocationCoordinate2D]]
    ) {
        self.init(
            iso2: isoCode,
            continent: continent,
            polygonParts:
                polygons.map { coordinates in
                    CountryPolygon(
                        exterior:
                            coordinates
                    )
                }
        )
    }

    // MARK: - Compatibility Properties

    nonisolated var isoCode: String { iso2 }
    nonisolated var normalizedISOCode: String { iso2 }
    nonisolated var polygons: [[CLLocationCoordinate2D]] { polygonParts.map(\.exterior) }
    nonisolated var name: String { iso2 }

    // MARK: - Normalized Values

    nonisolated var normalizedName: String { Self.normalize(iso2) }

    // MARK: - Statistics

    nonisolated var polygonCount: Int { polygonParts.count }
    nonisolated var holeCount: Int { polygonParts.reduce(0) { $0 + $1.holes.count } }
    nonisolated var coordinateCount: Int { polygonParts.reduce(0) { $0 + $1.coordinateCount } }
    nonisolated var approximateArea: Double { polygonParts.reduce(0) { $0 + $1.approximateArea } }

    // MARK: - Geography

    nonisolated var fullGeometryBounds: CountryBoundingBox? { CountryBoundingBox(polygons: polygonParts) }

    nonisolated var searchBoundingBox: CountryBoundingBox? {
        polygonParts
            .max { first, second in
                first.approximateArea < second.approximateArea
            }?
            .boundingBox ?? fullGeometryBounds
    }

    nonisolated var boundingBox: CountryBoundingBox? { fullGeometryBounds }

    nonisolated var centerCoordinate: CLLocationCoordinate2D {
        searchBoundingBox?.center ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    nonisolated func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        if let fullGeometryBounds,
           !fullGeometryBounds.contains(
                coordinate: coordinate
           ) {
            return false
        }

        return polygonParts.contains {
            polygon in

            polygon.contains(
                coordinate: coordinate
            )
        }
    }

    nonisolated func isNearSmallGeometry(coordinate: CLLocationCoordinate2D) -> Bool {
        guard let bounds = fullGeometryBounds else {
            return false
        }

        let largestSpan = max(bounds.latitudeSpan, bounds.longitudeSpan)
        guard largestSpan <= 1.2 else {
            return false
        }

        let expansion = max(min(0.18, largestSpan * 0.85), 0.04)
        return bounds.expanded(byDegrees: expansion).contains(coordinate: coordinate)
    }

    // MARK: - Matching

    nonisolated func matches(nameOrCode value: String) -> Bool {
        let normalizedValue =
            Self.normalize(value)

        guard !normalizedValue.isEmpty else {
            return false
        }

        return
            Self.normalize(iso2) ==
                normalizedValue ||
            Self.normalize(iso3) ==
                normalizedValue
    }

    // MARK: - Display Name (localized via system Locale; @MainActor because Locale.current is main-actor)

    @MainActor var displayName: String {
        WanderlustNameResolver.countryName(for: iso2)
    }

    // MARK: - Flag

    nonisolated var flagEmoji: String {
        guard iso2.count == 2 else {
            return "🌍"
        }

        let scalars =
            iso2.unicodeScalars
                .compactMap { scalar in
                    UnicodeScalar(
                        127397 +
                        scalar.value
                    )
                }

        guard scalars.count == 2 else {
            return "🌍"
        }

        return String(
            String.UnicodeScalarView(
                scalars
            )
        )
    }

    // MARK: - Helpers

    nonisolated private static func clean(
        _ text: String
    ) -> String {
        text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    nonisolated private static func normalize(
        _ text: String
    ) -> String {
        text
            .trimmingCharacters(
                in: .whitespacesAndNewlines
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
            .replacingOccurrences(
                of: "’",
                with: "'"
            )
            .replacingOccurrences(
                of: "-",
                with: " "
            )
            .replacingOccurrences(
                of: "'",
                with: ""
            )
            .lowercased()
    }
}
