import CoreLocation
import Foundation

// MARK: - Visited Country Aggregation
//
// 目的:
//   World / Trips / Passport / Statistics / Search がそれぞれ独自に訪問国を
//   数えていたため、同じデータでも画面ごとに国数が食い違っていた。
//
//   - GeoJSONLoader.visitedCountries(from:) は GeoJSON に一致した国だけを返す
//     （＝未収録の国が数から落ちる）
//   - StatisticsSnapshot.make は ISO コード or 生の国名で数える
//   - PassportView.entries は独自キーで数える
//   - TripsView.countryGroups はさらに別のキーで数える
//
//   本ファイルを唯一の正とし、全画面がここを経由して数える。
//
// 設計:
//   - キー算出は `nonisolated` かつ純粋関数。UI もストレージも参照しないため
//     Unit Test から直接検証できる。
//   - 表示名・国旗の解決だけが `@MainActor`（GeoJSONLoader / L10n が MainActor のため）。

/// 正規化済みの訪問国キー。ISO2 が判明していれば ISO2、
/// 判明しない場合は正規化した国名を大文字化したもの。
nonisolated struct VisitedCountryKey: Hashable, Comparable, Sendable {
    let rawValue: String

    /// ISO2 コードとして解決できた場合のみ非 nil。
    let isoCode: String?

    /// キー解決前の代表的な国名（表示フォールバック用）。
    let fallbackName: String

    static func < (lhs: VisitedCountryKey, rhs: VisitedCountryKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func == (lhs: VisitedCountryKey, rhs: VisitedCountryKey) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

/// 表示用に解決済みの訪問国。
struct VisitedCountry: Identifiable, Hashable, Sendable {
    let id: String
    let isoCode: String
    let displayName: String
    let flagEmoji: String
    let continent: String

    /// この国を含む Trip の ID（重複なし）。
    let tripIDs: [UUID]

    /// この国で訪問した都市名（重複なし・ソート済み）。
    let cityNames: [String]

    /// 最初/最後の訪問日。
    let firstVisit: Date
    let lastVisit: Date

    var tripCount: Int { tripIDs.count }
}

enum VisitedCountryAggregator {

    // MARK: - Pure key resolution (testable, off-main)

    /// 「国なし」として除外すべき値。
    nonisolated private static let unknownTokens: Set<String> = ["", "unknown", "n/a", "-", "—", "未設定", "不明"]

    /// 1 都市から正規化キーを求める。判定できない場合は nil。
    ///
    /// - Note: `WanderlustNameResolver.normalizedCountryCode` は "England" → "GB" の
    ///   ようなエイリアスも解決する。ここを唯一の入口にすることで、
    ///   イギリスを 1 国として数えるか 4 国として数えるかが画面間でズレなくなる。
    nonisolated static func key(
        countryCode: String,
        countryName: String
    ) -> VisitedCountryKey? {
        let trimmedName = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = WanderlustNameResolver
            .normalizedCountryCode(countryCode, fallback: countryName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if !normalizedCode.isEmpty,
           !unknownTokens.contains(normalizedCode.lowercased()) {
            return VisitedCountryKey(
                rawValue: normalizedCode,
                isoCode: normalizedCode.count == 2 ? normalizedCode : nil,
                fallbackName: trimmedName.isEmpty ? normalizedCode : trimmedName
            )
        }

        guard !unknownTokens.contains(trimmedName.lowercased()) else {
            return nil
        }

        // ISO が引けない国名は、大文字化 + 空白畳み込みで安定キーにする。
        let nameKey = trimmedName
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .uppercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        guard !nameKey.isEmpty else { return nil }

        return VisitedCountryKey(
            rawValue: nameKey,
            isoCode: nil,
            fallbackName: trimmedName
        )
    }

    nonisolated static func key(for city: VisitedCity) -> VisitedCountryKey? {
        key(countryCode: city.countryCode, countryName: city.countryName)
    }

    /// Trip 配列に含まれる訪問国キーの集合。**これがアプリ全体の訪問国数の定義**。
    nonisolated static func countryKeys(in trips: [Trip]) -> Set<VisitedCountryKey> {
        var keys: Set<VisitedCountryKey> = []
        for trip in trips {
            for city in trip.cities {
                if let key = key(for: city) {
                    keys.insert(key)
                }
            }
        }
        return keys
    }

    /// 訪問国数。World / Trips / Passport / Statistics はすべてこれを使う。
    nonisolated static func visitedCountryCount(in trips: [Trip]) -> Int {
        countryKeys(in: trips).count
    }

    /// 1 つの Trip が指定キーの国を含むか。
    nonisolated static func trip(_ trip: Trip, visits key: VisitedCountryKey) -> Bool {
        trip.cities.contains { self.key(for: $0) == key }
    }

    // MARK: - Display resolution (MainActor)

    /// 表示用に解決した訪問国一覧。初回訪問日の昇順。
    ///
    /// Passport のスタンプ、Trips の国グループ、Statistics の国一覧は
    /// すべてこの結果を使うため、順序・件数・表記が一致する。
    @MainActor
    static func visitedCountries(in trips: [Trip]) -> [VisitedCountry] {
        struct Accumulator {
            var key: VisitedCountryKey
            var tripIDs: [UUID] = []
            var cityNames: Set<String> = []
            var firstVisit: Date
            var lastVisit: Date
        }

        var accumulators: [String: Accumulator] = [:]

        for trip in trips {
            for city in trip.cities {
                guard let key = key(for: city) else { continue }

                let visitDate = city.arrivalDate ?? trip.startDate
                let cityName = city.localizedName

                if var existing = accumulators[key.rawValue] {
                    if !existing.tripIDs.contains(trip.id) {
                        existing.tripIDs.append(trip.id)
                    }
                    existing.cityNames.insert(cityName)
                    existing.firstVisit = min(existing.firstVisit, visitDate)
                    existing.lastVisit = max(existing.lastVisit, visitDate)
                    accumulators[key.rawValue] = existing
                } else {
                    accumulators[key.rawValue] = Accumulator(
                        key: key,
                        tripIDs: [trip.id],
                        cityNames: [cityName],
                        firstVisit: visitDate,
                        lastVisit: visitDate
                    )
                }
            }
        }

        return accumulators.values
            .map { accumulator -> VisitedCountry in
                let country = resolveCountry(for: accumulator.key)
                return VisitedCountry(
                    id: accumulator.key.rawValue,
                    isoCode: country?.iso2 ?? (accumulator.key.isoCode ?? ""),
                    displayName: country?.displayName ?? accumulator.key.fallbackName,
                    flagEmoji: country?.flagEmoji ?? flagEmoji(for: accumulator.key.isoCode),
                    continent: country?.continent ?? "",
                    tripIDs: accumulator.tripIDs,
                    cityNames: accumulator.cityNames.sorted(),
                    firstVisit: accumulator.firstVisit,
                    lastVisit: accumulator.lastVisit
                )
            }
            .sorted { lhs, rhs in
                if lhs.firstVisit != rhs.firstVisit {
                    return lhs.firstVisit < rhs.firstVisit
                }
                return lhs.id < rhs.id
            }
    }

    /// 地図で塗りつぶせる国（GeoJSON に存在するもの）。
    ///
    /// - Important: GeoJSON に未収録の国は塗れないため、この件数は
    ///   `visitedCountryCount(in:)` 以下になり得る。**画面に出す「訪問国数」には
    ///   これを使わないこと。** 数の表示は必ず `visitedCountryCount(in:)` を使う。
    ///
    /// 座標フォールバックは「すでに数えられている国」の描画可否を上げるためだけに
    /// 使う。新しい国を増やすことはないので、他画面との件数一致は崩れない。
    @MainActor
    static func mappableCountries(in trips: [Trip]) -> [Country] {
        var result: [String: Country] = [:]
        for (key, coordinate) in keyedCoordinates(in: trips) {
            if let country = resolveCountry(for: key, coordinate: coordinate) {
                result[country.id] = country
            }
        }
        return Array(result.values)
    }

    // MARK: - Helpers

    /// 各訪問国キーの代表座標（最初に見つかった非ゼロ座標）。
    @MainActor
    private static func keyedCoordinates(in trips: [Trip]) -> [VisitedCountryKey: CLLocationCoordinate2D?] {
        var result: [VisitedCountryKey: CLLocationCoordinate2D?] = [:]
        for trip in trips {
            for city in trip.cities {
                guard let key = key(for: city) else { continue }
                if let existing = result[key], existing != nil { continue }
                let coordinate = city.coordinate
                let isUsable = coordinate.latitude != 0 || coordinate.longitude != 0
                result[key] = isUsable ? coordinate : nil
            }
        }
        return result
    }

    @MainActor
    private static func resolveCountry(
        for key: VisitedCountryKey,
        coordinate: CLLocationCoordinate2D? = nil
    ) -> Country? {
        if let isoCode = key.isoCode,
           let country = GeoJSONLoader.shared.country(withISOCode: isoCode) {
            return country
        }
        if let country = GeoJSONLoader.shared.country(named: key.fallbackName) {
            return country
        }
        // ISO も国名も引けない場合のみ座標から引く。
        // （旧 GeoJSONLoader.visitedCountries が持っていた第 3 フォールバック）
        if let coordinate {
            return GeoJSONLoader.shared.country(containing: coordinate)
        }
        return nil
    }

    nonisolated static func flagEmoji(for isoCode: String?) -> String {
        guard let isoCode else { return "🌍" }
        let code = isoCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2 else { return "🌍" }
        let scalars = code.unicodeScalars.compactMap {
            UnicodeScalar(127_397 + $0.value).map(String.init)
        }
        return scalars.count == 2 ? scalars.joined() : "🌍"
    }
}
