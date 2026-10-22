import Foundation

// Curated Japanese reading aliases for high-demand travel search targets.
enum JapaneseSearchReadingAliases {
    struct CityTarget: Hashable, Sendable {
        let countryCode: String
        let name: String
        fileprivate let matchNames: [String]
        fileprivate let aliases: [String]

        init(
            countryCode: String,
            name: String,
            matchNames: [String] = [],
            aliases: [String]
        ) {
            self.countryCode = countryCode.uppercased()
            self.name = name
            self.matchNames = ([name] + matchNames)
            self.aliases = aliases
        }
    }

    nonisolated static func matchingCityTargets(
        for normalizedQueries: [String]
    ) -> [CityTarget] {
        cityTargets.filter { target in
            aliasesMatch(target.aliases, normalizedQueries: normalizedQueries)
        }
    }

    nonisolated static func cityAliases(
        countryCode: String,
        cityName: String
    ) -> [String] {
        let normalizedCountryCode = countryCode.uppercased()
        let normalizedCityName = normalize(cityName)
        guard !normalizedCountryCode.isEmpty, !normalizedCityName.isEmpty else {
            return []
        }

        return cityTargets
            .filter { target in
                target.countryCode == normalizedCountryCode &&
                    target.matchNames.contains { normalize($0) == normalizedCityName }
            }
            .flatMap(\.aliases)
    }

    nonisolated static func matchingAirportCodes(
        for normalizedQueries: [String]
    ) -> [String] {
        matchingAirportCodes(
            for: normalizedQueries,
            match: .prefix
        )
    }

    nonisolated static func matchingAirportCodes(
        for normalizedQueries: [String],
        match: AliasMatch
    ) -> [String] {
        airportAliasesByCode.compactMap { code, aliases in
            aliasesMatch(aliases, normalizedQueries: normalizedQueries, match: match) ? code : nil
        }
        .sorted { first, second in
            let firstPriority = AirportSearchRank.priority(for: first)
            let secondPriority = AirportSearchRank.priority(for: second)
            if firstPriority != secondPriority {
                return firstPriority < secondPriority
            }
            return first < second
        }
    }

    nonisolated static func airportAliases(
        code: String
    ) -> [String] {
        airportAliasesByCode[code.uppercased()] ?? []
    }

    nonisolated static func matchingAirlineCodes(
        for normalizedQueries: [String]
    ) -> [String] {
        airlineAliasesByCode.compactMap { code, aliases in
            aliasesMatch(aliases, normalizedQueries: normalizedQueries) ? code : nil
        }
        .sorted { first, second in
            let firstPriority = AirlineSearchRank.priority(for: first)
            let secondPriority = AirlineSearchRank.priority(for: second)
            if firstPriority != secondPriority {
                return firstPriority < secondPriority
            }
            return first < second
        }
    }

    nonisolated static func airlineAliases(
        code: String
    ) -> [String] {
        airlineAliasesByCode[code.uppercased()] ?? []
    }

    nonisolated static func airlineAliasMatches(
        code: String,
        normalizedQueries: [String]
    ) -> Bool {
        aliasesMatch(
            airlineAliases(code: code),
            normalizedQueries: normalizedQueries
        )
    }

    private nonisolated static func aliasesMatch(
        _ aliases: [String],
        normalizedQueries: [String],
        match: AliasMatch = .prefix
    ) -> Bool {
        normalizedAliases(for: aliases).contains { alias in
            normalizedQueries.contains { query in
                switch match {
                case .exact:
                    return alias == query
                case .prefix:
                    return alias == query || alias.hasPrefix(query)
                }
            }
        }
    }

    private nonisolated static func normalizedAliases(
        for aliases: [String]
    ) -> [String] {
        var normalized: [String] = []
        for alias in aliases {
            normalized.append(
                contentsOf: JapaneseKanaRomajiSearch.normalizedQueryVariants(
                    alias,
                    normalizer: normalize
                )
            )
        }
        var seen = Set<String>()
        return normalized.filter { seen.insert($0).inserted }
    }

    private nonisolated static func normalize(_ value: String) -> String {
        SearchNormalizer.normalize(value)
    }

    enum AliasMatch: Sendable {
        case exact
        case prefix
    }

    private nonisolated static let cityTargets: [CityTarget] = [
        CityTarget(countryCode: "JP", name: "Osaka", aliases: ["おおさか"]),
        CityTarget(countryCode: "JP", name: "Kyoto", aliases: ["きょうと"]),
        CityTarget(countryCode: "JP", name: "Yokohama", aliases: ["よこはま"]),
        CityTarget(countryCode: "JP", name: "Sapporo", aliases: ["さっぽろ"]),
        CityTarget(countryCode: "JP", name: "Fukuoka", aliases: ["ふくおか"]),
        CityTarget(countryCode: "JP", name: "Nagoya", aliases: ["なごや"]),
        CityTarget(countryCode: "JP", name: "Kobe", aliases: ["こうべ"]),
        CityTarget(countryCode: "JP", name: "Naha", aliases: ["なは"]),
        CityTarget(countryCode: "JP", name: "Hiroshima", aliases: ["ひろしま"]),
        CityTarget(countryCode: "JP", name: "Kanazawa", aliases: ["かなざわ"]),
        CityTarget(countryCode: "JP", name: "Hakone", aliases: ["はこね"]),
        CityTarget(countryCode: "JP", name: "Nara", aliases: ["なら"]),
        CityTarget(countryCode: "JP", name: "Kamakura", aliases: ["かまくら"]),
        CityTarget(countryCode: "JP", name: "Nikko", aliases: ["にっこう"]),
        CityTarget(countryCode: "JP", name: "Hakodate", aliases: ["はこだて"]),
        CityTarget(countryCode: "JP", name: "Otaru", aliases: ["おたる"]),
        CityTarget(countryCode: "JP", name: "Beppu", aliases: ["べっぷ"]),
        CityTarget(countryCode: "JP", name: "Nagasaki", aliases: ["ながさき"]),
        CityTarget(countryCode: "JP", name: "Matsumoto", aliases: ["まつもと"]),
        CityTarget(countryCode: "JP", name: "Takayama", aliases: ["たかやま"]),
        CityTarget(countryCode: "JP", name: "Sendai", aliases: ["せんだい"]),
        CityTarget(countryCode: "JP", name: "Chiba", aliases: ["ちば"]),
        CityTarget(countryCode: "JP", name: "Saitama", aliases: ["さいたま"]),
        CityTarget(countryCode: "US", name: "New York City", matchNames: ["New York"], aliases: ["にゅーよーく", "ニューヨーク", "ニューヨーク市"]),
        CityTarget(countryCode: "US", name: "Los Angeles", aliases: ["ろさんぜるす", "ロサンゼルス"]),
        CityTarget(countryCode: "US", name: "San Francisco", aliases: ["さんふらんしすこ", "サンフランシスコ"]),
        CityTarget(countryCode: "US", name: "Honolulu", aliases: ["ほのるる", "ホノルル"]),
        CityTarget(countryCode: "US", name: "Las Vegas", aliases: ["らすべがす", "ラスベガス"]),
        CityTarget(countryCode: "US", name: "Seattle", aliases: ["しあとる", "シアトル"]),
        CityTarget(countryCode: "US", name: "Chicago", aliases: ["しかご", "シカゴ"]),
        CityTarget(countryCode: "US", name: "Boston", aliases: ["ぼすとん", "ボストン"]),
        CityTarget(countryCode: "US", name: "Washington", aliases: ["わしんとん", "ワシントン", "ワシントンDC"]),
        CityTarget(countryCode: "US", name: "Miami", aliases: ["まいあみ", "マイアミ"]),
        CityTarget(countryCode: "US", name: "Orlando", aliases: ["おーらんど", "オーランド"]),
        CityTarget(countryCode: "CA", name: "Vancouver", aliases: ["ばんくーばー", "バンクーバー"]),
        CityTarget(countryCode: "CA", name: "Toronto", aliases: ["とろんと", "トロント"]),
        CityTarget(countryCode: "GB", name: "London", aliases: ["ろんどん", "ロンドン", "ロンドン市"]),
        CityTarget(countryCode: "FR", name: "Paris", aliases: ["ぱり", "パリ", "パリス"]),
        CityTarget(countryCode: "IT", name: "Rome", aliases: ["ろーま", "ローマ"]),
        CityTarget(countryCode: "IT", name: "Milan", aliases: ["みらの", "ミラノ"]),
        CityTarget(countryCode: "IT", name: "Venice", aliases: ["べねちあ", "ヴェネツィア", "ベネチア", "ベニス"]),
        CityTarget(countryCode: "IT", name: "Florence", aliases: ["ふぃれんつぇ", "フィレンツェ", "フローレンス"]),
        CityTarget(countryCode: "ES", name: "Barcelona", aliases: ["ばるせろな", "バルセロナ"]),
        CityTarget(countryCode: "ES", name: "Madrid", aliases: ["まどりーど", "マドリード"]),
        CityTarget(countryCode: "NL", name: "Amsterdam", aliases: ["あむすてるだむ", "アムステルダム"]),
        CityTarget(countryCode: "DE", name: "Berlin", aliases: ["べるりん", "ベルリン"]),
        CityTarget(countryCode: "DE", name: "Munich", aliases: ["みゅんへん", "ミュンヘン"]),
        CityTarget(countryCode: "DE", name: "Frankfurt am Main", matchNames: ["Frankfurt"], aliases: ["ふらんくふると", "フランクフルト"]),
        CityTarget(countryCode: "AT", name: "Vienna", aliases: ["うぃーん", "ウィーン"]),
        CityTarget(countryCode: "CH", name: "Zurich", aliases: ["ちゅーりっひ", "チューリッヒ"]),
        CityTarget(countryCode: "CH", name: "Geneva", aliases: ["じゅねーぶ", "ジュネーブ"]),
        CityTarget(countryCode: "DK", name: "Copenhagen", aliases: ["こぺんはーげん", "コペンハーゲン"]),
        CityTarget(countryCode: "SE", name: "Stockholm", aliases: ["すとっくほるむ", "ストックホルム"]),
        CityTarget(countryCode: "NO", name: "Oslo", aliases: ["おすろ", "オスロ"]),
        CityTarget(countryCode: "FI", name: "Helsinki", aliases: ["へるしんき", "ヘルシンキ"]),
        CityTarget(countryCode: "CZ", name: "Prague", aliases: ["ぷらは", "プラハ", "プラーグ"]),
        CityTarget(countryCode: "GR", name: "Athens", aliases: ["あてね", "アテネ", "アセンズ"]),
        CityTarget(countryCode: "PT", name: "Lisbon", aliases: ["りすぼん", "リスボン"]),
        CityTarget(countryCode: "PT", name: "Porto", aliases: ["ぽると", "ポルト"]),
        CityTarget(countryCode: "HU", name: "Budapest", aliases: ["ぶだぺすと", "ブダペスト"]),
        CityTarget(countryCode: "BE", name: "Brussels", aliases: ["ぶりゅっせる", "ブリュッセル"]),
        CityTarget(countryCode: "PL", name: "Warsaw", aliases: ["わるしゃわ", "ワルシャワ"]),
        CityTarget(countryCode: "TR", name: "Istanbul", aliases: ["いすたんぶーる", "イスタンブール", "イスタンブル"]),
        CityTarget(countryCode: "TR", name: "Antalya", aliases: ["あんたるや", "アンタルヤ"]),
        CityTarget(countryCode: "AE", name: "Dubai", aliases: ["どばい", "ドバイ", "ドゥバイ"]),
        CityTarget(countryCode: "AE", name: "Abu Dhabi", aliases: ["あぶだび", "アブダビ"]),
        CityTarget(countryCode: "SA", name: "Makkah", matchNames: ["Mecca"], aliases: ["めっか", "メッカ", "マッカ"]),
        CityTarget(countryCode: "SA", name: "Madinah", matchNames: ["Medina"], aliases: ["めでぃな", "メディナ", "マディーナ"]),
        CityTarget(countryCode: "SG", name: "Singapore", aliases: ["しんがぽーる", "シンガポール"]),
        CityTarget(countryCode: "TH", name: "Bangkok", aliases: ["ばんこく", "バンコク", "バンコック"]),
        CityTarget(countryCode: "TH", name: "Chiang Mai", aliases: ["ちぇんまい", "チェンマイ"]),
        CityTarget(countryCode: "TH", name: "Phuket", aliases: ["ぷーけっと", "プーケット"]),
        CityTarget(countryCode: "TH", name: "Krabi", aliases: ["くらび", "クラビ"]),
        CityTarget(countryCode: "MY", name: "Kuala Lumpur", aliases: ["くあらるんぷーる", "クアラルンプール"]),
        CityTarget(countryCode: "KR", name: "Seoul", aliases: ["そうる", "ソウル"]),
        CityTarget(countryCode: "KR", name: "Busan", aliases: ["ぷさん", "ぶさん", "釜山"]),
        CityTarget(countryCode: "KR", name: "Jeju City", matchNames: ["Jeju"], aliases: ["ちぇじゅ", "チェジュ", "済州", "済州市"]),
        CityTarget(countryCode: "TW", name: "Taipei", aliases: ["たいぺい", "台北"]),
        CityTarget(countryCode: "TW", name: "Kaohsiung", aliases: ["たかお", "高雄"]),
        CityTarget(countryCode: "HK", name: "Hong Kong", aliases: ["ほんこん", "ホンコン", "香港"]),
        CityTarget(countryCode: "MO", name: "Macau", matchNames: ["Macao"], aliases: ["まかお", "マカオ", "澳門"]),
        CityTarget(countryCode: "CN", name: "Shanghai", aliases: ["しゃんはい", "上海"]),
        CityTarget(countryCode: "CN", name: "Beijing", aliases: ["ぺきん", "北京"]),
        CityTarget(countryCode: "CN", name: "Guangzhou", aliases: ["こうしゅう", "広州"]),
        CityTarget(countryCode: "CN", name: "Shenzhen", aliases: ["しんせん", "深圳"]),
        CityTarget(countryCode: "IN", name: "Delhi", aliases: ["でりー", "デリー"]),
        CityTarget(countryCode: "IN", name: "Mumbai", aliases: ["むんばい", "ムンバイ"]),
        CityTarget(countryCode: "IN", name: "Agra", aliases: ["あぐら", "アグラ"]),
        CityTarget(countryCode: "AU", name: "Sydney", aliases: ["しどにー", "シドニー"]),
        CityTarget(countryCode: "AU", name: "Melbourne", aliases: ["めるぼるん", "メルボルン"]),
        CityTarget(countryCode: "NZ", name: "Auckland", aliases: ["おーくらんど", "オークランド"]),
        CityTarget(countryCode: "NZ", name: "Queenstown", aliases: ["くいーんずたうん", "クイーンズタウン"]),
        CityTarget(countryCode: "ID", name: "Denpasar", aliases: ["でんぱさーる", "デンパサール", "バリ"]),
        CityTarget(countryCode: "ID", name: "Ubud", aliases: ["うぶど", "ウブド"]),
        CityTarget(countryCode: "VN", name: "Ho Chi Minh City", aliases: ["ほーちみん", "ホーチミン", "ホーチミン市", "サイゴン"]),
        CityTarget(countryCode: "VN", name: "Hanoi", aliases: ["はのい", "ハノイ"]),
        CityTarget(countryCode: "VN", name: "Da Nang", aliases: ["だなん", "ダナン"]),
        CityTarget(countryCode: "EG", name: "Cairo", aliases: ["かいろ", "カイロ"]),
        CityTarget(countryCode: "MA", name: "Marrakesh", aliases: ["まらけしゅ", "マラケシュ"]),
        CityTarget(countryCode: "MX", name: "Cancún", matchNames: ["Cancun"], aliases: ["かんくん", "カンクン"]),
        CityTarget(countryCode: "BR", name: "Rio de Janeiro", aliases: ["りおでじゃねいろ", "リオデジャネイロ"]),
        CityTarget(countryCode: "AR", name: "Buenos Aires", aliases: ["ぶえのすあいれす", "ブエノスアイレス"])
    ]

    private nonisolated static let airportAliasesByCode: [String: [String]] = [
        "HND": ["はねだ", "羽田", "とうきょう", "東京"], "NRT": ["なりた", "成田", "とうきょう", "東京"],
        "KIX": ["かんくう", "関空", "かんさい", "おおさか", "大阪"],
        "ITM": ["いたみ", "伊丹", "おおさか", "大阪"], "CTS": ["しんちとせ", "新千歳", "さっぽろ", "札幌"],
        "FUK": ["ふくおか", "福岡"],
        "NGO": ["ちゅうぶ", "せんとれあ", "セントレア", "なごや", "名古屋"], "OKA": ["なは", "那覇"],
        "HIJ": ["ひろしま", "広島"],
        "JFK": ["じぇーえふけー", "ニューヨーク"], "LGA": ["らがーでぃあ"], "EWR": ["にゅーあーく"],
        "LAX": ["えるえーえっくす", "ろさんぜるす"], "SFO": ["さんふらんしすこ"], "HNL": ["ほのるる"],
        "LAS": ["らすべがす"], "SEA": ["しあとる"], "ORD": ["しかご", "おへあ"], "BOS": ["ぼすとん"],
        "IAD": ["わしんとん", "だれす"], "DCA": ["れーがん"], "MIA": ["まいあみ"],
        "YVR": ["ばんくーばー"], "YYZ": ["とろんと"], "LHR": ["ひーすろー", "ろんどん"],
        "LGW": ["がとwick", "がとぃっく"], "CDG": ["しゃるるどごーる", "ぱり"], "ORY": ["おるりー"],
        "FCO": ["ふぃうみちーの", "ろーま"], "MXP": ["まるぺんさ", "みらの"], "VCE": ["べねちあ"],
        "BCN": ["ばるせろな"], "MAD": ["まどりーど"], "AMS": ["すきぽーる", "あむすてるだむ"],
        "FRA": ["ふらんくふると"], "MUC": ["みゅんへん"], "VIE": ["うぃーん"], "ZRH": ["ちゅーりっひ"],
        "CPH": ["こぺんはーげん"], "ARN": ["すとっくほるむ"], "HEL": ["へるしんき"],
        "IST": ["いすたんぶーる"], "DXB": ["どばい"], "AUH": ["あぶだび"], "SIN": ["しんがぽーる"],
        "BKK": ["すわんなぷーむ", "ばんこく"], "DMK": ["どんむあん"], "HKT": ["ぷーけっと"],
        "ICN": ["いんちょん", "仁川"], "GMP": ["きんぽ", "金浦"], "PUS": ["ぷさん", "釜山"],
        "TPE": ["たいぺい", "とうえん", "桃園"], "TSA": ["しょうざん", "松山"], "KHH": ["たかお", "高雄"],
        "HKG": ["ほんこん", "香港"], "MFM": ["まかお"], "PVG": ["ぷどん", "上海"], "SHA": ["ほんちゃお", "虹橋"],
        "PEK": ["ぺきん", "首都"], "PKX": ["だいこう", "大興"], "CAN": ["こうしゅう", "広州"], "SZX": ["しんせん", "深圳"],
        "SYD": ["しどにー"], "MEL": ["めるぼるん"], "AKL": ["おーくらんど"], "ZQN": ["くいーんずたうん"],
        "DPS": ["でんぱさーる", "ばり", "バリ"]
    ]

    private nonisolated static let airlineAliasesByCode: [String: [String]] = {
        var aliases: [String: [String]] = [
        "JL": ["じゃる", "にほんこうくう", "日本航空"], "NH": ["あな", "ぜんにっくう", "全日空"],
        "BC": ["すかいまーく"], "MM": ["ぴーち"], "GK": ["じぇっとすたーじゃぱん"], "7G": ["すたーふらいやー"],
        "SQ": ["しんがぽーるこうくう"], "TG": ["たいこうくう"], "KE": ["こりあんえあー", "だいかんこうくう"],
        "OZ": ["あしあな"], "CI": ["ちゃいなえあらいん"], "BR": ["えばーこうくう"],
        "CX": ["きゃせい", "きゃせいぱしふぃっく"], "UO": ["ほんこんえくすぷれす"],
        "CA": ["えあちゃいな", "ちゅうごくこくさいこうくう"], "MU": ["ちゅうごくとうほうこうくう"],
        "CZ": ["ちゅうごくなんぽうこうくう"], "EK": ["えみれーつ"], "EY": ["えてぃはど"], "QR": ["かたーるこうくう"],
        "TK": ["たーきっしゅ", "とるここうくう"], "BA": ["ぶりてぃっしゅえあうぇいず"],
        "AF": ["えーるふらんす"], "LH": ["るふとはんざ"], "KL": ["けーえるえむ"], "AZ": ["いたこうくう"],
        "AY": ["ふぃんえあー"], "UA": ["ゆないてっど"], "AA": ["あめりかんこうくう"], "DL": ["でるた"],
        "AC": ["えあかなだ"], "QF": ["かんたす"], "JQ": ["じぇっとすたー"], "NZ": ["にゅーじーらんどこうくう"],
        "VN": ["べとなむこうくう"], "GA": ["がるーだ"], "PR": ["ふぃりぴんこうくう"],
        "MH": ["まれーしあこうくう"], "AI": ["えあいんでぃあ"]
        ]

        return aliases
    }()
}
