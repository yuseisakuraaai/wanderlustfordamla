import Foundation
import Combine
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct GuestMergeResult: Codable, Equatable {
    let addedTripCount: Int
    let mergedTripCount: Int
    let unchangedTripCount: Int
    let failedTripCount: Int
}

private struct GuestMergeBackupEnvelope: Codable {
    let schemaVersion: Int
    let startedAt: Date
    let userID: String
    let guestTrips: [Trip]
    let accountTrips: [Trip]
}

@MainActor
final class TripStore: ObservableObject {
    static let shared = TripStore()

    @Published private(set) var trips: [Trip] = []
    @Published private(set) var tripGroups: [TripGroup] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var isCloudSyncing = false
    @Published private(set) var isMergingGuestData = false
    @Published private(set) var lastGuestMergeResult: GuestMergeResult?
    @Published private(set) var lastGuestMergeError: String?
    @Published private(set) var syncState: SyncState = .idle
    @Published var lastErrorMessage: String?

    private let userDefaults: UserDefaults
    private let storageKey = "trips"
    private let tripGroupsStorageKey = "tripGroups"
    private var activeCloudUID: String?
    private var cloudSyncTask: Task<Void, Never>?
    private var isApplyingCloudSnapshot = false
    private var suppressCloudUpload = false
    private var hasCompletedInitialCloudRestore = false

    init(
        userDefaults: UserDefaults = .standard
    ) {
        self.userDefaults = userDefaults
        load()
    }

    // MARK: - Loading

    func load() {
        lastErrorMessage = nil
        #if DEBUG
        let start = CFAbsoluteTimeGetCurrent()
        #endif

        guard let data = userDefaults.data(
            forKey: storageKey
        ) else {
            trips = []
            tripGroups = []
            isLoaded = true
            #if DEBUG
            print(String(format: "[WanderlustPerformance] trip_decode %.1fms 0 trips", (CFAbsoluteTimeGetCurrent() - start) * 1000))
            #endif
            return
        }

        do {
            let decodedTrips = try JSONDecoder().decode(
                [Trip].self,
                from: data
            )

            let migratedTrips = normalizeStoredIdentifiers(in: decodedTrips)

            trips = migratedTrips.sorted {
                $0.startDate > $1.startDate
            }
            tripGroups = reconciledTripGroups(loadTripGroups(), with: trips)

            isLoaded = true
            if migratedTrips != decodedTrips {
                _ = save()
            } else {
                saveTripGroups()
            }
            #if DEBUG
            WanderlustDiagnostics.info(String(format: "trip_decode %.1fms %d trips", (CFAbsoluteTimeGetCurrent() - start) * 1000, migratedTrips.count), category: .performance)
            #endif
        } catch {
            trips = []
            tripGroups = []
            isLoaded = true

            lastErrorMessage = """
            Trip data could not be loaded:
            \(error.localizedDescription)
            """

            WanderlustDiagnostics.error(error, category: .storage, message: "TripStore load failed")
        }
    }

    func reload() {
        load()
    }

    func migrateStoredNamesIfPossible() {
        let migratedTrips = normalizeStoredIdentifiers(in: trips)
        guard migratedTrips != trips else { return }
        trips = migratedTrips.sorted { $0.startDate > $1.startDate }
        _ = save()
    }

    private func normalizeStoredIdentifiers(in sourceTrips: [Trip]) -> [Trip] {
        return sourceTrips.map { trip in
            var migratedTrip = trip
            migratedTrip.flights = trip.flights.normalizedFlightList()
            migratedTrip.cities = trip.cities.map { city in
                var migratedCity = city
                let resolvedCountryCode = WanderlustNameResolver.countryCode(
                    from: migratedCity.countryCode,
                    fallback: migratedCity.countryName
                )
                if !resolvedCountryCode.isEmpty {
                    migratedCity.countryCode = resolvedCountryCode
                }

                return migratedCity
            }
            return migratedTrip
        }
    }

    private func loadTripGroups() -> [TripGroup] {
        guard let data = userDefaults.data(forKey: tripGroupsStorageKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([TripGroup].self, from: data)
        } catch {
            WanderlustDiagnostics.warning("trip group load skipped: \(error.localizedDescription)", category: .storage)
            return []
        }
    }

    private func saveTripGroups() {
        do {
            let data = try JSONEncoder().encode(tripGroups)
            userDefaults.set(data, forKey: tripGroupsStorageKey)
            saveUserScopedTripGroupsCacheIfNeeded(data)
        } catch {
            WanderlustDiagnostics.error(error, category: .storage, message: "TripStore group save failed")
        }
    }

    private func reconciledTripGroups(_ sourceGroups: [TripGroup], with sourceTrips: [Trip]) -> [TripGroup] {
        let validTripIDs = Set(sourceTrips.map(\.id))
        var groupedTripIDs = Set<UUID>()
        var groups: [TripGroup] = []

        for sourceGroup in sourceGroups {
            let cleanedTripIDs = sourceGroup.tripIDs.filter { validTripIDs.contains($0) }
            guard !cleanedTripIDs.isEmpty else { continue }

            var group = sourceGroup
            group.tripIDs = cleanedTripIDs
            groups.append(group)
            groupedTripIDs.formUnion(cleanedTripIDs)
        }

        for trip in sourceTrips where !groupedTripIDs.contains(trip.id) {
            groups.append(TripGroup.singleTripGroup(for: trip))
        }

        return sortedTripGroups(groups, trips: sourceTrips)
    }

    private func sortedTripGroups(_ groups: [TripGroup], trips sourceTrips: [Trip]) -> [TripGroup] {
        let tripsByID = Dictionary(
            sourceTrips.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return groups.sorted { lhs, rhs in
            let lhsDate = lhs.tripIDs.compactMap { tripsByID[$0]?.startDate }.min() ?? lhs.createdAt
            let rhsDate = rhs.tripIDs.compactMap { tripsByID[$0]?.startDate }.min() ?? rhs.createdAt
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func validUniqueTripIDs(_ tripIDs: [UUID]) -> [UUID] {
        let validTripIDs = Set(trips.map(\.id))
        var seen = Set<UUID>()
        return tripIDs.filter { validTripIDs.contains($0) && seen.insert($0).inserted }
    }

    private func defaultGroupTitle(for tripIDs: [UUID]) -> String {
        let selectedTrips = tripIDs.compactMap { id in
            trips.first { $0.id == id }
        }

        if let firstDate = selectedTrips.map(\.startDate).min() {
            let lastDate = selectedTrips.map(\.endDate).max() ?? firstDate
            return WanderlustDateFormatter.dateRange(start: firstDate, end: lastDate)
        }

        return WanderlustL10n.string("New Journey", table: .trips, fallback: "New Journey")
    }

    // MARK: - Saving

    @discardableResult
    func save() -> Bool {
        lastErrorMessage = nil

        do {
            let data = try JSONEncoder().encode(
                trips
            )

            userDefaults.set(
                data,
                forKey: storageKey
            )

            tripGroups = reconciledTripGroups(tripGroups, with: trips)
            saveTripGroups()
            saveUserScopedCacheIfNeeded(data)
            scheduleCloudUploadIfNeeded()

            return true
        } catch {
            lastErrorMessage = """
            Trip data could not be saved:
            \(error.localizedDescription)
            """

            WanderlustDiagnostics.error(error, category: .storage, message: "TripStore save failed")

            return false
        }
    }

    // MARK: - Trip CRUD

    @discardableResult
    func addTrip(
        _ trip: Trip
    ) -> Bool {
        addTrip(trip, toTripGroupID: nil)
    }

    @discardableResult
    func addTrip(
        _ trip: Trip,
        toTripGroupID tripGroupID: UUID?
    ) -> Bool {
        guard !trips.contains(
            where: {
                $0.id == trip.id
            }
        ) else {
            lastErrorMessage = """
            A trip with the same ID already exists.
            """
            return false
        }

        trips.append(trip)
        sortTrips()
        if let tripGroupID,
           let groupIndex = tripGroups.firstIndex(where: { $0.id == tripGroupID }) {
            tripGroups[groupIndex].tripIDs.append(trip.id)
            tripGroups[groupIndex].updatedAt = Date()
        }
        tripGroups = reconciledTripGroups(tripGroups, with: trips)

        let saved = save()
        if saved {
            enqueueTripSync(trip, operation: .create)
            if let tripGroupID,
               let group = tripGroups.first(where: { $0.id == tripGroupID }) {
                enqueueTripGroupSync(group, operation: .update)
            }
        }
        return saved
    }

    @discardableResult
    func updateTrip(
        _ trip: Trip
    ) -> Bool {
        guard let index = trips.firstIndex(
            where: {
                $0.id == trip.id
            }
        ) else {
            lastErrorMessage = """
            The selected trip could not be found.
            """
            return false
        }

        var updatedTrip = trip
        updatedTrip.updatedAt = Date()
        trips[index] = updatedTrip
        sortTrips()
        tripGroups = reconciledTripGroups(tripGroups, with: trips)

        let saved = save()
        if saved {
            enqueueTripSync(updatedTrip, operation: .update)
        }
        return saved
    }

    @discardableResult
    func deleteTrip(
        _ trip: Trip
    ) -> Bool {
        deleteTrip(
            id: trip.id
        )
    }

    @discardableResult
    func deleteTrip(
        id: UUID
    ) -> Bool {
        guard trips.contains(
            where: {
                $0.id == id
            }
        ) else {
            lastErrorMessage = """
            The selected trip could not be found.
            """
            return false
        }

        trips.removeAll {
            $0.id == id
        }
        tripGroups = reconciledTripGroups(tripGroups, with: trips)

        let saved = save()
        if saved {
            SyncQueueStore.shared.enqueue(
                entityType: .trip,
                entityId: id.uuidString,
                operationType: .delete
            )
            deleteCloudTrip(id: id)
        }
        return saved
    }

    func trip(
        withID id: UUID
    ) -> Trip? {
        trips.first {
            $0.id == id
        }
    }

    func trips(in group: TripGroup) -> [Trip] {
        let tripsByID = Dictionary(
            trips.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return group.tripIDs.compactMap { tripsByID[$0] }
    }

    @discardableResult
    func addTripGroup(title: String, notes: String = "", tripIDs: [UUID]) -> Bool {
        let validTripIDs = validUniqueTripIDs(tripIDs)
        guard !validTripIDs.isEmpty else {
            lastErrorMessage = WanderlustL10n.string(
                "Select at least one trip.",
                table: .trips,
                fallback: "Select at least one trip."
            )
            return false
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = TripGroup(
            title: trimmedTitle.isEmpty ? defaultGroupTitle(for: validTripIDs) : trimmedTitle,
            notes: notes,
            tripIDs: validTripIDs
        )

        tripGroups = tripGroups.compactMap { existingGroup in
            var group = existingGroup
            group.tripIDs.removeAll { validTripIDs.contains($0) }
            return group.tripIDs.isEmpty ? nil : group
        }
        tripGroups.append(group)
        tripGroups = reconciledTripGroups(tripGroups, with: trips)
        saveTripGroups()
        enqueueTripGroupSync(group, operation: .create)
        scheduleCloudUploadIfNeeded()
        objectWillChange.send()
        return true
    }

    @discardableResult
    func updateTripGroup(id: UUID, title: String, notes: String? = nil, tripIDs: [UUID]) -> Bool {
        guard let index = tripGroups.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let validTripIDs = validUniqueTripIDs(tripIDs)
        guard !validTripIDs.isEmpty else {
            lastErrorMessage = WanderlustL10n.string(
                "Select at least one trip.",
                table: .trips,
                fallback: "Select at least one trip."
            )
            return false
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingGroup = tripGroups[index]
        let updatedGroup = TripGroup(
            id: existingGroup.id,
            title: trimmedTitle.isEmpty ? defaultGroupTitle(for: validTripIDs) : trimmedTitle,
            notes: notes ?? existingGroup.notes,
            tripIDs: validTripIDs,
            transportItems: existingGroup.transportItems,
            createdAt: existingGroup.createdAt,
            updatedAt: Date()
        )

        tripGroups = tripGroups.compactMap { group in
            if group.id == id {
                return updatedGroup
            }

            var remainingGroup = group
            remainingGroup.tripIDs.removeAll { validTripIDs.contains($0) }
            remainingGroup.updatedAt = Date()
            return remainingGroup.tripIDs.isEmpty ? nil : remainingGroup
        }
        tripGroups = reconciledTripGroups(tripGroups, with: trips)
        saveTripGroups()
        if let group = tripGroups.first(where: { $0.id == id }) {
            enqueueTripGroupSync(group, operation: .update)
        }
        scheduleCloudUploadIfNeeded()
        return true
    }

    @discardableResult
    func addTrip(_ tripID: UUID, toTripGroupID tripGroupID: UUID) -> Bool {
        guard trips.contains(where: { $0.id == tripID }),
              let index = tripGroups.firstIndex(where: { $0.id == tripGroupID }) else {
            return false
        }

        if !tripGroups[index].tripIDs.contains(tripID) {
            tripGroups[index].tripIDs.append(tripID)
        }
        tripGroups[index].updatedAt = Date()
        tripGroups = reconciledTripGroups(tripGroups, with: trips)
        saveTripGroups()
        if let group = tripGroups.first(where: { $0.id == tripGroupID }) {
            enqueueTripGroupSync(group, operation: .update)
        }
        scheduleCloudUploadIfNeeded()
        return true
    }

    @discardableResult
    func removeTrip(_ tripID: UUID, fromTripGroupID tripGroupID: UUID) -> Bool {
        guard let index = tripGroups.firstIndex(where: { $0.id == tripGroupID }) else {
            return false
        }

        tripGroups[index].tripIDs.removeAll { $0 == tripID }
        tripGroups[index].updatedAt = Date()
        tripGroups = reconciledTripGroups(tripGroups, with: trips)
        saveTripGroups()
        if let group = tripGroups.first(where: { $0.id == tripGroupID }) {
            enqueueTripGroupSync(group, operation: .update)
        }
        scheduleCloudUploadIfNeeded()
        return true
    }

    @discardableResult
    func addTransportItem(_ item: TripGroupTransportItem, toTripGroupID tripGroupID: UUID) -> Bool {
        guard let index = tripGroups.firstIndex(where: { $0.id == tripGroupID }) else {
            return false
        }

        tripGroups[index].transportItems.append(item)
        tripGroups[index].transportItems = tripGroups[index].transportItems.sortedByDate()
        tripGroups[index].updatedAt = Date()
        saveTripGroups()
        enqueueTripGroupSync(tripGroups[index], operation: .update)
        scheduleCloudUploadIfNeeded()
        return true
    }

    @discardableResult
    func updateTransportItem(_ item: TripGroupTransportItem, inTripGroupID tripGroupID: UUID) -> Bool {
        guard let groupIndex = tripGroups.firstIndex(where: { $0.id == tripGroupID }),
              let itemIndex = tripGroups[groupIndex].transportItems.firstIndex(where: { $0.id == item.id }) else {
            return false
        }

        var updatedItem = item
        updatedItem.updatedAt = Date()
        tripGroups[groupIndex].transportItems[itemIndex] = updatedItem
        tripGroups[groupIndex].transportItems = tripGroups[groupIndex].transportItems.sortedByDate()
        tripGroups[groupIndex].updatedAt = Date()
        saveTripGroups()
        enqueueTripGroupSync(tripGroups[groupIndex], operation: .update)
        scheduleCloudUploadIfNeeded()
        return true
    }

    @discardableResult
    func deleteTransportItem(id itemID: UUID, fromTripGroupID tripGroupID: UUID) -> Bool {
        guard let index = tripGroups.firstIndex(where: { $0.id == tripGroupID }) else {
            return false
        }

        tripGroups[index].transportItems.removeAll { $0.id == itemID }
        tripGroups[index].updatedAt = Date()
        saveTripGroups()
        enqueueTripGroupSync(tripGroups[index], operation: .update)
        scheduleCloudUploadIfNeeded()
        return true
    }

    @discardableResult
    func deleteTripGroup(id: UUID) -> Bool {
        guard tripGroups.contains(where: { $0.id == id }) else {
            return false
        }

        tripGroups.removeAll { $0.id == id }
        tripGroups = reconciledTripGroups(tripGroups, with: trips)
        saveTripGroups()
        SyncQueueStore.shared.enqueue(
            entityType: .tripGroup,
            entityId: id.uuidString,
            operationType: .delete
        )
        deleteCloudTripGroup(id: id)
        return true
    }

    @discardableResult
    func replaceTrips(
        _ newTrips: [Trip]
    ) -> Bool {
        trips = newTrips.sorted {
            $0.startDate > $1.startDate
        }
        tripGroups = reconciledTripGroups(tripGroups, with: trips)
        isLoaded = true
        return save()
    }

    @discardableResult
    func mergeRestoredTrips(
        _ restoredTrips: [Trip]
    ) -> Bool {
        trips = WanderlustConflictResolver
            .mergedTripsByID(
                localTrips: trips,
                remoteTrips: restoredTrips
            )
            .sorted {
                $0.startDate > $1.startDate
            }
        tripGroups = reconciledTripGroups(tripGroups, with: trips)
        isLoaded = true
        return save()
    }

    func activateCloudSync(for uid: String) {
        guard !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        activeCloudUID = uid
        cloudSyncTask?.cancel()
        hasCompletedInitialCloudRestore = false
        suppressCloudUpload = true
        isLoaded = false
        trips = []
        SyncQueueStore.shared.activate(for: uid)
        loadUserScopedCache(uid: uid)
        syncState = .syncing
        cloudSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.restoreTripsFromCloud(uid: uid)
            await self.processQueuedCloudOperations(uid: uid)
        }
    }

    func deactivateCloudSync() {
        activeCloudUID = nil
        cloudSyncTask?.cancel()
        cloudSyncTask = nil
        hasCompletedInitialCloudRestore = false
        suppressCloudUpload = false
        SyncQueueStore.shared.deactivate()
        load()
    }

    func performDeferredCloudSync() async -> Bool {
        guard let uid = activeCloudUID ?? currentFirebaseUID else { return false }
        activeCloudUID = uid
        await restoreTripsFromCloud(uid: uid)
        await processQueuedCloudOperations(uid: uid)
        return true
    }

    // MARK: - City CRUD

    @discardableResult
    func addCity(
        _ city: VisitedCity,
        toTripID tripID: UUID
    ) -> Bool {
        guard let tripIndex = trips.firstIndex(
            where: {
                $0.id == tripID
            }
        ) else {
            lastErrorMessage = """
            The trip could not be found.
            """
            return false
        }

        guard !trips[tripIndex].cities.contains(
            where: {
                $0.id == city.id
            }
        ) else {
            lastErrorMessage = """
            This city already exists in the trip.
            """
            return false
        }

        trips[tripIndex].cities.append(city)

        sortCities(
            inTripAt: tripIndex
        )

        return save()
    }

    @discardableResult
    func updateCity(
        _ city: VisitedCity,
        inTripID tripID: UUID
    ) -> Bool {
        guard let tripIndex = trips.firstIndex(
            where: {
                $0.id == tripID
            }
        ) else {
            lastErrorMessage = """
            The trip could not be found.
            """
            return false
        }

        guard let cityIndex = trips[
            tripIndex
        ]
            .cities
            .firstIndex(
                where: {
                    $0.id == city.id
                }
            )
        else {
            lastErrorMessage = """
            The selected city could not be found.
            """
            return false
        }

        trips[tripIndex]
            .cities[cityIndex] = city

        sortCities(
            inTripAt: tripIndex
        )

        return save()
    }

    @discardableResult
    func deleteCity(
        _ city: VisitedCity,
        fromTripID tripID: UUID
    ) -> Bool {
        deleteCity(
            cityID: city.id,
            fromTripID: tripID
        )
    }

    @discardableResult
    func deleteCity(
        cityID: UUID,
        fromTripID tripID: UUID
    ) -> Bool {
        guard let tripIndex = trips.firstIndex(
            where: {
                $0.id == tripID
            }
        ) else {
            lastErrorMessage = """
            The trip could not be found.
            """
            return false
        }

        guard trips[tripIndex].cities.contains(
            where: {
                $0.id == cityID
            }
        ) else {
            lastErrorMessage = """
            The selected city could not be found.
            """
            return false
        }

        trips[tripIndex].cities.removeAll {
            $0.id == cityID
        }

        return save()
    }

    // MARK: - Flight CRUD

    @discardableResult
    func addFlight(
        _ flight: Flight,
        toTripID tripID: UUID
    ) -> Bool {
        guard let tripIndex = trips.firstIndex(
            where: {
                $0.id == tripID
            }
        ) else {
            lastErrorMessage = """
            The trip could not be found.
            """
            return false
        }

        guard !trips[tripIndex].flights.contains(
            where: {
                $0.id == flight.id
            }
        ) else {
            lastErrorMessage = """
            This flight already exists in the trip.
            """
            return false
        }

        trips[tripIndex].flights.append(
            flight
        )

        sortFlights(
            inTripAt: tripIndex
        )

        return save()
    }

    @discardableResult
    func updateFlight(
        _ flight: Flight,
        inTripID tripID: UUID
    ) -> Bool {
        guard let tripIndex = trips.firstIndex(
            where: {
                $0.id == tripID
            }
        ) else {
            lastErrorMessage = """
            The trip could not be found.
            """
            return false
        }

        guard let flightIndex = trips[
            tripIndex
        ]
            .flights
            .firstIndex(
                where: {
                    $0.id == flight.id
                }
            )
        else {
            lastErrorMessage = """
            The selected flight could not be found.
            """
            return false
        }

        trips[tripIndex]
            .flights[flightIndex] = flight

        sortFlights(
            inTripAt: tripIndex
        )

        return save()
    }

    @discardableResult
    func deleteFlight(
        _ flight: Flight,
        fromTripID tripID: UUID
    ) -> Bool {
        deleteFlight(
            flightID: flight.id,
            fromTripID: tripID
        )
    }

    @discardableResult
    func deleteFlight(
        flightID: UUID,
        fromTripID tripID: UUID
    ) -> Bool {
        guard let tripIndex = trips.firstIndex(
            where: {
                $0.id == tripID
            }
        ) else {
            lastErrorMessage = """
            The trip could not be found.
            """
            return false
        }

        guard trips[tripIndex].flights.contains(
            where: {
                $0.id == flightID
            }
        ) else {
            lastErrorMessage = """
            The selected flight could not be found.
            """
            return false
        }

        trips[tripIndex].flights.removeAll {
            $0.id == flightID
        }

        return save()
    }

    // MARK: - Country Queries

    // NOTE: 旧 `visitedCountryNames` / `visitedCountryCodes` は削除した（参照なし）。
    // 訪問国の同定・件数は `VisitedCountryAggregator` に一本化している。

    var visitedCities: [VisitedCity] {
        var uniqueCities:
            [String: VisitedCity] = [:]

        for city in trips.flatMap({
            $0.cities
        }) {
            let key = cityDeduplicationKey(
                city
            )

            if uniqueCities[key] == nil {
                uniqueCities[key] = city
            }
        }

        return uniqueCities.values.sorted {
            if $0.localizedCountryName !=
                $1.localizedCountryName {
                return $0.localizedCountryName
                    .localizedCaseInsensitiveCompare(
                        $1.localizedCountryName
                    ) == .orderedAscending
            }

            return $0.localizedName
                .localizedCaseInsensitiveCompare(
                    $1.localizedName
                ) == .orderedAscending
        }
    }

    func cities(
        inCountry countryCode: String
    ) -> [VisitedCity] {
        let normalizedCountryCode = clean(
            countryCode
        )
        .uppercased()

        guard !normalizedCountryCode.isEmpty else { return [] }

        return visitedCities.filter { city in
            clean(city.countryCode)
                .uppercased() == normalizedCountryCode
        }
    }

    func trips(
        visitingCountry countryCode: String
    ) -> [Trip] {
        let normalizedCountryCode = clean(
            countryCode
        )
        .uppercased()

        guard !normalizedCountryCode.isEmpty else { return [] }

        return trips
            .filter { trip in
                trip.cities.contains { city in
                    clean(city.countryCode)
                        .uppercased() == normalizedCountryCode
                }
            }
            .sorted {
                $0.startDate > $1.startDate
            }
    }

    func trips(
        visitingCity city: VisitedCity
    ) -> [Trip] {
        trips
            .filter { trip in
                trip.cities.contains {
                    citiesMatch(
                        $0,
                        city
                    )
                }
            }
            .sorted {
                $0.startDate > $1.startDate
            }
    }

    func trips(
        visitingCityNamed cityName: String,
        countryCode: String? = nil
    ) -> [Trip] {
        let normalizedCityName = normalize(
            cityName
        )

        let normalizedCountryCode = clean(
            countryCode ?? ""
        )
        .uppercased()

        return trips
            .filter { trip in
                trip.cities.contains { city in
                    let nameMatches =
                        normalize(
                            city.name
                        ) == normalizedCityName

                    guard nameMatches else {
                        return false
                    }

                    if normalizedCountryCode.isEmpty {
                        return true
                    }

                    return clean(
                        city.countryCode
                    )
                    .uppercased() ==
                    normalizedCountryCode
                }
            }
            .sorted {
                $0.startDate > $1.startDate
            }
    }

    // MARK: - Statistics

    var tripCount: Int {
        trips.count
    }

    /// 訪問国数。World / Trips / Passport / Statistics と必ず一致させるため
    /// `VisitedCountryAggregator` を唯一の正とする。
    ///
    /// 以前は「ISO コードの件数が 0 より大きければそれ、さもなくば国名の件数」
    /// という実装で、コード付きの都市とコードなしの都市が混在すると
    /// 片方が丸ごと欠落していた。
    var countryCount: Int {
        VisitedCountryAggregator.visitedCountryCount(in: trips)
    }

    var cityCount: Int {
        visitedCities.count
    }

    var flightCount: Int {
        trips.reduce(0) {
            $0 + $1.flights.count
        }
    }

    // MARK: - Favorites

    @discardableResult
    func toggleFavorite(
        tripID: UUID
    ) -> Bool {
        guard let index = trips.firstIndex(
            where: {
                $0.id == tripID
            }
        ) else {
            lastErrorMessage = """
            The selected trip could not be found.
            """
            return false
        }

        trips[index].isFavorite.toggle()

        return save()
    }

    // MARK: - Data Management

    @discardableResult
    func replaceAllTrips(
        with newTrips: [Trip]
    ) -> Bool {
        trips = newTrips
        sortTrips()

        return save()
    }

    func deleteAllTrips() {
        trips = []

        userDefaults.removeObject(
            forKey: storageKey
        )

        lastErrorMessage = nil
    }

    func clearError() {
        lastErrorMessage = nil
    }

    func clearGuestMergeStatus() {
        lastGuestMergeResult = nil
        lastGuestMergeError = nil
    }

    // MARK: - Cloud Sync

    private func scheduleCloudUploadIfNeeded() {
        guard !isApplyingCloudSnapshot,
              !suppressCloudUpload,
              !isMergingGuestData,
              hasCompletedInitialCloudRestore,
              let uid = activeCloudUID ?? currentFirebaseUID else {
            return
        }

        activeCloudUID = uid
        let snapshot = trips
        let groupSnapshot = tripGroups
        cloudSyncTask?.cancel()
        cloudSyncTask = Task { [weak self] in
            await self?.uploadTripsToCloud(snapshot, tripGroups: groupSnapshot, uid: uid)
        }
    }

    private func restoreTripsFromCloud(uid: String) async {
        #if canImport(FirebaseFirestore)
        guard currentFirebaseUID == uid else { return }
        isCloudSyncing = true
        syncState = .syncing
        defer { isCloudSyncing = false }

        do {
            WanderlustDiagnostics.info("cloud trip fetch started", category: .sync)
            let cloudTrips = try await fetchCloudTrips(uid: uid)
            let cloudTripGroups = try await fetchCloudTripGroups(uid: uid)
            WanderlustDiagnostics.info("cloud trip fetch completed count=\(cloudTrips.count)", category: .sync)
            let localBeforeMergeCount = trips.count

            if cloudTrips.isEmpty {
                if trips.isEmpty {
                    loadUserScopedCache(uid: uid)
                }
                tripGroups = reconciledTripGroups(
                    mergeTripGroups(localGroups: tripGroups, cloudGroups: cloudTripGroups),
                    with: trips
                )
                hasCompletedInitialCloudRestore = true
                suppressCloudUpload = false
                if !trips.isEmpty {
                    await uploadTripsToCloud(trips, tripGroups: tripGroups, uid: uid)
                }
                syncState = .synced(Date())
                return
            }

            let merged = merge(localTrips: trips, cloudTrips: cloudTrips)
            WanderlustDiagnostics.info(
                "cloud trip merge local=\(localBeforeMergeCount) remote=\(cloudTrips.count) merged=\(merged.count)",
                category: .sync
            )
            createLocalBackup(reason: "before-cloud-merge")
            isApplyingCloudSnapshot = true
            trips = merged.sorted { $0.startDate > $1.startDate }
            tripGroups = reconciledTripGroups(
                mergeTripGroups(localGroups: tripGroups, cloudGroups: cloudTripGroups),
                with: trips
            )
            isLoaded = true
            _ = save()
            isApplyingCloudSnapshot = false
            hasCompletedInitialCloudRestore = true
            suppressCloudUpload = false
            await uploadTripsToCloud(trips, tripGroups: tripGroups, uid: uid)
            await processQueuedCloudOperations(uid: uid)
        } catch {
            syncState = .failed(FirebaseErrorMapper.message(for: error))
            WanderlustDiagnostics.error(error, category: .sync, message: "cloud restore failed")
            if trips.isEmpty {
                loadUserScopedCache(uid: uid)
            }
            isLoaded = true
        }
        #endif
    }

    private func uploadTripsToCloud(_ snapshot: [Trip], tripGroups groupSnapshot: [TripGroup]? = nil, uid: String) async {
        #if canImport(FirebaseFirestore)
        guard currentFirebaseUID == uid else { return }
        guard hasCompletedInitialCloudRestore || !snapshot.isEmpty else {
            WanderlustDiagnostics.warning("blocked empty trip upload before initial cloud restore", category: .sync)
            return
        }
        isCloudSyncing = true
        syncState = .syncing
        defer { isCloudSyncing = false }

        do {
            try await uploadTripsToCloudThrowing(snapshot, uid: uid)
            try await uploadTripGroupsToCloudThrowing(groupSnapshot ?? tripGroups, uid: uid)
            syncState = .synced(Date())
            await processQueuedCloudOperations(uid: uid)
        } catch {
            syncState = .failed(FirebaseErrorMapper.message(for: error))
            WanderlustDiagnostics.error(error, category: .sync, message: "cloud upload failed")
            for trip in snapshot {
                enqueueTripSync(trip, operation: .update)
            }
            for group in groupSnapshot ?? tripGroups {
                enqueueTripGroupSync(group, operation: .update)
            }
        }
        #endif
    }

    func mergeGuestTripsIntoCloudAccount(guestTrips: [Trip], uid: String) async -> GuestMergeResult? {
        #if canImport(FirebaseFirestore)
        guard currentFirebaseUID == uid else { return nil }
        guard !isMergingGuestData else { return lastGuestMergeResult }

        isMergingGuestData = true
        suppressCloudUpload = true
        isCloudSyncing = true
        syncState = .syncing
        lastGuestMergeResult = nil
        lastGuestMergeError = nil
        cloudSyncTask?.cancel()
        cloudSyncTask = nil

        defer {
            isMergingGuestData = false
            suppressCloudUpload = false
            isCloudSyncing = false
        }

        do {
            let accountTrips = try await fetchCloudTrips(uid: uid)
            let accountTripGroups = try await fetchCloudTripGroups(uid: uid)
            let guestTripGroups = tripGroups
            createGuestMergeBackup(guestTrips: guestTrips, accountTrips: accountTrips, uid: uid)

            let output = WanderlustConflictResolver.mergeGuestTrips(
                guestTrips: guestTrips,
                accountTrips: accountTrips
            )

            let mergedTrips = output.trips.sorted { $0.startDate > $1.startDate }
            let mergedTripGroups = reconciledTripGroups(
                mergeTripGroups(localGroups: guestTripGroups, cloudGroups: accountTripGroups),
                with: mergedTrips
            )
            try await uploadTripsToCloudThrowing(mergedTrips, uid: uid)
            try await uploadTripGroupsToCloudThrowing(mergedTripGroups, uid: uid)

            isApplyingCloudSnapshot = true
            trips = mergedTrips
            tripGroups = mergedTripGroups
            isLoaded = true
            _ = save()
            isApplyingCloudSnapshot = false

            SyncQueueStore.shared.removeOperations(entityType: .trip)
            SyncQueueStore.shared.removeOperations(entityType: .tripGroup)
            syncState = .synced(Date())

            let result = GuestMergeResult(
                addedTripCount: output.summary.addedTripCount,
                mergedTripCount: output.summary.mergedTripCount,
                unchangedTripCount: output.summary.unchangedTripCount,
                failedTripCount: output.summary.failedTripCount
            )
            lastGuestMergeResult = result
            return result
        } catch {
            isApplyingCloudSnapshot = false
            syncState = .failed(FirebaseErrorMapper.message(for: error))
            lastGuestMergeError = WanderlustL10n.string(
                "Data merge failed. Your guest data has not been deleted.",
                table: .errors,
                fallback: "Data merge failed. Your guest data has not been deleted."
            )
            WanderlustDiagnostics.error(error, category: .sync, message: "guest account merge failed")
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(FirebaseFirestore)
    private func fetchCloudTrips(uid: String) async throws -> [Trip] {
        guard currentFirebaseUID == uid else { return [] }
        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("trips")
            .getDocuments()

        return try snapshot.documents.compactMap { document in
            try Self.trip(fromFirestoreData: document.data())
        }
    }

    private func fetchCloudTripGroups(uid: String) async throws -> [TripGroup] {
        guard currentFirebaseUID == uid else { return [] }
        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("tripGroups")
            .getDocuments()

        return try snapshot.documents.compactMap { document in
            try Self.tripGroup(fromFirestoreData: document.data())
        }
    }

    private func uploadTripsToCloudThrowing(_ snapshot: [Trip], uid: String) async throws {
        guard currentFirebaseUID == uid else { return }
        let db = Firestore.firestore()
        let batch = db.batch()
        let now = Timestamp(date: Date())
        for trip in snapshot {
            var data = try Self.firestoreData(from: trip, ownerUID: uid)
            data["updatedAt"] = Timestamp(date: trip.updatedAt)
            data["syncedAt"] = now
            let document = db
                .collection("users")
                .document(uid)
                .collection("trips")
                .document(trip.id.uuidString)
            batch.setData(data, forDocument: document, merge: true)
        }
        try await batch.commit()
    }

    private func uploadTripGroupsToCloudThrowing(_ snapshot: [TripGroup], uid: String) async throws {
        guard currentFirebaseUID == uid else { return }
        let db = Firestore.firestore()
        let batch = db.batch()
        let now = Timestamp(date: Date())
        for group in snapshot {
            var data = try Self.firestoreData(from: group, ownerUID: uid)
            data["syncedAt"] = now
            let document = db
                .collection("users")
                .document(uid)
                .collection("tripGroups")
                .document(group.id.uuidString)
            batch.setData(data, forDocument: document, merge: true)
        }
        try await batch.commit()
    }
    #endif

    private func deleteCloudTrip(id: UUID) {
        #if canImport(FirebaseFirestore)
        guard let uid = activeCloudUID ?? currentFirebaseUID else { return }
        Task {
            do {
                try await Firestore.firestore()
                    .collection("users")
                    .document(uid)
                    .collection("trips")
                    .document(id.uuidString)
                    .setData(
                        [
                            "ownerUID": uid,
                            "schemaVersion": 1,
                            "deletedAt": Timestamp(date: Date()),
                            "updatedAt": Timestamp(date: Date())
                        ],
                        merge: true
                    )
            } catch {
                WanderlustDiagnostics.error(error, category: .sync, message: "cloud delete tombstone failed", metadata: ["entityType": "trip", "entityId": id.uuidString])
            }
        }
        #endif
    }

    private func deleteCloudTripGroup(id: UUID) {
        #if canImport(FirebaseFirestore)
        guard let uid = activeCloudUID ?? currentFirebaseUID else { return }
        Task {
            do {
                try await Firestore.firestore()
                    .collection("users")
                    .document(uid)
                    .collection("tripGroups")
                    .document(id.uuidString)
                    .setData(
                        [
                            "ownerUID": uid,
                            "schemaVersion": 1,
                            "deletedAt": Timestamp(date: Date()),
                            "updatedAt": Timestamp(date: Date())
                        ],
                        merge: true
                    )
            } catch {
                WanderlustDiagnostics.error(error, category: .sync, message: "cloud trip group delete tombstone failed", metadata: ["entityType": "tripGroup", "entityId": id.uuidString])
            }
        }
        #endif
    }

    private func enqueueTripSync(_ trip: Trip, operation: SyncOperationType) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try? encoder.encode(trip)
        SyncQueueStore.shared.enqueue(
            entityType: .trip,
            entityId: trip.id.uuidString,
            operationType: operation,
            payload: payload
        )
    }

    private func enqueueTripGroupSync(_ group: TripGroup, operation: SyncOperationType) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try? encoder.encode(group)
        SyncQueueStore.shared.enqueue(
            entityType: .tripGroup,
            entityId: group.id.uuidString,
            operationType: operation,
            payload: payload
        )
    }

    private func processQueuedCloudOperations(uid: String) async {
        #if canImport(FirebaseFirestore)
        guard currentFirebaseUID == uid else { return }
        await SyncQueueStore.shared.processPendingOperations { operation in
            let db = Firestore.firestore()
            let now = Timestamp(date: Date())
            switch operation.entityType {
            case .trip:
                let document = db.collection("users")
                    .document(uid)
                    .collection("trips")
                    .document(operation.entityId)
                switch operation.operationType {
                case .create, .update:
                    guard let payload = operation.payload else { return }
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let trip = try decoder.decode(Trip.self, from: payload)
                    var data = try Self.firestoreData(from: trip, ownerUID: uid)
                    data["updatedAt"] = Timestamp(date: trip.updatedAt)
                    data["syncedAt"] = now
                    try await document.setData(data, merge: true)
                case .delete:
                    try await document.setData(
                        [
                            "ownerUID": uid,
                            "schemaVersion": 1,
                            "deletedAt": now,
                            "updatedAt": now
                        ],
                        merge: true
                    )
                }
            case .tripGroup:
                let document = db.collection("users")
                    .document(uid)
                    .collection("tripGroups")
                    .document(operation.entityId)
                switch operation.operationType {
                case .create, .update:
                    guard let payload = operation.payload else { return }
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let group = try decoder.decode(TripGroup.self, from: payload)
                    var data = try Self.firestoreData(from: group, ownerUID: uid)
                    data["syncedAt"] = now
                    try await document.setData(data, merge: true)
                case .delete:
                    try await document.setData(
                        [
                            "ownerUID": uid,
                            "schemaVersion": 1,
                            "deletedAt": now,
                            "updatedAt": now
                        ],
                        merge: true
                    )
                }
            default:
                return
            }
        }
        syncState = SyncQueueStore.shared.syncState
        WanderlustDiagnostics.info("pending sync operations count=\(SyncQueueStore.shared.operations.count)", category: .sync)
        #else
        syncState = .offline
        #endif
    }

    private var currentFirebaseUID: String? {
        #if canImport(FirebaseAuth)
        Auth.auth().currentUser?.uid
        #else
        nil
        #endif
    }

    private func merge(localTrips: [Trip], cloudTrips: [Trip]) -> [Trip] {
        WanderlustConflictResolver.mergedTrips(localTrips: localTrips, remoteTrips: cloudTrips)
    }

    private func mergeTripGroups(localGroups: [TripGroup], cloudGroups: [TripGroup]) -> [TripGroup] {
        var groupsByID = Dictionary(
            localGroups.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for cloudGroup in cloudGroups {
            if let localGroup = groupsByID[cloudGroup.id] {
                groupsByID[cloudGroup.id] = cloudGroup.updatedAt >= localGroup.updatedAt ? cloudGroup : localGroup
            } else {
                groupsByID[cloudGroup.id] = cloudGroup
            }
        }

        return Array(groupsByID.values)
    }

    private func createGuestMergeBackup(guestTrips: [Trip], accountTrips: [Trip], uid: String) {
        do {
            let envelope = GuestMergeBackupEnvelope(
                schemaVersion: 1,
                startedAt: Date(),
                userID: uid,
                guestTrips: guestTrips,
                accountTrips: accountTrips
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(envelope)
            let supportDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let formatter = ISO8601DateFormatter()
            let fileName = formatter.string(from: envelope.startedAt)
                .replacingOccurrences(of: ":", with: "-")
            let url = supportDirectory
                .appendingPathComponent("Backups", isDirectory: true)
                .appendingPathComponent("guest-merge-\(uid)-\(fileName).json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            WanderlustDiagnostics.warning("guest merge backup failed: \(error.localizedDescription)", category: .storage)
        }
    }

    private func createLocalBackup(reason: String) {
        do {
            let data = try JSONEncoder().encode(trips)
            let supportDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let formatter = ISO8601DateFormatter()
            let fileName = formatter.string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let url = supportDirectory
                .appendingPathComponent("Backups", isDirectory: true)
                .appendingPathComponent("\(reason)-\(fileName).json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            WanderlustDiagnostics.warning("trip backup failed: \(error.localizedDescription)", category: .storage)
        }
    }

    #if canImport(FirebaseFirestore)
    private static func firestoreData(from trip: Trip, ownerUID: String) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(trip)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard var dictionary = object as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        dictionary["ownerUID"] = ownerUID
        dictionary["schemaVersion"] = 1
        dictionary["createdAt"] = Timestamp(date: trip.startDate)
        return dictionary
    }

    private static func trip(fromFirestoreData source: [String: Any]) throws -> Trip? {
        if source["deletedAt"] != nil {
            return nil
        }
        var dictionary = source
        dictionary.removeValue(forKey: "ownerUID")
        dictionary.removeValue(forKey: "schemaVersion")
        dictionary.removeValue(forKey: "createdAt")
        dictionary.removeValue(forKey: "updatedAt")
        dictionary.removeValue(forKey: "deletedAt")
        dictionary.removeValue(forKey: "syncedAt")
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Trip.self, from: data)
    }

    private static func firestoreData(from group: TripGroup, ownerUID: String) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(group)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard var dictionary = object as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        dictionary["ownerUID"] = ownerUID
        dictionary["schemaVersion"] = 1
        return dictionary
    }

    private static func tripGroup(fromFirestoreData source: [String: Any]) throws -> TripGroup? {
        if source["deletedAt"] != nil {
            return nil
        }
        var dictionary = source
        dictionary.removeValue(forKey: "ownerUID")
        dictionary.removeValue(forKey: "schemaVersion")
        dictionary.removeValue(forKey: "deletedAt")
        dictionary.removeValue(forKey: "syncedAt")
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TripGroup.self, from: data)
    }
    #endif

    private func saveUserScopedCacheIfNeeded(_ data: Data) {
        guard let uid = activeCloudUID ?? currentFirebaseUID else { return }
        do {
            let url = try userScopedTripsURL(uid: uid)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            WanderlustDiagnostics.error(
                error,
                category: .sync,
                message: "user cache save failed"
            )
            #endif
        }
    }

    private func loadUserScopedCache(uid: String) {
        do {
            let url = try userScopedTripsURL(uid: uid)
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Trip].self, from: data)
            trips = decoded.sorted { $0.startDate > $1.startDate }
            tripGroups = reconciledTripGroups(loadUserScopedTripGroupsCache(uid: uid), with: trips)
            isLoaded = true
        } catch {
            #if DEBUG
            WanderlustDiagnostics.warning(
                "user cache load skipped: \(error.localizedDescription)",
                category: .sync
            )
            #endif
        }
    }

    private func saveUserScopedTripGroupsCacheIfNeeded(_ data: Data) {
        guard let uid = activeCloudUID ?? currentFirebaseUID else { return }
        do {
            let url = try userScopedTripGroupsURL(uid: uid)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            WanderlustDiagnostics.error(
                error,
                category: .sync,
                message: "user trip group cache save failed"
            )
            #endif
        }
    }

    private func loadUserScopedTripGroupsCache(uid: String) -> [TripGroup] {
        do {
            let url = try userScopedTripGroupsURL(uid: uid)
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([TripGroup].self, from: data)
        } catch {
            #if DEBUG
            WanderlustDiagnostics.warning(
                "user trip group cache load skipped: \(error.localizedDescription)",
                category: .sync
            )
            #endif
            return loadTripGroups()
        }
    }

    private func userScopedTripsURL(uid: String) throws -> URL {
        let supportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let safeUID = uid
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return supportDirectory
            .appendingPathComponent("Users", isDirectory: true)
            .appendingPathComponent(safeUID, isDirectory: true)
            .appendingPathComponent("trips.json")
    }

    private func userScopedTripGroupsURL(uid: String) throws -> URL {
        let supportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let safeUID = uid
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return supportDirectory
            .appendingPathComponent("Users", isDirectory: true)
            .appendingPathComponent(safeUID, isDirectory: true)
            .appendingPathComponent("tripGroups.json")
    }

    // MARK: - Sorting

    private func sortTrips() {
        trips.sort {
            if $0.startDate !=
                $1.startDate {
                return $0.startDate >
                    $1.startDate
            }

            return $0.title
                .localizedCaseInsensitiveCompare(
                    $1.title
                ) == .orderedAscending
        }
    }

    private func sortCities(
        inTripAt index: Int
    ) {
        guard trips.indices.contains(
            index
        ) else {
            return
        }

        trips[index].cities.sort {
            let firstDate =
                $0.arrivalDate ??
                .distantFuture

            let secondDate =
                $1.arrivalDate ??
                .distantFuture

            if firstDate != secondDate {
                return firstDate <
                    secondDate
            }

            return $0.name
                .localizedCaseInsensitiveCompare(
                    $1.name
                ) == .orderedAscending
        }
    }

    private func sortFlights(
        inTripAt index: Int
    ) {
        guard trips.indices.contains(
            index
        ) else {
            return
        }

        trips[index].flights.sort {
            $0.departureDate <
            $1.departureDate
        }
    }

    // MARK: - Matching Helpers

    private func citiesMatch(
        _ first: VisitedCity,
        _ second: VisitedCity
    ) -> Bool {
        if let firstGeonameID =
                first.geonameID,
           let secondGeonameID =
                second.geonameID {
            return firstGeonameID ==
                secondGeonameID
        }

        let namesMatch =
            normalize(first.name) ==
            normalize(second.name)

        guard namesMatch else {
            return false
        }

        let firstCountryCode =
            clean(first.countryCode)
                .uppercased()

        let secondCountryCode =
            clean(second.countryCode)
                .uppercased()

        if !firstCountryCode.isEmpty,
           !secondCountryCode.isEmpty {
            return firstCountryCode ==
                secondCountryCode
        }

        return normalize(
            first.countryName
        ) == normalize(
            second.countryName
        )
    }

    private func cityDeduplicationKey(
        _ city: VisitedCity
    ) -> String {
        if let geonameID =
                city.geonameID {
            return "geoname:\(geonameID)"
        }

        return [
            normalize(city.name),
            clean(city.countryCode)
                .uppercased(),
            normalize(city.countryName)
        ]
        .joined(separator: "|")
    }

    private func clean(
        _ text: String
    ) -> String {
        text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private func normalize(
        _ text: String
    ) -> String {
        clean(text)
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
}
