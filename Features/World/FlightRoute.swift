import CoreLocation
import Foundation

// MARK: - Flight route
//
// フライト再生の「幾何と時間」だけを担当する純粋な型。
// SwiftUI / MapKit / TripStore に一切依存しないので Unit Test から直接検証できる。
//
// 旧 `FlightPlaybackViewModel` は座標補間・距離計算・カメラ位置・再生制御・
// 空港ラベル生成までを 1 クラスに抱えていたため、テストできず変更もしづらかった。

/// 大圏航路を等間隔にサンプリングした経路。
struct FlightRoute: Sendable {

    /// 経路上の点（始点から終点まで）。
    let coordinates: [CLLocationCoordinate2D]

    /// `coordinates[i]` までの累積距離（メートル）。
    let cumulativeDistances: [CLLocationDistance]

    /// 全長（メートル）。
    var totalDistance: CLLocationDistance { cumulativeDistances.last ?? 0 }

    /// 経由地（乗り継ぎ空港）が経路上のどの進捗にあたるか。
    let legBoundaries: [Double]

    init?(coordinates: [CLLocationCoordinate2D], legBoundaries: [Double] = []) {
        let cleaned = Self.removingDuplicates(in: coordinates)
        guard cleaned.count >= 2 else { return nil }

        var distances: [CLLocationDistance] = [0]
        distances.reserveCapacity(cleaned.count)
        var accumulated: CLLocationDistance = 0
        for index in 1..<cleaned.count {
            accumulated += cleaned[index - 1].flightDistance(to: cleaned[index])
            distances.append(accumulated)
        }

        guard accumulated > 1 else { return nil }

        self.coordinates = cleaned
        self.cumulativeDistances = distances
        self.legBoundaries = legBoundaries
    }

    // MARK: Sampling

    /// 進捗 0...1 における位置・進行方位・区間番号。
    func sample(at progress: Double) -> FlightRouteSample {
        let clamped = min(max(progress, 0), 1)
        let target = totalDistance * clamped
        let index = segmentIndex(forDistance: target)

        let segmentStart = cumulativeDistances[index]
        let segmentEnd = cumulativeDistances[min(index + 1, cumulativeDistances.count - 1)]
        let segmentLength = segmentEnd - segmentStart

        let fraction = segmentLength > 0
            ? (target - segmentStart) / segmentLength
            : 0

        let from = coordinates[index]
        let to = coordinates[min(index + 1, coordinates.count - 1)]

        return FlightRouteSample(
            coordinate: from.flightInterpolated(to: to, fraction: fraction),
            course: from.flightBearing(to: to),
            segmentIndex: index,
            distanceTravelled: target,
            distanceRemaining: max(totalDistance - target, 0)
        )
    }

    /// 進捗で「飛んだ部分」と「これから飛ぶ部分」に分ける。
    ///
    /// 分割点の座標を両方に含めることで、2 本の `MapPolyline` が
    /// 途切れず繋がって見えるようにしている。
    func split(at progress: Double) -> (travelled: [CLLocationCoordinate2D],
                                        remaining: [CLLocationCoordinate2D]) {
        let sample = sample(at: progress)
        let index = sample.segmentIndex

        var travelled = Array(coordinates.prefix(index + 1))
        travelled.append(sample.coordinate)

        var remaining = [sample.coordinate]
        remaining.append(contentsOf: coordinates.suffix(from: min(index + 1, coordinates.count)))

        return (travelled, remaining)
    }

    /// 経路全体を含む矩形（カメラの初期位置決めに使う）。
    var boundingRegion: (center: CLLocationCoordinate2D, span: CLLocationDegrees) {
        var minLat = 90.0, maxLat = -90.0
        var minLon = 180.0, maxLon = -180.0
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = max(maxLat - minLat, maxLon - minLon)
        return (center, max(span, 0.5))
    }

    // MARK: Private

    private func segmentIndex(forDistance distance: CLLocationDistance) -> Int {
        // 累積距離は単調増加なので二分探索できる。
        var lower = 0
        var upper = cumulativeDistances.count - 1
        while lower < upper {
            let middle = (lower + upper + 1) / 2
            if cumulativeDistances[middle] <= distance {
                lower = middle
            } else {
                upper = middle - 1
            }
        }
        return min(lower, coordinates.count - 2)
    }

    private static func removingDuplicates(
        in coordinates: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        for coordinate in coordinates {
            guard coordinate.isValidFlightCoordinate else { continue }
            if let last = result.last, last.flightDistance(to: coordinate) < 1 { continue }
            result.append(coordinate)
        }
        return result
    }
}

struct FlightRouteSample: Sendable {
    let coordinate: CLLocationCoordinate2D
    /// 真北からの進行方位（度）。機体アイコンの回転に使う。
    let course: CLLocationDirection
    let segmentIndex: Int
    let distanceTravelled: CLLocationDistance
    let distanceRemaining: CLLocationDistance
}

// MARK: - Flight phase

/// 離陸・上昇・巡航・降下・着陸。カメラワークと高度表示の切り替えに使う。
enum FlightPhase: String, CaseIterable, Sendable {
    case takeoff
    case climb
    case cruise
    case descent
    case landing

    /// 進捗からフェーズを求める。
    ///
    /// 実機の飛行プロファイルに合わせ、上昇と降下に約 12% ずつ割り当てている。
    static func phase(for progress: Double) -> FlightPhase {
        switch progress {
        case ..<0.03: return .takeoff
        case ..<0.15: return .climb
        case ..<0.85: return .cruise
        case ..<0.97: return .descent
        default: return .landing
        }
    }

    var localizedName: String {
        switch self {
        case .takeoff: return String(localized: "Takeoff")
        case .climb: return String(localized: "Climbing")
        case .cruise: return String(localized: "Cruising")
        case .descent: return String(localized: "Descending")
        case .landing: return String(localized: "Landing")
        }
    }
}

// MARK: - Altitude profile

/// 進捗に対する擬似的な高度プロファイル（0...1）。
///
/// 実データは持っていないので、離陸で急上昇し巡航で平坦、着陸で降りる
/// 台形カーブを作る。カメラの引き・ピッチ・高度表示に使う。
enum FlightAltitudeProfile {
    static func normalizedAltitude(at progress: Double) -> Double {
        let value = min(max(progress, 0), 1)
        let climbEnd = 0.15
        let descentStart = 0.85

        if value <= climbEnd {
            // 上昇: 前半ほど急な ease-out
            let t = value / climbEnd
            return 1 - pow(1 - t, 2.2)
        }
        if value >= descentStart {
            let t = (value - descentStart) / (1 - descentStart)
            return 1 - pow(t, 1.8)
        }
        return 1
    }

    /// 表示用の巡航高度（フィート）。だいたいの見た目合わせ。
    static func displayAltitudeFeet(at progress: Double, cruiseFeet: Double = 36_000) -> Int {
        let feet = normalizedAltitude(at: progress) * cruiseFeet
        // 100ft 単位に丸めて数字がガタつかないようにする。
        return Int((feet / 100).rounded()) * 100
    }
}

// MARK: - Playback timing

/// 実際の飛行時間に比例した再生時間を決める。
///
/// そのまま実時間で再生すると 12 時間かかってしまうので圧縮するが、
/// 「長距離便は長く感じる」ことは保ちたい。そこで平方根で圧縮し、
/// 上限・下限を設けている。
///   1 時間の便  → 約 12 秒
///   6 時間の便  → 約 29 秒
///   13 時間の便 → 約 43 秒（上限）
struct FlightPlaybackTiming: Sendable {

    /// 実際の飛行時間（秒）。不明な場合は距離から推定する。
    let realDuration: TimeInterval

    /// 画面上での再生時間（秒、等速時）。
    let playbackDuration: TimeInterval

    static let minimumPlayback: TimeInterval = 8
    static let maximumPlayback: TimeInterval = 45

    init(realDuration: TimeInterval) {
        let safeDuration = max(realDuration, 60)
        self.realDuration = safeDuration

        let hours = safeDuration / 3600
        let scaled = 12 * sqrt(max(hours, 0.1))
        self.playbackDuration = min(max(scaled, Self.minimumPlayback), Self.maximumPlayback)
    }

    /// 飛行時間が判らないときに距離から推定する。
    /// 巡航 840km/h + 離着陸のオーバーヘッド 25 分。
    init(estimatingFromDistance distance: CLLocationDistance) {
        let cruiseSpeedMetersPerSecond: Double = 840_000 / 3600
        let cruise = distance / cruiseSpeedMetersPerSecond
        self.init(realDuration: cruise + 25 * 60)
    }

    /// 再生進捗から「経過した飛行時間」を求める。
    func elapsedRealTime(at progress: Double) -> TimeInterval {
        realDuration * min(max(progress, 0), 1)
    }

    /// 実時間に対する圧縮倍率（「約 40 倍速」の表示に使う）。
    var compressionFactor: Double {
        guard playbackDuration > 0 else { return 1 }
        return realDuration / playbackDuration
    }
}

// MARK: - Coordinate math

extension CLLocationCoordinate2D {

    var isValidFlightCoordinate: Bool {
        latitude.isFinite && longitude.isFinite &&
        abs(latitude) <= 90 && abs(longitude) <= 180 &&
        !(latitude == 0 && longitude == 0)
    }

    /// 2 点間の大圏距離（メートル）。Haversine。
    func flightDistance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let earthRadius: Double = 6_371_000
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(max(1 - a, 0)))
    }

    /// 経度 180 度線をまたぐ場合も最短側を通って補間する。
    func flightInterpolated(
        to other: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        let clamped = min(max(fraction, 0), 1)

        var deltaLongitude = other.longitude - longitude
        if deltaLongitude > 180 { deltaLongitude -= 360 }
        if deltaLongitude < -180 { deltaLongitude += 360 }

        var resultLongitude = longitude + deltaLongitude * clamped
        if resultLongitude > 180 { resultLongitude -= 360 }
        if resultLongitude < -180 { resultLongitude += 360 }

        return CLLocationCoordinate2D(
            latitude: latitude + (other.latitude - latitude) * clamped,
            longitude: resultLongitude
        )
    }

    /// 真北を 0 度とした方位角。
    func flightBearing(to other: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        var deltaLon = (other.longitude - longitude) * .pi / 180
        if deltaLon > .pi { deltaLon -= 2 * .pi }
        if deltaLon < -.pi { deltaLon += 2 * .pi }

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }
}
