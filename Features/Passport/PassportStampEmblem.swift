import SwiftUI

// MARK: - Passport stamp emblems
//
// 参考写真のような「国ごとのランドマークが線画で入ったスタンプ」を作る。
//
// 195 か国ぶんの図案を個別に描くのは現実的ではないので、**原型（archetype）**を
// 用意して国を割り当てる方式にした。よく使う国は専用の原型を持ち、
// それ以外も大陸や地域からもっともらしい原型へフォールバックする。
// これで「どの国を登録しても絵が出る」ことを保証できる。
//
// 図案はすべて 100×100 の座標系で描き、実際の寸法へスケールする。

enum PassportEmblemArchetype: String, CaseIterable {
    case fuji           // 富士山と鳥居
    case clockTower     // 時計塔
    case ironTower      // 鉄塔
    case colosseum      // 円形闘技場
    case brandenburg    // 列柱の門
    case mosque         // ドームとミナレット
    case pagoda         // 多層塔
    case parthenon      // 神殿の列柱
    case pyramid        // ピラミッド
    case skyline        // 摩天楼
    case windmill       // 風車
    case operaHouse     // 帆状の屋根
    case tajMahal       // ドームと尖塔
    case mountains      // 連峰
    case liberty        // 松明を掲げる像
    case globe          // 汎用（経緯線の地球）

    /// ISO2 コードから原型を決める。
    ///
    /// 未知の国は地域で寄せる。ここに無い国でも `globe` が返るので
    /// 図案が出ないことはない。
    static func archetype(forCountryCode code: String) -> PassportEmblemArchetype {
        switch code.uppercased() {
        case "JP":                          return .fuji
        case "GB", "UK", "IE":              return .clockTower
        case "FR", "BE", "LU":              return .ironTower
        case "IT", "VA", "SM", "HR":        return .colosseum
        case "DE", "AT", "PL", "CZ", "HU":  return .brandenburg
        case "TR", "MA", "AE", "SA", "QA", "OM", "KW", "BH", "JO", "IR", "AZ", "UZ", "MY", "ID", "PK", "BD":
            return .mosque
        case "TH", "CN", "KR", "VN", "MM", "KH", "LA", "TW", "NP", "LK", "MN":
            return .pagoda
        case "GR", "CY", "MT", "AL", "MK":  return .parthenon
        case "EG", "SD", "MX", "GT", "PE", "BO":
            return .pyramid
        case "US", "CA", "SG", "HK", "AR", "PA", "IL":
            return .skyline
        case "NL", "DK", "BE_WIND":         return .windmill
        case "AU", "NZ", "FJ":              return .operaHouse
        case "IN":                          return .tajMahal
        case "CH", "NO", "SE", "FI", "IS", "CL", "BT", "GE", "AM":
            return .mountains
        case "BR", "PT", "ES", "CO", "UY", "CU", "DO":
            return .liberty
        default:                            return .globe
        }
    }
}

// MARK: - Emblem view

/// スタンプの中央に置く線画。ink 色は呼び出し側から渡す。
struct PassportStampEmblem: View {
    let archetype: PassportEmblemArchetype
    let ink: Color
    var lineWidth: CGFloat = 1.4

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / 100

            ZStack {
                shape
                    .stroke(
                        ink,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            }
            .frame(width: 100, height: 100)
            .scaleEffect(scale)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }

    private var shape: some Shape {
        PassportEmblemShape(archetype: archetype)
    }
}

// MARK: - Emblem shape

/// 100×100 の座標系に描いた線画。`Shape` なので解像度に依存しない。
struct PassportEmblemShape: Shape {
    let archetype: PassportEmblemArchetype

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = min(rect.width, rect.height) / 100
        let ox = rect.minX + (rect.width - 100 * s) / 2
        let oy = rect.minY + (rect.height - 100 * s) / 2

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }

        func line(_ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            path.move(to: p(first.0, first.1))
            for point in points.dropFirst() {
                path.addLine(to: p(point.0, point.1))
            }
        }

        func ground(_ y: CGFloat = 86) {
            line([(8, y), (92, y)])
        }

        switch archetype {
        case .fuji:
            // 山体
            line([(10, 78), (38, 30), (46, 36), (54, 30), (82, 78)])
            // 冠雪
            line([(30, 44), (36, 48), (42, 42), (50, 47), (58, 41), (64, 46)])
            // 鳥居
            line([(58, 78), (58, 58)])
            line([(78, 78), (78, 58)])
            line([(52, 58), (84, 58)])
            line([(55, 64), (81, 64)])
            ground()

        case .clockTower:
            line([(38, 86), (38, 30), (62, 30), (62, 86)])
            line([(38, 62), (62, 62)])           // 文字盤の下端
            path.addEllipse(in: CGRect(x: ox + 42 * s, y: oy + 38 * s,
                                       width: 16 * s, height: 16 * s))
            line([(50, 46), (50, 41)])           // 短針
            line([(50, 46), (55, 48)])           // 長針
            line([(36, 30), (50, 14), (64, 30)]) // 尖塔
            line([(50, 14), (50, 8)])
            ground()

        case .ironTower:
            line([(20, 86), (42, 20), (50, 10), (58, 20), (80, 86)])
            line([(31, 54), (69, 54)])
            line([(26, 70), (74, 70)])
            // 脚のアーチ
            path.move(to: p(30, 86))
            path.addQuadCurve(to: p(70, 86), control: p(50, 62))
            line([(50, 10), (50, 4)])
            ground()

        case .colosseum:
            // 外周
            path.addEllipse(in: CGRect(x: ox + 16 * s, y: oy + 30 * s,
                                       width: 68 * s, height: 52 * s))
            line([(16, 56), (84, 56)])
            // アーチ列
            for column in 0..<5 {
                let x = 26 + CGFloat(column) * 12
                path.move(to: p(x - 4, 56))
                path.addQuadCurve(to: p(x + 4, 56), control: p(x, 44))
            }
            for column in 0..<5 {
                let x = 26 + CGFloat(column) * 12
                path.move(to: p(x - 4, 78))
                path.addQuadCurve(to: p(x + 4, 78), control: p(x, 66))
            }
            ground()

        case .brandenburg:
            line([(18, 82), (18, 34), (82, 34), (82, 82)])
            line([(14, 34), (86, 34)])
            line([(14, 28), (86, 28)])
            for column in 0..<5 {
                let x = 24 + CGFloat(column) * 13
                line([(x, 82), (x, 38)])
            }
            // 四頭立ての戦車を簡略化した箱
            line([(42, 28), (42, 20), (58, 20), (58, 28)])
            ground()

        case .mosque:
            // 中央ドーム
            path.move(to: p(32, 70))
            path.addQuadCurve(to: p(68, 70), control: p(50, 24))
            line([(50, 24), (50, 16)])
            path.addEllipse(in: CGRect(x: ox + 47 * s, y: oy + 12 * s,
                                       width: 6 * s, height: 6 * s))
            line([(28, 70), (72, 70)])
            line([(28, 70), (28, 84)])
            line([(72, 70), (72, 84)])
            // ミナレット
            for x in [16.0 as CGFloat, 84.0] {
                line([(x, 84), (x, 40)])
                line([(x - 4, 40), (x + 4, 40)])
                line([(x - 3, 40), (x, 30), (x + 3, 40)])
            }
            ground()

        case .pagoda:
            // 三層の屋根
            for level in 0..<3 {
                let y = 34 + CGFloat(level) * 17
                let half = 20 + CGFloat(level) * 8
                line([(50 - half, y), (50 + half, y)])
                line([(50 - half + 4, y), (50, y - 10), (50 + half - 4, y)])
            }
            line([(50, 24), (50, 16)])
            line([(40, 85), (40, 68)])
            line([(60, 85), (60, 68)])
            ground()

        case .parthenon:
            line([(14, 36), (50, 16), (86, 36)])
            line([(14, 36), (86, 36)])
            line([(18, 42), (82, 42)])
            for column in 0..<6 {
                let x = 24 + CGFloat(column) * 10.5
                line([(x, 42), (x, 80)])
            }
            line([(16, 80), (84, 80)])
            ground()

        case .pyramid:
            line([(12, 82), (44, 26), (76, 82)])
            line([(44, 26), (56, 82)])            // 稜線
            line([(58, 82), (78, 48), (94, 82)])  // 小ピラミッド
            ground()

        case .skyline:
            line([(14, 84), (14, 46), (28, 46), (28, 84)])
            line([(32, 84), (32, 28), (46, 28), (46, 84)])
            line([(39, 28), (39, 16)])
            line([(50, 84), (50, 54), (64, 54), (64, 84)])
            line([(68, 84), (68, 38), (84, 38), (84, 84)])
            // 窓
            for column in 0..<3 {
                let y = 36 + CGFloat(column) * 10
                line([(35, y), (43, y)])
            }
            ground()

        case .windmill:
            line([(38, 84), (43, 44), (57, 44), (62, 84)])
            line([(34, 84), (66, 84)])
            // 羽根
            line([(50, 44), (50, 12)])
            line([(50, 44), (78, 44)])
            line([(50, 44), (50, 76)])
            line([(50, 44), (22, 44)])
            path.addEllipse(in: CGRect(x: ox + 47 * s, y: oy + 41 * s,
                                       width: 6 * s, height: 6 * s))
            ground()

        case .operaHouse:
            // 帆状の屋根を 3 枚
            for index in 0..<3 {
                let x = 24 + CGFloat(index) * 20
                path.move(to: p(x - 14, 76))
                path.addQuadCurve(to: p(x + 10, 76), control: p(x - 6, 30 + CGFloat(index) * 4))
            }
            line([(10, 76), (90, 76)])
            line([(10, 82), (90, 82)])
            ground()

        case .tajMahal:
            path.move(to: p(34, 68))
            path.addQuadCurve(to: p(66, 68), control: p(50, 22))
            line([(50, 22), (50, 14)])
            line([(30, 68), (70, 68)])
            line([(30, 68), (30, 82)])
            line([(70, 68), (70, 82)])
            // アーチ
            path.move(to: p(44, 82))
            path.addQuadCurve(to: p(56, 82), control: p(50, 60))
            for x in [18.0 as CGFloat, 82.0] {
                line([(x, 82), (x, 44)])
                line([(x - 3, 44), (x, 36), (x + 3, 44)])
            }
            ground()

        case .mountains:
            line([(6, 82), (30, 40), (44, 60), (58, 32), (94, 82)])
            line([(24, 50), (30, 46), (36, 52)])   // 冠雪
            line([(52, 42), (58, 38), (64, 44)])
            ground(82)

        case .liberty:
            line([(50, 82), (50, 40)])             // 体
            line([(50, 46), (66, 30)])             // 腕
            line([(66, 30), (66, 22)])             // 松明
            line([(62, 22), (70, 22), (66, 14), (62, 22)])
            path.addEllipse(in: CGRect(x: ox + 44 * s, y: oy + 28 * s,
                                       width: 12 * s, height: 12 * s))
            // 冠
            line([(44, 28), (42, 22)])
            line([(50, 27), (50, 20)])
            line([(56, 28), (58, 22)])
            line([(38, 82), (50, 58), (62, 82)])   // 裾
            line([(34, 82), (66, 82)])
            line([(30, 88), (70, 88)])             // 台座
            ground(88)

        case .globe:
            path.addEllipse(in: CGRect(x: ox + 20 * s, y: oy + 20 * s,
                                       width: 60 * s, height: 60 * s))
            line([(20, 50), (80, 50)])
            // 経線
            path.move(to: p(50, 20))
            path.addQuadCurve(to: p(50, 80), control: p(24, 50))
            path.move(to: p(50, 20))
            path.addQuadCurve(to: p(50, 80), control: p(76, 50))
            // 緯線
            path.move(to: p(27, 35))
            path.addQuadCurve(to: p(73, 35), control: p(50, 43))
            path.move(to: p(27, 65))
            path.addQuadCurve(to: p(73, 65), control: p(50, 57))
        }

        return path
    }
}

#if DEBUG
#Preview("Emblems") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 16) {
            ForEach(PassportEmblemArchetype.allCases, id: \.self) { archetype in
                VStack(spacing: 6) {
                    PassportStampEmblem(
                        archetype: archetype,
                        ink: Color(red: 0.10, green: 0.18, blue: 0.42)
                    )
                    .frame(width: 78, height: 78)

                    Text(archetype.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
#endif

// MARK: - Passport cover globe
//
// 表紙中央の箔押し地球儀。参考写真に合わせ、経緯線の上に大陸のシルエットを
// 載せた「線画 + 面」の構成にしている。
// SF Symbol の globe だと線が均一すぎて箔押しに見えないため自前で描く。
//
// 座標系は 100×100。緯度経度から起こすと重いので、参考写真と同じ見え方に
// なるよう大陸を手作業で単純化した多角形で置いている。

/// 大陸のシルエット（塗り）。
struct PassportGlobeLandmass: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = min(rect.width, rect.height) / 100
        let ox = rect.minX + (rect.width - 100 * s) / 2
        let oy = rect.minY + (rect.height - 100 * s) / 2

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }

        func polygon(_ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            path.move(to: p(first.0, first.1))
            for point in points.dropFirst() {
                path.addLine(to: p(point.0, point.1))
            }
            path.closeSubpath()
        }

        // 北アメリカ
        polygon([
            (14, 30), (26, 25), (36, 28), (38, 36), (33, 42),
            (34, 50), (29, 54), (26, 47), (20, 44), (15, 37)
        ])
        // 中米〜南アメリカ
        polygon([
            (30, 56), (36, 55), (41, 62), (40, 74), (35, 84),
            (31, 82), (32, 72), (28, 64)
        ])
        // ヨーロッパ
        polygon([
            (50, 26), (60, 24), (64, 30), (59, 35), (52, 34)
        ])
        // アフリカ
        polygon([
            (50, 38), (62, 36), (68, 44), (66, 58), (60, 72),
            (55, 78), (52, 70), (54, 56), (49, 46)
        ])
        // アジア
        polygon([
            (64, 22), (82, 20), (88, 28), (84, 38), (76, 44),
            (70, 40), (66, 32)
        ])
        // 東南アジア・豪州
        polygon([
            (76, 52), (86, 50), (90, 58), (84, 66), (77, 62)
        ])

        return path
    }
}

/// 経緯線。
struct PassportGlobeGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = min(rect.width, rect.height) / 100
        let ox = rect.minX + (rect.width - 100 * s) / 2
        let oy = rect.minY + (rect.height - 100 * s) / 2

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }

        // 赤道
        path.move(to: p(4, 50))
        path.addLine(to: p(96, 50))

        // 緯線（上下 2 本ずつ）
        for offset in [22.0 as CGFloat, 78.0] {
            let bulge: CGFloat = offset < 50 ? 8 : -8
            path.move(to: p(18, offset))
            path.addQuadCurve(to: p(82, offset), control: p(50, offset + bulge))
        }

        // 経線
        for control in [16.0 as CGFloat, 34, 66, 84] {
            path.move(to: p(50, 4))
            path.addQuadCurve(to: p(50, 96), control: p(control, 50))
        }
        path.move(to: p(50, 4))
        path.addLine(to: p(50, 96))

        return path
    }
}

/// 表紙中央の地球儀エンブレム（軌道リングと機体つき）。
struct PassportCoverGlobe: View {
    let gold: LinearGradient
    let lineColor: Color
    var scale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let globe = size * 0.60

            ZStack {
                // 外側の軌道（破線）
                Circle()
                    .stroke(
                        lineColor.opacity(0.42),
                        style: StrokeStyle(
                            lineWidth: 0.7 * scale,
                            dash: [2.4 * scale, 3.4 * scale]
                        )
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-16))

                // 内側の軌道（実線・一部だけ）
                Circle()
                    .trim(from: 0.06, to: 0.78)
                    .stroke(lineColor.opacity(0.55), lineWidth: 0.8 * scale)
                    .frame(width: size * 0.84, height: size * 0.84)
                    .rotationEffect(.degrees(-28))

                // 軌道上の点
                ForEach([28.0, 152.0, 262.0], id: \.self) { angle in
                    Circle()
                        .fill(lineColor.opacity(0.75))
                        .frame(width: 2.6 * scale, height: 2.6 * scale)
                        .offset(y: -size / 2)
                        .rotationEffect(.degrees(angle))
                }

                // 地球本体
                ZStack {
                    Circle()
                        .stroke(lineColor.opacity(0.85), lineWidth: 0.9 * scale)

                    PassportGlobeGrid()
                        .stroke(lineColor.opacity(0.40), lineWidth: 0.55 * scale)
                        .clipShape(Circle())

                    PassportGlobeLandmass()
                        .fill(gold)
                        .clipShape(Circle())
                }
                .frame(width: globe, height: globe)

                // 軌道上を飛ぶ機体
                Image(systemName: "airplane")
                    .font(.system(size: 11 * scale, weight: .regular))
                    .foregroundStyle(gold)
                    .rotationEffect(.degrees(-24))
                    .offset(x: size * 0.34, y: -size * 0.36)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}
