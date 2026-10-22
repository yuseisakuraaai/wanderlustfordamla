import Foundation
import CoreLocation

// MARK: - Wanderlust City

struct WanderlustCity: Identifiable, Codable, Hashable, Sendable {
    let id: Int

    let name: String
    let countryCode: String
    let stateCode: String

    let timezone: String
    let population: Int
    let featureCode: String
    let municipalitySuffix: String
    let travelDemandRank: Int
    let modificationDate: String

    let location: WanderlustGeoPoint
    let alternateNames: [String]

    nonisolated init(
        id: Int,
        name: String,
        countryCode: String,
        stateCode: String = "",
        timezone: String = "",
        population: Int = 0,
        featureCode: String = "",
        municipalitySuffix: String = "",
        travelDemandRank: Int = 0,
        modificationDate: String = "",
        location: WanderlustGeoPoint,
        alternateNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.countryCode = countryCode
        self.stateCode = stateCode
        self.timezone = timezone
        self.population = population
        self.featureCode = featureCode
        self.municipalitySuffix = municipalitySuffix
        self.travelDemandRank = travelDemandRank
        self.modificationDate = modificationDate
        self.location = location
        self.alternateNames = alternateNames
    }

    // MARK: Coordinates

    nonisolated var latitude: Double { location.latitude }
    nonisolated var longitude: Double { location.longitude }
    nonisolated var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // MARK: Display

    nonisolated var normalizedCountryCode: String {
        countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    nonisolated var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var localizedDisplayName: String {
        WanderlustNameResolver.cityName(for: self, fallback: name)
    }

    var localizedMunicipalityDisplayName: String {
        let cityName = localizedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCountryCode == "JP",
              !cityName.isEmpty,
              !Self.hasJapaneseMunicipalitySuffix(cityName),
              let suffix = japaneseMunicipalitySuffix else {
            return cityName
        }

        return cityName + suffix
    }

    nonisolated var japanesePrefectureName: String? {
        guard normalizedCountryCode == "JP" else {
            return nil
        }

        return Self.japanesePrefectureNames[stateCode]
    }

    nonisolated var japaneseMunicipalitySuffix: String? {
        guard normalizedCountryCode == "JP" else {
            return nil
        }

        let storedSuffix = municipalitySuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !storedSuffix.isEmpty {
            return storedSuffix
        }

        if let suffix = Self.japaneseMunicipalitySuffixesByID[id] {
            return suffix
        }

        let normalizedNames = ([displayName] + alternateNames)
            .map(Self.normalize)

        if normalizedNames.contains(where: { $0.hasSuffix("-ku") || $0.hasSuffix(" ku") || $0.hasSuffix(" city") }) {
            return "区"
        }

        if normalizedNames.contains(where: { $0.hasSuffix("-cho") || $0.hasSuffix(" cho") || $0.hasSuffix("-machi") || $0.hasSuffix(" machi") }) {
            return "町"
        }

        if normalizedNames.contains(where: { $0.hasSuffix("-mura") || $0.hasSuffix(" mura") || $0.hasSuffix("-son") || $0.hasSuffix(" son") }) {
            return "村"
        }

        return nil
    }

    nonisolated var localizationID: String {
        String(id)
    }

    nonisolated var flagEmoji: String {
        let code = normalizedCountryCode

        guard code.count == 2,
              code.unicodeScalars.allSatisfy({
                  CharacterSet.uppercaseLetters
                      .contains($0)
              }) else {
            return "🌍"
        }

        return code.unicodeScalars.compactMap { scalar in
            UnicodeScalar(
                127397 + scalar.value
            )
            .map(String.init)
        }
        .joined()
    }

    nonisolated var searchableNames: [String] {
        var names = WanderlustL10n.localizedVariants(
            key: "city.\(localizationID)",
            table: .cities,
            fallback: displayName
        )

        names.append(
            contentsOf: alternateNames
        )
        names.append(
            contentsOf: JapaneseSearchReadingAliases.cityAliases(
                countryCode: normalizedCountryCode,
                cityName: displayName
            )
        )
        names.append(String(id))
        names.append(normalizedCountryCode)

        var seen = Set<String>()

        return names.filter { value in
            let cleaned = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !cleaned.isEmpty else {
                return false
            }

            let key = cleaned
                .folding(
                    options: [
                        .caseInsensitive,
                        .diacriticInsensitive,
                        .widthInsensitive
                    ],
                    locale: Locale(
                        identifier: "en_US_POSIX"
                    )
                )
                .lowercased()

            return seen.insert(key).inserted
        }
    }

    nonisolated func matches(
        query: String
    ) -> Bool {
        let queryContainsJapaneseKana = JapaneseKanaRomajiSearch.containsJapaneseKana(query)
        let normalizedQueries = JapaneseKanaRomajiSearch.normalizedQueryVariants(
            query,
            normalizer: Self.normalize,
            includeRomajiForKana: true
        )

        guard !normalizedQueries.isEmpty else {
            return false
        }

        return searchableNames.contains { candidate in
            let normalizedCandidate = Self.normalize(candidate)
            let nameMatches = normalizedQueries.contains {
                normalizedCandidate == $0 ||
                    normalizedCandidate.hasPrefix($0) ||
                    (queryContainsJapaneseKana && normalizedCandidate.contains($0)) ||
                    (!queryContainsJapaneseKana &&
                        Self.hasWordPrefix(normalizedCandidate, query: $0))
            }

            let romajiMatches = !queryContainsJapaneseKana && normalizedQueries.contains { query in
                guard let romaji = JapaneseKanaRomajiSearch.romaji(fromKana: candidate) else {
                    return false
                }
                let normalizedRomaji = Self.normalize(romaji)
                return normalizedRomaji.hasPrefix(query) || normalizedRomaji.contains(query)
            }

            return nameMatches || romajiMatches
        }
    }

    nonisolated func searchScore(
        for query: String
    ) -> Int {
        let queryContainsJapaneseKana = JapaneseKanaRomajiSearch.containsJapaneseKana(query)
        let normalizedQueries = JapaneseKanaRomajiSearch.normalizedQueryVariants(
            query,
            normalizer: Self.normalize,
            includeRomajiForKana: true
        )

        guard !normalizedQueries.isEmpty else {
            return 0
        }

        let normalizedMainName = Self.normalize(
            WanderlustL10n.cityName(
                id: localizationID,
                fallback: displayName
            )
        )

        if normalizedQueries.contains(normalizedMainName) {
            return 10_000
        }

        if normalizedQueries.contains(where: { normalizedMainName.hasPrefix($0) }) {
            return 9_000
        }

        for candidateName in searchableNames {
            let normalizedAlternate = Self.normalize(candidateName)

            if normalizedQueries.contains(normalizedAlternate) {
                return 8_000
            }

            if normalizedQueries.contains(where: { normalizedAlternate.hasPrefix($0) }) {
                return 7_000
            }
        }

        if !queryContainsJapaneseKana,
           searchableNames.contains(where: {
               guard let romaji = JapaneseKanaRomajiSearch.romaji(fromKana: $0) else {
                   return false
               }
               let normalizedRomaji = Self.normalize(romaji)
               return normalizedQueries.contains {
                   normalizedRomaji.hasPrefix($0) || normalizedRomaji.contains($0)
               }
           }) {
            return 6_500
        }

        if queryContainsJapaneseKana,
           normalizedQueries.contains(where: { normalizedMainName.contains($0) }) {
            return 6_000
        }

        if queryContainsJapaneseKana,
           searchableNames.contains(where: {
               let normalizedAlternate = Self.normalize($0)
               return normalizedQueries.contains {
                   normalizedAlternate.contains($0)
               }
           }) {
            return 5_500
        }

        if !queryContainsJapaneseKana,
           normalizedQueries.contains(where: { Self.hasWordPrefix(normalizedMainName, query: $0) }) {
            return 6_000
        }

        if !queryContainsJapaneseKana,
           searchableNames.contains(where: {
               let normalizedAlternate = Self.normalize($0)
               return normalizedQueries.contains {
                   Self.hasWordPrefix(normalizedAlternate, query: $0)
               }
           }) {
            return 5_000
        }

        return 0
    }

    private nonisolated static func hasWordPrefix(
        _ candidate: String,
        query: String
    ) -> Bool {
        let escapedQuery = NSRegularExpression.escapedPattern(
            for: query
        )

        return candidate.range(
            of: "(^|[\\s\\-/・.])\(escapedQuery)",
            options: .regularExpression
        ) != nil
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case legacyID = "_id"
        case name
        case defaultName
        case asciiName
        case countryCode = "country"
        case countryISO2
        case stateCode = "state"
        case admin1Code
        case timezone
        case timeZoneID
        case population
        case featureCode
        case municipalitySuffix
        case travelDemandRank
        case modificationDate = "modtime"
        case location
        case latitude
        case longitude
        case alternateNames = "alternate_names"
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(stateCode, forKey: .stateCode)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(population, forKey: .population)
        try container.encode(featureCode, forKey: .featureCode)
        try container.encode(municipalitySuffix, forKey: .municipalitySuffix)
        try container.encode(travelDemandRank, forKey: .travelDemandRank)
        try container.encode(modificationDate, forKey: .modificationDate)
        try container.encode(location, forKey: .location)
        try container.encode(alternateNames, forKey: .alternateNames)
    }

    nonisolated init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        id = try container.decodeFlexibleInt(
            forKeys: [.id, .legacyID],
            defaultValue: 0
        )

        name = try container.decodeFirstString(
            forKeys: [.name, .defaultName, .asciiName],
            defaultValue: ""
        )

        countryCode = try container.decodeFirstString(
            forKeys: [.countryCode, .countryISO2],
            defaultValue: ""
        )

        stateCode = try container.decodeFirstString(
            forKeys: [.stateCode, .admin1Code],
            defaultValue: ""
        )

        timezone = try container.decodeFirstString(
            forKeys: [.timezone, .timeZoneID],
            defaultValue: ""
        )

        population = try container.decodeFlexibleInt(
            forKey: .population,
            defaultValue: 0
        )

        featureCode = try container.decodeIfPresent(
            String.self,
            forKey: .featureCode
        ) ?? ""

        municipalitySuffix = try container.decodeIfPresent(
            String.self,
            forKey: .municipalitySuffix
        ) ?? ""

        travelDemandRank = try container.decodeFlexibleInt(
            forKey: .travelDemandRank,
            defaultValue: 0
        )

        modificationDate = try container.decodeIfPresent(
            String.self,
            forKey: .modificationDate
        ) ?? ""

        if let decodedLocation = try container.decodeIfPresent(
            WanderlustGeoPoint.self,
            forKey: .location
        ) {
            location = decodedLocation
        } else {
            let longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
            let latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
            location = WanderlustGeoPoint(
                type: "Point",
                coordinates: [longitude, latitude]
            )
        }

        alternateNames = try container.decodeIfPresent(
            [String].self,
            forKey: .alternateNames
        ) ?? []
    }

    nonisolated private static func normalize(
        _ text: String
    ) -> String {
        SearchNormalizer.normalize(text)
    }

    private nonisolated static func hasJapaneseMunicipalitySuffix(_ name: String) -> Bool {
        guard let last = name.last else {
            return false
        }

        return ["市", "区", "町", "村"].contains(last)
    }

    private nonisolated static let japanesePrefectureNames: [String: String] = [
        "01": "愛知県",
        "02": "秋田県",
        "03": "青森県",
        "04": "千葉県",
        "05": "愛媛県",
        "06": "福井県",
        "07": "福岡県",
        "08": "福島県",
        "09": "岐阜県",
        "10": "群馬県",
        "11": "広島県",
        "12": "北海道",
        "13": "兵庫県",
        "14": "茨城県",
        "15": "石川県",
        "16": "岩手県",
        "17": "香川県",
        "18": "鹿児島県",
        "19": "神奈川県",
        "20": "高知県",
        "21": "熊本県",
        "22": "京都府",
        "23": "三重県",
        "24": "宮城県",
        "25": "宮崎県",
        "26": "長野県",
        "27": "長崎県",
        "28": "奈良県",
        "29": "新潟県",
        "30": "大分県",
        "31": "岡山県",
        "32": "大阪府",
        "33": "佐賀県",
        "34": "埼玉県",
        "35": "滋賀県",
        "36": "島根県",
        "37": "静岡県",
        "38": "栃木県",
        "39": "徳島県",
        "40": "東京都",
        "41": "鳥取県",
        "42": "富山県",
        "43": "和歌山県",
        "44": "山形県",
        "45": "山口県",
        "46": "山梨県",
        "47": "沖縄県"
    ]

    private nonisolated static let japaneseMunicipalitySuffixesByID: [Int: String] = [
        11790342: "区", // Setagaya
        11071717: "区", // Edogawa
        10987897: "区", // Adachi
        11836117: "区", // Suginami
        1861321: "区", // Itabashi
        11790353: "区", // Shinjuku
        8572994: "区", // Toshima
        11790374: "区", // Meguro
        1851454: "区", // Sumida
        11790632: "区", // Bunkyo
        11808021: "区", // Shibuya
        10968247: "区", // Arakawa
        11790369: "区", // Taito
        11749713: "区", // Chiyoda
        13353695: "区", // Chuo
        13353696: "区", // Minato
        8469289: "区", // Ota
        8469284: "区", // Katsushika
        8715035: "区", // Nakano
        8469285: "区", // Kita
        900100001: "区", // Koto
        900100002: "区", // Shinagawa
        900100003: "区", // Nerima

        900200001: "町", // Hakone
        900200002: "町", // Niseko
        900200003: "町", // Biei
        900200004: "町", // Toyako
        900200005: "村", // Onna
        900200006: "町", // Naoshima
        900200007: "村" // Shirakawa
    ]
}

// MARK: - Japanese Kana Search

enum JapaneseKanaRomajiSearch {
    nonisolated static func normalizedQueryVariants(
        _ query: String,
        normalizer: (String) -> String,
        includeRomajiForKana: Bool = true
    ) -> [String] {
        var variants: [String] = []
        let normalizedQuery = normalizer(query)
        if !normalizedQuery.isEmpty {
            variants.append(normalizedQuery)
        }

        if containsJapaneseKana(query), !includeRomajiForKana {
            for kanaVariant in kanaScriptVariants(for: query) {
                let normalizedVariant = normalizer(kanaVariant)
                if !normalizedVariant.isEmpty {
                    variants.append(normalizedVariant)
                }
            }
        } else if let romaji = romaji(fromKana: query) {
            let normalizedRomaji = normalizer(romaji)
            if !normalizedRomaji.isEmpty {
                variants.append(normalizedRomaji)
            }
            for longVowelVariant in longVowelRomajiVariants(for: normalizedRomaji) {
                if !longVowelVariant.isEmpty {
                    variants.append(longVowelVariant)
                }
            }
        } else {
            for romajiVariant in japaneseInputRomajiVariants(for: normalizedQuery) {
                let normalizedVariant = normalizer(romajiVariant)
                if !normalizedVariant.isEmpty {
                    variants.append(normalizedVariant)
                }
            }
        }

        var seen = Set<String>()
        return variants.filter {
            seen.insert($0).inserted
        }
    }

    nonisolated static func containsJapaneseKana(
        _ text: String
    ) -> Bool {
        text.contains(where: isKanaCharacter)
    }

    private nonisolated static func kanaScriptVariants(
        for text: String
    ) -> [String] {
        [
            text,
            String(text.map(normalizedHiraganaCharacter)),
            String(text.map(normalizedKatakanaCharacter))
        ]
    }

    private nonisolated static func japaneseInputRomajiVariants(
        for text: String
    ) -> [String] {
        guard !text.isEmpty else { return [] }

        var variants: Set<String> = []
        var queue = [text]
        let replacements: [(String, String)] = [
            ("si", "shi"),
            ("ti", "chi"),
            ("tu", "tsu"),
            ("hu", "fu"),
            ("zi", "ji"),
            ("sy", "sh"),
            ("ty", "ch"),
            ("zy", "j")
        ]

        while let current = queue.popLast() {
            for (source, replacement) in replacements where current.contains(source) {
                let replaced = current.replacingOccurrences(of: source, with: replacement)
                if variants.insert(replaced).inserted {
                    queue.append(replaced)
                }
            }
        }

        return Array(variants)
    }

    private nonisolated static func longVowelRomajiVariants(
        for text: String
    ) -> [String] {
        let replacements: [(String, String)] = [
            ("ou", "o"),
            ("oo", "o"),
            ("uu", "u"),
            ("aa", "a"),
            ("ii", "i"),
            ("ee", "e")
        ]
        var variants: Set<String> = []
        var queue = [text]

        while let current = queue.popLast() {
            for (source, replacement) in replacements where current.contains(source) {
                let replaced = current.replacingOccurrences(of: source, with: replacement)
                if replaced != text, variants.insert(replaced).inserted {
                    queue.append(replaced)
                }
            }
        }

        return Array(variants)
    }

    private nonisolated static func normalizedKatakanaCharacter(
        _ character: Character
    ) -> Character {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1,
              (0x3041...0x3096).contains(Int(scalar.value)),
              let katakana = UnicodeScalar(scalar.value + 0x60) else {
            return character
        }

        return Character(katakana)
    }

    nonisolated static func romaji(
        fromKana text: String
    ) -> String? {
        let kana = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .map(normalizedHiraganaCharacter)

        guard kana.contains(where: isKanaCharacter) else {
            return nil
        }

        var result = ""
        var index = kana.startIndex
        var shouldDoubleNextConsonant = false

        while index < kana.endIndex {
            let character = kana[index]

            if character == "っ" {
                shouldDoubleNextConsonant = true
                index = kana.index(after: index)
                continue
            }

            if character == "ー" {
                index = kana.index(after: index)
                continue
            }

            let nextIndex = kana.index(after: index)
            var syllable: String?
            var didConsumeNext = false

            if nextIndex < kana.endIndex {
                let pair = String(character) + String(kana[nextIndex])
                if let pairRomaji = digraphRomaji[pair] {
                    syllable = pairRomaji
                    didConsumeNext = true
                }
            }

            if syllable == nil {
                syllable = kanaRomaji[String(character)]
            }

            guard let syllable else {
                return nil
            }

            if shouldDoubleNextConsonant,
               let first = syllable.first,
               !"aeioun".contains(first) {
                result.append(first)
            }

            result += syllable
            shouldDoubleNextConsonant = false
            index = didConsumeNext ? kana.index(after: nextIndex) : nextIndex
        }

        return result
    }

    private nonisolated static func normalizedHiraganaCharacter(
        _ character: Character
    ) -> Character {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1,
              (0x30A1...0x30F6).contains(Int(scalar.value)),
              let hiragana = UnicodeScalar(scalar.value - 0x60) else {
            return character
        }

        return Character(hiragana)
    }

    private nonisolated static func isKanaCharacter(
        _ character: Character
    ) -> Bool {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else {
            return false
        }

        return (0x3040...0x309F).contains(Int(scalar.value)) ||
            (0x30A0...0x30FF).contains(Int(scalar.value))
    }

    private nonisolated static let digraphRomaji: [String: String] = [
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
        "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
        "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
        "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo",
        "てぃ": "ti", "でぃ": "di", "うぃ": "wi", "うぇ": "we", "うぉ": "wo"
    ]

    private nonisolated static let kanaRomaji: [String: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "を": "wo", "ん": "n",
        "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
        "ゃ": "ya", "ゅ": "yu", "ょ": "yo", "ゎ": "wa"
    ]
}

// MARK: - GeoJSON Point

struct WanderlustGeoPoint: Codable, Hashable, Sendable {
    let type: String
    let coordinates: [Double]

    nonisolated init(
        type: String = "Point",
        coordinates: [Double]
    ) {
        self.type = type
        self.coordinates = coordinates
    }

    /*
     GeoJSONの座標順は以下です。

     coordinates[0] = longitude
     coordinates[1] = latitude
    */

    nonisolated var longitude: Double {
        coordinates.indices.contains(0) ? coordinates[0] : 0
    }

    nonisolated var latitude: Double {
        coordinates.indices.contains(1) ? coordinates[1] : 0
    }

    nonisolated var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    nonisolated var isValid: Bool {
        coordinates.count >= 2 &&
        (-90...90).contains(latitude) &&
        (-180...180).contains(longitude)
    }
}

// MARK: - Flexible JSON Decoding

private extension KeyedDecodingContainer {
    nonisolated func decodeFirstString(
        forKeys keys: [Key],
        defaultValue: String
    ) throws -> String {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }

        return defaultValue
    }

    nonisolated func decodeFlexibleInt(
        forKeys keys: [Key],
        defaultValue: Int
    ) throws -> Int {
        for key in keys {
            let value = try decodeFlexibleInt(
                forKey: key,
                defaultValue: Int.min
            )

            if value != Int.min {
                return value
            }
        }

        return defaultValue
    }

    nonisolated func decodeFlexibleInt(
        forKey key: Key,
        defaultValue: Int
    ) throws -> Int {
        if let integer = try decodeIfPresent(
            Int.self,
            forKey: key
        ) {
            return integer
        }

        if let double = try decodeIfPresent(
            Double.self,
            forKey: key
        ) {
            return Int(double)
        }

        if let string = try decodeIfPresent(
            String.self,
            forKey: key
        ),
           let integer = Int(string) {
            return integer
        }

        return defaultValue
    }
}
