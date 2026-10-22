import Foundation

struct TripDraft: Codable, Equatable {
    var title: String
    var startDate: Date
    var endDate: Date
    var countryCode: String
    var cities: [VisitedCity]
    var transportationTypes: [TransportationType]
    var flights: [Flight]
    var notes: String
    var updatedAt: Date

    var isMeaningful: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !countryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !cities.isEmpty ||
        !transportationTypes.isEmpty ||
        !flights.isEmpty ||
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isExpired: Bool {
        Date().timeIntervalSince(updatedAt) > 86_400
    }

    init(
        title: String,
        startDate: Date,
        endDate: Date,
        countryCode: String,
        cities: [VisitedCity],
        transportationTypes: [TransportationType],
        flights: [Flight],
        notes: String,
        updatedAt: Date
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.countryCode = countryCode
        self.cities = cities
        self.transportationTypes = transportationTypes
        self.flights = flights
        self.notes = notes
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case title, startDate, endDate, countryCode, cities, transportationTypes, flights, notes, updatedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        countryCode = try container.decode(String.self, forKey: .countryCode)
        cities = try container.decode([VisitedCity].self, forKey: .cities)
        transportationTypes = try container.decode([TransportationType].self, forKey: .transportationTypes)
        flights = try container.decode([Flight].self, forKey: .flights)
        notes = try container.decode(String.self, forKey: .notes)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(cities, forKey: .cities)
        try container.encode(transportationTypes, forKey: .transportationTypes)
        try container.encode(flights, forKey: .flights)
        try container.encode(notes, forKey: .notes)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

actor TripDraftStore {
    static let shared = TripDraftStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadDraft() throws -> TripDraft? {
        let url = try draftURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(TripDraft.self, from: data)
    }

    func saveDraft(_ draft: TripDraft) throws {
        let url = try draftURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(draft)
        try data.write(to: url, options: [.atomic])
    }

    func deleteDraft() throws {
        let url = try draftURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func draftURL() throws -> URL {
        let supportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return supportDirectory
            .appendingPathComponent("Drafts", isDirectory: true)
            .appendingPathComponent("new-trip.json")
    }
}
