import SwiftUI
import UIKit

// MARK: - Passport Entry

struct PassportEntry: Identifiable {
    let id: String
    let countryName: String
    let countryCode: String
    let flagEmoji: String
    let continent: String
    let firstVisit: Date
    let lastVisit: Date
    let tripCount: Int
    let cityNames: [String]
    let trips: [Trip]
}

private struct PassportStampStyle {
    let seed: UInt64
    let designSeed: UInt64
    private let countryCode: String

    init(entry: PassportEntry) {
        let dateSeed = Int(entry.firstVisit.timeIntervalSinceReferenceDate / 86_400)
        self.seed = Self.stableSeed("\(entry.id)|\(entry.countryCode)|\(dateSeed)")
        self.countryCode = entry.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let designKey = self.countryCode.isEmpty ? entry.countryName.uppercased() : self.countryCode
        self.designSeed = Self.stableSeed(designKey)
    }

    var xOffset: CGFloat { value(index: 1, range: -18...18) }
    var yOffset: CGFloat { value(index: 2, range: -8...18) }
    var rotation: Double { Double(value(index: 6, range: -6...6)) }
    var inkOpacity: Double { Double(value(index: 8, range: 80...94)) / 100 }
    var bleedOpacity: Double { Double(value(index: 9, range: 8...16)) / 100 }
    var wearOpacity: Double { Double(value(index: 10, range: 12...22)) / 100 }
    static let standardWidthRatio: CGFloat = 0.35

    var widthRatio: CGFloat {
        Self.standardWidthRatio
    }

    func value(index: UInt64, range: ClosedRange<CGFloat>) -> CGFloat {
        let fraction = Double(Self.mix(seed &+ index)) / Double(UInt64.max)
        return range.lowerBound + CGFloat(fraction) * (range.upperBound - range.lowerBound)
    }

    func designValue(index: UInt64, range: ClosedRange<CGFloat>) -> CGFloat {
        let fraction = Double(Self.mix(designSeed &+ index)) / Double(UInt64.max)
        return range.lowerBound + CGFloat(fraction) * (range.upperBound - range.lowerBound)
    }

    static func stableSeed(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for scalar in text.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    static func mix(_ value: UInt64) -> UInt64 {
        var x = value
        x ^= x >> 30
        x &*= 0xbf58_476d_1ce4_e5b9
        x ^= x >> 27
        x &*= 0x94d0_49bb_1331_11eb
        x ^= x >> 31
        return x
    }
}

// MARK: - Passport Theme

private enum PassportTheme {
    // Cover — fixed navy, never adapts to dark mode
    static let navyDeep  = Color(red: 0.048, green: 0.072, blue: 0.138)
    static let navyMid   = Color(red: 0.065, green: 0.098, blue: 0.178)
    static let navyEdge  = Color(red: 0.036, green: 0.054, blue: 0.108)
    static let gold      = Color(red: 0.788, green: 0.659, blue: 0.298)
    static let goldDim   = Color(red: 0.650, green: 0.535, blue: 0.220)
    static let paperBase = Color(red: 0.920, green: 0.890, blue: 0.810)
    static let paperBack = Color(red: 0.840, green: 0.800, blue: 0.700)
    static let paperEdge = Color(red: 0.560, green: 0.490, blue: 0.340)
    static let watermark = Color(red: 0.560, green: 0.430, blue: 0.230)
    static let pageNumber = Color(red: 0.610, green: 0.500, blue: 0.280)
    static let watermarkDark = Color(red: 0.700, green: 0.620, blue: 0.500)
    static let pageNumberDark = Color(red: 0.740, green: 0.640, blue: 0.460)
    static let securityInkDark = Color(red: 0.640, green: 0.560, blue: 0.450)
    static let pageCornerRadius: CGFloat = 24
    static let pageAspectRatio: CGFloat = 0.66

    // Paper — adapts to color scheme
    static let paperLight  = UIColor(red: 0.965, green: 0.945, blue: 0.895, alpha: 1)
    static let paperDark   = UIColor(red: 0.212, green: 0.188, blue: 0.165, alpha: 1)

    static func pageBase(_ s: ColorScheme) -> Color {
        s == .dark ? Color(uiColor: paperDark) : Color(uiColor: paperLight)
    }
    static func pageSecondary(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.180, green: 0.160, blue: 0.140) : Color(red: 0.925, green: 0.905, blue: 0.845)
    }
    static func primaryText(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.94, green: 0.91, blue: 0.82) : Color(red: 0.065, green: 0.090, blue: 0.120)
    }
    static func secondaryText(_ s: ColorScheme) -> Color {
        s == .dark ? Color(red: 0.84, green: 0.79, blue: 0.68) : Color(red: 0.35, green: 0.32, blue: 0.26)
    }
    static func watermarkInk(_ s: ColorScheme) -> Color {
        s == .dark ? watermarkDark : watermark
    }
    static func pageNumberInk(_ s: ColorScheme) -> Color {
        s == .dark ? pageNumberDark : pageNumber
    }
    static func securityPatternInk(_ s: ColorScheme) -> Color {
        s == .dark ? securityInkDark : Color.black
    }
}

private enum PassportPaperAsset {
    static let texture = "PassportPaperTexture"
    static let darkTexture = "PassportPaperTextureDark"
    static let securityPattern = "PassportSecurityPattern"
    static let backTexture = "PassportPaperBackTexture"
    static let darkBackTexture = "PassportPaperBackTextureDark"
    static let bindingTexture = "PassportBindingOverlay"
    static let leftPageSliver = "PassportLeftPageSliver"

    static let allNames = [
        texture,
        darkTexture,
        backTexture,
        darkBackTexture,
        securityPattern,
        bindingTexture,
        leftPageSliver
    ]

    static func pageTexture(colorScheme: ColorScheme, isBack: Bool) -> String {
        if colorScheme == .dark {
            return isBack ? darkBackTexture : darkTexture
        }
        return isBack ? backTexture : texture
    }
}

private struct PassportBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.125, green: 0.112, blue: 0.098),
                   Color(red: 0.088, green: 0.078, blue: 0.070),
                   Color(red: 0.052, green: 0.047, blue: 0.043)]
                : [Color(red: 0.957, green: 0.945, blue: 0.921),
                   Color(red: 0.937, green: 0.921, blue: 0.890),
                   Color(red: 0.914, green: 0.894, blue: 0.858)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#if DEBUG
private var didValidatePassportAssets = false

private func validatePassportAssets() {
    guard !didValidatePassportAssets else { return }
    didValidatePassportAssets = true

    for name in PassportPaperAsset.allNames {
        if UIImage(named: name) == nil {
            WanderlustDiagnostics.warning("missing passport asset: \(name)", category: .ui)
        } else {
            WanderlustDiagnostics.info("loaded passport asset: \(name)", category: .ui)
        }
    }
}
#endif

// MARK: - Compass Star Shape

private struct CompassStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let outerR = min(rect.width, rect.height) / 2.0
        let innerR = outerR * 0.28
        let midR   = outerR * 0.60
        var path = Path()
        let count = 16
        for i in 0..<count {
            let angle = Double(i) * (2 * .pi) / Double(count) - .pi / 2
            let r: CGFloat
            switch i % 4 {
            case 0: r = outerR
            case 2: r = midR
            default: r = innerR
            }
            let pt = CGPoint(x: cx + CGFloat(cos(angle)) * r, y: cy + CGFloat(sin(angle)) * r)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

private struct PassportRightPageShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) * 0.18)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Textures

private struct LeatherTexture: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 7
            var x: CGFloat = 1
            while x < size.width {
                var y: CGFloat = 1
                while y < size.height {
                    let w = CGFloat(((Int(x) * 17 + Int(y) * 5) % 4) + 1)
                    let a = Double(((Int(x) * 11 + Int(y) * 13) % 9) + 2) / 100
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: 1.2)), with: .color(.white.opacity(a)))
                    y += spacing
                }
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PassportPaperSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    var isBack = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                isBack ? PassportTheme.pageSecondary(colorScheme) : PassportTheme.pageBase(colorScheme)
                Image(PassportPaperAsset.pageTexture(colorScheme: colorScheme, isBack: isBack))
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .contrast(colorScheme == .dark ? 1.06 : 1.0)
                    .blendMode(.normal)
                if !isBack {
                    Image(PassportPaperAsset.securityPattern)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .colorMultiply(PassportTheme.securityPatternInk(colorScheme))
                        .opacity(colorScheme == .dark ? 0.16 : 0.20)
                        .blendMode(colorScheme == .dark ? .overlay : .multiply)
                        .allowsHitTesting(false)
                }
            }
        }
        .clipped()
    }
}

private struct PassportPageBackContent: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PassportTheme.pageSecondary(colorScheme)
                Image(PassportPaperAsset.pageTexture(colorScheme: colorScheme, isBack: true))
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .contrast(colorScheme == .dark ? 1.04 : 1.0)
                    .blendMode(.normal)
                Image(PassportPaperAsset.securityPattern)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .colorMultiply(PassportTheme.securityPatternInk(colorScheme))
                    .blendMode(colorScheme == .dark ? .overlay : .multiply)
                    .opacity(colorScheme == .dark ? 0.12 : 0.08)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(PassportRightPageShape(cornerRadius: PassportTheme.pageCornerRadius))
    }
}

private struct PassportLeftPageSliver: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            PassportTheme.pageBase(colorScheme)
            Image(PassportPaperAsset.leftPageSliver)
                .resizable()
                .scaledToFill()
                .contrast(colorScheme == .dark ? 1.04 : 1.0)
                .opacity(colorScheme == .dark ? 0.30 : 0.62)
                .blendMode(colorScheme == .dark ? .overlay : .multiply)
                .allowsHitTesting(false)

            LinearGradient(
                colors: [.black.opacity(0.10), .clear, .black.opacity(0.26)],
                startPoint: .leading,
                endPoint: .trailing
            )

            GeometryReader { geometry in
                Path { path in
                    path.move(to: CGPoint(x: max(geometry.size.width - 5, 0), y: 14))
                    path.addLine(to: CGPoint(x: max(geometry.size.width - 5, 0), y: max(14, geometry.size.height - 14)))
                }
                .stroke(
                    PassportTheme.gold.opacity(0.26),
                    style: StrokeStyle(lineWidth: 0.9, lineCap: .round, dash: [3, 4])
                )
            }
        }
        .clipShape(Rectangle())
        .allowsHitTesting(false)
    }
}

private struct PassportBindingOverlayView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(PassportPaperAsset.bindingTexture)
            .resizable()
            .scaledToFill()
            .contrast(colorScheme == .dark ? 1.03 : 1.0)
            .opacity(colorScheme == .dark ? 0.34 : 0.92)
            .blendMode(colorScheme == .dark ? .overlay : .multiply)
            .clipShape(Rectangle())
            .allowsHitTesting(false)
    }
}

private struct PassportWatermark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 5) {
            Text(verbatim: "WANDERLUST")
                .wanderlustFont(15, relativeTo: .callout, weight: .semibold, design: .serif, maxScale: 1.25)
                .tracking(5.0)
                .foregroundStyle(PassportTheme.watermarkInk(colorScheme).opacity(colorScheme == .dark ? 0.36 : 0.28))
            HStack(spacing: 10) {
                Text(verbatim: "PASSPORT")
                    .wanderlustFont(8.5, relativeTo: .caption2, weight: .medium, design: .serif, maxScale: 1.25)
                    .tracking(3.1)
                    .foregroundStyle(PassportTheme.watermarkInk(colorScheme).opacity(colorScheme == .dark ? 0.31 : 0.24))
            }
        }
        .allowsHitTesting(false)
    }
}

struct StampPlacement {
    let x: CGFloat
    let y: CGFloat
    let rotation: Double
}

enum PassportStampLayout {
    static let stampsPerPage = 6
    static let pageNumberReservedRatio: CGFloat = 0.09
    private static let rotations: [Double] = [-5, 4, 3, -4, -3, 4]
    private static let xSlots: [CGFloat] = [
        0.29,
        0.71,
        0.29,
        0.71,
        0.29,
        0.71
    ]

    static func pageCount(for stampCount: Int) -> Int {
        guard stampCount > 0 else { return 0 }
        return Int(ceil(Double(stampCount) / Double(stampsPerPage)))
    }

    static func pages<Entry>(from entries: [Entry]) -> [[Entry]] {
        stride(from: 0, to: entries.count, by: stampsPerPage).map {
            Array(entries[$0..<min($0 + stampsPerPage, entries.count)])
        }
    }

    static func stampDiameter(pageSize: CGSize, topReserved: CGFloat) -> CGFloat {
        let verticalGap: CGFloat = 24
        let pageNumberReserved = max(pageSize.height * pageNumberReservedRatio, 38)
        let topClear = topReserved + 8
        let bottomClear = pageSize.height - pageNumberReserved - 10
        let verticalSpan = max(bottomClear - topClear, 1)

        let maxFromVertical = max((2 * verticalSpan - 5 * verticalGap) / 7, 76)
        let maxFromWidth = min(pageSize.width * 0.36, pageSize.width * 0.42 - 18)
        return min(maxFromVertical, maxFromWidth)
    }

    static func placements(count: Int, pageSize: CGSize, diameter: CGFloat, topReserved: CGFloat) -> [StampPlacement] {
        guard count > 0 else { return [] }
        let clamped = min(count, stampsPerPage)
        let minX = diameter / 2 + 16
        let maxX = pageSize.width - diameter / 2 - 16
        let pageNumberReserved = max(pageSize.height * pageNumberReservedRatio, 38)
        let firstY = topReserved + 8 + diameter / 2
        let lastY = pageSize.height - pageNumberReserved - 10 - diameter / 2
        let stepY = (lastY - firstY) / CGFloat(stampsPerPage - 1)

        return xSlots.prefix(clamped).enumerated().map { index, slotX in
            StampPlacement(
                x: min(max(pageSize.width * slotX, minX), maxX),
                y: firstY + stepY * CGFloat(index),
                rotation: rotations[index % rotations.count]
            )
        }
    }
}

private struct StampInkWear: View {
    let seed: UInt64
    let opacity: Double
    var body: some View {
        Canvas { context, size in
            for i in 0..<18 {
                let x = val(UInt64(i * 2 + 1), max: size.width)
                let y = val(UInt64(i * 2 + 2), max: size.height)
                let r = 1.6 + val(UInt64(i + 51), max: 3.4)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r)), with: .color(.black.opacity(opacity)))
            }
        }
        .blendMode(.destinationOut)
        .compositingGroup()
        .allowsHitTesting(false)
    }
    private func val(_ index: UInt64, max: CGFloat) -> CGFloat {
        CGFloat(Double(PassportStampStyle.mix(seed &+ index)) / Double(UInt64.max)) * max
    }
}

// MARK: - Passport Cover View

struct PassportCoverView: View {
    let username: String?
    let entryCount: Int
    var showsShadow = true

    private enum Metrics {
        // 参考写真の本は角がきつめ。20 だとタブレットのように見えてしまう。
        static let outerRadius: CGFloat = 13
        static let outerFrameInset: CGFloat = 18
        static let innerFrameInset: CGFloat = 23
        /// 綴じ側（左端）の背表紙の幅。
        static let spineWidth: CGFloat = 16
    }

    var body: some View {
        GeometryReader { geometry in
            PassportKitCoverView(
                holderName: username ?? "",
                visitedCountryCount: entryCount,
                fixedWidth: geometry.size.width
            )
            .shadow(
                color: .black.opacity(showsShadow ? 0.13 : 0),
                radius: showsShadow ? 14 : 0,
                y: showsShadow ? 8 : 0
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WanderlustL10n.string("Passport", table: .passport))
        .accessibilityValue(PluralizationFormatter.countries(entryCount))
    }

    // MARK: - Layers

    /// ネイビーのレザー地。表紙は意匠上ダークモードでも色を変えない。
    private var coverMaterial: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.outerRadius, style: .continuous)
        return ZStack {
            shape.fill(
                LinearGradient(
                    colors: [PassportTheme.navyMid, PassportTheme.navyDeep, PassportTheme.navyEdge],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            LeatherTexture()
                .clipShape(shape)
                .opacity(0.26)

            // 革の起伏を感じさせる斜めのハイライトと落ち込み。
            LinearGradient(
                colors: [.white.opacity(0.09), .clear, .black.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(shape)

            // 綴じ側（左端）を少し暗くして厚みを出す。
            LinearGradient(
                colors: [.black.opacity(0.30), .clear],
                startPoint: .leading,
                endPoint: .center
            )
            .clipShape(shape)

            spine
                .clipShape(shape)
        }
    }

    /// 背表紙。革が一段落ち込み、内側にステッチが走る。
    private var spine: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                LinearGradient(
                    colors: [
                        .black.opacity(0.22),
                        .black.opacity(0.05),
                        .black.opacity(0.30)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: Metrics.spineWidth)

                // 折り目
                Rectangle()
                    .fill(.black.opacity(0.35))
                    .frame(width: 0.8)

                // ステッチ
                Rectangle()
                    .fill(.clear)
                    .frame(width: 0.5)
                    .overlay(
                        Rectangle()
                            .stroke(
                                PassportTheme.gold.opacity(0.20),
                                style: StrokeStyle(lineWidth: 0.9, dash: [3, 4])
                            )
                    )
                    .padding(.trailing, 4)
                    .padding(.vertical, 14)
            }
            .frame(width: Metrics.spineWidth)

            Spacer(minLength: 0)
        }
    }

    /// 金の二重罫。外枠は細く、内枠はさらに細い線を重ねて箔押しらしく見せる。
    private var goldFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PassportTheme.gold.opacity(0.62), lineWidth: 1.4)
                .padding(Metrics.outerFrameInset)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(PassportTheme.gold.opacity(0.42), lineWidth: 0.7)
                .padding(Metrics.innerFrameInset)

            // 箔押しの縁が光を拾う感じ
            RoundedRectangle(cornerRadius: Metrics.outerRadius, style: .continuous)
                .stroke(PassportTheme.gold.opacity(0.14), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    private var coverContent: some View {
        GeometryReader { geo in
            let width = geo.size.width
            // 表紙の要素は幅に対する比率で配置する。
            // 固定 pt にすると小型端末で罫線と文字がぶつかる。
            //
            // ここだけ `wanderlustFont`（Dynamic Type 追従）を使わないのは意図的。
            // 表紙は縦横比 0.70 の固定カードで、文字だけが文字サイズ設定で伸びると
            // 金の罫線を突き破る。カード自体が画面幅に追従して拡大縮小するため、
            // 文字も同じ `scale` に追従させるのが正しい挙動になる。
            let scale = width / 300

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                CompassStarShape()
                    .fill(PassportTheme.gold.opacity(0.88))
                    .frame(width: 26 * scale, height: 26 * scale)

                Spacer().frame(height: 22 * scale)

                Text(verbatim: "WANDERLUST")
                    .font(.system(size: 27 * scale, weight: .regular, design: .serif))
                    .tracking(6.0 * scale)
                    .foregroundStyle(goldFoil)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer().frame(height: 11 * scale)

                ruledLabel("PASSPORT", scale: scale)

                Spacer().frame(height: 34 * scale)

                emblem(scale: scale)

                Spacer().frame(height: 46 * scale)

                if let username {
                    Text(username.uppercased())
                        .font(.system(size: 12 * scale, weight: .semibold, design: .serif))
                        .tracking(3.2 * scale)
                        .foregroundStyle(PassportTheme.gold.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 18 * scale)
                }

                Spacer(minLength: 0)
            }
            // 背表紙のぶんだけ本文を右へ寄せ、綴じ目との間隔を確保する。
            .padding(.leading, 40 * scale)
            .padding(.trailing, 32 * scale)
            .padding(.vertical, 42 * scale)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Pieces

    /// 箔押しらしい艶。単色ではなく細い縦のグラデーションで金属感を出す。
    private var goldFoil: LinearGradient {
        LinearGradient(
            colors: [
                PassportTheme.gold.opacity(0.78),
                PassportTheme.gold,
                PassportTheme.goldDim,
                PassportTheme.gold.opacity(0.92)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func ruledLabel(_ text: String, scale: CGFloat) -> some View {
        HStack(spacing: 10 * scale) {
            Rectangle()
                .fill(PassportTheme.goldDim.opacity(0.75))
                .frame(width: 24 * scale, height: 0.8)
            Text(verbatim: text)
                .font(.system(size: 11 * scale, weight: .medium, design: .serif))
                .tracking(4.0 * scale)
                .foregroundStyle(PassportTheme.goldDim)
            Rectangle()
                .fill(PassportTheme.goldDim.opacity(0.75))
                .frame(width: 24 * scale, height: 0.8)
        }
        .fixedSize()
    }

    private func emblem(scale: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(PassportTheme.gold.opacity(0.72), lineWidth: 1.4 * scale)
                .frame(width: 112 * scale, height: 112 * scale)

            Circle()
                .stroke(PassportTheme.goldDim.opacity(0.48), lineWidth: 0.8 * scale)
                .frame(width: 88 * scale, height: 88 * scale)

            CompassStarShape()
                .fill(PassportTheme.gold.opacity(0.16))
                .frame(width: 70 * scale, height: 70 * scale)

            CompassStarShape()
                .stroke(PassportTheme.gold.opacity(0.86), lineWidth: 1.1 * scale)
                .frame(width: 70 * scale, height: 70 * scale)

            Circle()
                .fill(goldFoil)
                .frame(width: 10 * scale, height: 10 * scale)
        }
        .frame(width: 128 * scale, height: 128 * scale)
    }

    private func tagline(scale: CGFloat) -> some View {
        VStack(spacing: 13 * scale) {
            Rectangle()
                .fill(PassportTheme.goldDim.opacity(0.50))
                .frame(width: 108 * scale, height: 0.6)

            VStack(spacing: 5 * scale) {
                if let username {
                    Text(username.uppercased())
                        .font(.system(size: 12.5 * scale, weight: .semibold, design: .serif))
                        .tracking(3.0 * scale)
                        .foregroundStyle(PassportTheme.gold.opacity(0.86))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.bottom, 3 * scale)
                }

                ForEach(Self.taglineLines, id: \.self) { line in
                    Text(verbatim: line)
                        .font(.system(size: 9.5 * scale, weight: .medium, design: .serif))
                        .tracking(2.4 * scale)
                        .foregroundStyle(PassportTheme.gold.opacity(0.60))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }

            Rectangle()
                .fill(PassportTheme.goldDim.opacity(0.50))
                .frame(width: 108 * scale, height: 0.6)
        }
    }

    /// 右下の IC チップと波形。実在のパスポートの意匠を模した装飾。
    private func securityMarks(scale: CGFloat) -> some View {
        HStack(spacing: 12 * scale) {
            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 2 * scale, style: .continuous)
                .stroke(PassportTheme.gold.opacity(0.62), lineWidth: 0.9)
                .frame(width: 20 * scale, height: 14 * scale)
                .overlay(
                    Circle()
                        .stroke(PassportTheme.gold.opacity(0.62), lineWidth: 0.9)
                        .frame(width: 5.5 * scale, height: 5.5 * scale)
                )

            HStack(spacing: 4 * scale) {
                ForEach(0..<3, id: \.self) { index in
                    WaveMark()
                        .stroke(
                            PassportTheme.gold.opacity(0.44 - Double(index) * 0.08),
                            style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
                        )
                        .frame(width: 16 * scale, height: 10 * scale)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityHidden(true)
    }

    private static let taglineLines = [
        "COLLECT MOMENTS.",
        "STAMP MEMORIES.",
        "EXPLORE THE WORLD."
    ]
}

/// パスポート表紙右下の波形マーク。
private struct WaveMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY),
            control2: CGPoint(x: rect.maxX - rect.width * 0.3, y: rect.maxY)
        )
        return path
    }
}

// MARK: - Passport Reader View

struct PassportReaderView: View {
    let entries: [PassportEntry]
    let username: String?
    let onRequestCloseFromFirstPage: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    // シングルトンは View の所有物ではないので @ObservedObject を使う
    @ObservedObject private var tripStore = TripStore.shared
    @State private var currentPage = 0
    @State private var selectedTrip: Trip?
    /// ページ遷移の方向（true = 前進、false = 後退）。スライドアニメーションの向きに使う。
    @State private var navigateForward = true

    private var stampPages: [[PassportEntry]] {
        PassportStampLayout.pages(from: entries)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PassportBackground().ignoresSafeArea()

                GeometryReader { geo in
                    let size = bookSize(in: geo)
                    let visibleBookWidth = size.bookWidth

                    ZStack {
                        ZStack {
                            PassportBackground()
                                .clipShape(RoundedRectangle(cornerRadius: PassportTheme.pageCornerRadius, style: .continuous))
                            currentStampPage
                                .frame(width: size.pageWidth, height: size.pageHeight)
                                .id(currentPage)
                                .transition(.opacity)
                                .gesture(pageTurnGesture)
                        }
                        .frame(width: visibleBookWidth, height: size.pageHeight, alignment: .center)
                        .clipShape(RoundedRectangle(cornerRadius: PassportTheme.pageCornerRadius, style: .continuous))
                        .shadow(
                            color: (colorScheme == .dark
                                ? Color(red: 0.010, green: 0.008, blue: 0.006).opacity(0.34)
                                : .black.opacity(0.20)),
                            radius: 18,
                            x: 6,
                            y: 12
                        )

                        pageIndicator
                            .offset(y: size.pageHeight / 2 + 28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: entries.map(\.id).joined(separator: "|")) {
                        currentPage = 0
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .simultaneousGesture(closeFromFirstPageGesture)
            .sheet(item: $selectedTrip) { trip in
                NavigationStack {
                    TripDetailView(tripID: trip.id, tripStore: tripStore)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(String(localized: "Close")) {
                                    selectedTrip = nil
                                }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Header / Page indicator

    /// 本の上に置く見出し。左にタイトル、右に訪問国数のピル。
    private var readerHeader: some View {
        HStack(alignment: .center, spacing: WanderlustSpacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(WanderlustL10n.string("Passport", table: .passport))
                        .font(.title3.weight(.bold))
                } icon: {
                    Image(systemName: "airplane")
                        .foregroundStyle(WanderlustColor.accent)
                }
                .labelStyle(.titleAndIcon)

                Text(String(localized: "Collect a stamp for every country you visit"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            visitedCountPill
        }
        .padding(.horizontal, WanderlustSpacing.large)
        .padding(.bottom, WanderlustSpacing.small)
        .background(.bar)
    }

    private var visitedCountPill: some View {
        HStack(spacing: WanderlustSpacing.small) {
            Image(systemName: "globe")
                .font(.headline)
                .foregroundStyle(WanderlustColor.accent)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(entries.count)")
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(WanderlustColor.accent)
                    Text(verbatim: "/ \(Self.totalCountryCount)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Text(String(localized: "countries visited"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, WanderlustSpacing.medium)
        .padding(.vertical, WanderlustSpacing.small)
        .wanderlustNavigationGlass(shape: Capsule(style: .continuous), isInteractive: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "countries visited"))
        .accessibilityValue("\(entries.count) / \(Self.totalCountryCount)")
    }

    /// ページ位置のドット。ページ数が多いときは数値表示に切り替える。
    @ViewBuilder
    private var pageIndicator: some View {
        let pageCount = stampPages.count
        let dotCount = pageCount + 1
        let activeIndex = currentPage + 1
        let activeColor = Color(red: 0.0, green: 0.478, blue: 1.0)

        Group {
            if dotCount <= 10 {
                HStack(spacing: 7) {
                    ForEach(0..<dotCount, id: \.self) { index in
                        Circle()
                            .fill(
                                index == activeIndex
                                    ? AnyShapeStyle(activeColor)
                                    : AnyShapeStyle(Color.secondary.opacity(0.32))
                            )
                            .frame(width: 7, height: 7)
                    }
                }
            } else {
                Text(verbatim: "\(activeIndex + 1) / \(dotCount)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, WanderlustSpacing.small)
        .padding(.bottom, WanderlustSpacing.xSmall)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Page"))
        .accessibilityValue("\(activeIndex + 1) / \(dotCount)")
    }

    /// 世界の国数（スタンプ収集の母数）。
    private static let totalCountryCount = 195

    private var closeFromFirstPageGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard currentPage == 0 else { return }
                let isRightSwipe = value.translation.width > 55
                    && abs(value.translation.height) < 52
                    && value.predictedEndTranslation.width > 70
                if isRightSwipe {
                    onRequestCloseFromFirstPage()
                }
            }
    }

    // Compute fixed book dimensions first; images fill these bounds and never drive aspect ratio.
    /// 本の寸法。
    ///
    /// 左ページの見えている幅（sliver）と右ページ（実際にめくるページ）を
    /// 足したものが本の幅になるよう、**先に右ページの幅を決めてから**
    /// 本の幅を組み立てる。以前は逆順で計算していたため
    /// `pageWidth + sliverWidth > bookWidth` となり、綴じ目が本の外へ出ていた。
    private func bookSize(in geo: GeometryProxy) -> (bookWidth: CGFloat, pageWidth: CGFloat, pageHeight: CGFloat, sliverWidth: CGFloat) {
        let safeH = geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom
        let maxBookHeight = max(safeH - 44, 200)

        let pageAspect: CGFloat = 1.50
        // 幅で決めた場合と高さで決めた場合の小さいほうを採る。
        let widthLimitedPage = geo.size.width * 0.95
        let heightLimitedPage = maxBookHeight / pageAspect
        let pageWidth = max(min(widthLimitedPage, heightLimitedPage), 120)

        let pageHeight = pageWidth * pageAspect
        return (pageWidth, pageWidth, pageHeight, 0)
    }

    private var currentStampPage: some View {
        let safePage = min(max(currentPage, 0), stampPages.count - 1)
        return PassportStampPageContent(
            entries: stampPages[safePage],
            pageNumber: safePage + 1,
            tripStore: tripStore,
            onTripSelected: { trip in
                selectedTrip = trip
            }
        )
    }

    private var pageTurnGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > 55,
                      abs(value.translation.height) < 52 else { return }

                if horizontal < 0 {
                    let next = min(currentPage + 1, stampPages.count - 1)
                    guard next != currentPage else { return }
                    navigateForward = true
                    withAnimation(.easeInOut(duration: 0.30)) { currentPage = next }
                } else if currentPage == 0 {
                    onRequestCloseFromFirstPage()
                } else {
                    let prev = max(currentPage - 1, 0)
                    navigateForward = false
                    withAnimation(.easeInOut(duration: 0.30)) { currentPage = prev }
                }
            }
    }

}

// MARK: - Stamp Page Content (fills VC bounds, no aspect ratio)

private struct PassportStampPageContent: View {
    let entries: [PassportEntry]
    let pageNumber: Int
    @ObservedObject var tripStore: TripStore
    var onTripSelected: ((Trip) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let contentHeight = geometry.size.height
            let radius = min(PassportTheme.pageCornerRadius, min(geometry.size.width, geometry.size.height) * 0.12)
            let pageShape = RoundedRectangle(cornerRadius: radius, style: .continuous)

            ZStack(alignment: .top) {
                ZStack {
                    paperBackground

                    if entries.isEmpty {
                        emptyState
                    } else {
                        stampGrid
                    }

                    pageNumberOverlay
                }
                .frame(width: geometry.size.width, height: contentHeight)
                .clipShape(pageShape)
                .contentShape(pageShape)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var stampDesigns: [StampDesign] {
        entries.map(stampDesign(for:))
    }

    private func stampDesign(for entry: PassportEntry) -> StampDesign {
        StampDesign.design(forCountryCode: entry.countryCode, title: entry.countryName)
    }

    private var paperBackground: some View {
        ZStack {
            PassportPaperSurface()
            PassportWatermark()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 16)
                .zIndex(20)
        }
    }

    private var pageNumberOverlay: some View {
        GeometryReader { geometry in
            Text(String(format: "%02d", pageNumber))
                .wanderlustFont(15, relativeTo: .body, weight: .regular, design: .serif, monospacedDigit: true)
                .foregroundStyle(PassportTheme.pageNumberInk(colorScheme).opacity(colorScheme == .dark ? 0.86 : 0.78))
                .position(
                    x: geometry.size.width * 0.93,
                    y: geometry.size.height * 0.972
                )
                .zIndex(200)
        }
        .allowsHitTesting(false)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "stamp").wanderlustDecorativeFont(40).foregroundStyle(PassportTheme.gold.opacity(0.72))
            Text(WanderlustL10n.string("No passport stamps yet", table: .passport))
                .font(.title3.weight(.semibold)).foregroundStyle(PassportTheme.primaryText(colorScheme))
        }
        .padding(30)
    }

    private var stampGrid: some View {
        GeometryReader { proxy in
            let topReserved = proxy.size.height * 0.12
            let diameter = PassportStampLayout.stampDiameter(
                pageSize: proxy.size,
                topReserved: topReserved
            )
            let placements = PassportStampLayout.placements(
                count: entries.count,
                pageSize: proxy.size,
                diameter: diameter,
                topReserved: topReserved
            )
            ZStack {
                ForEach(Array(entries.prefix(placements.count).enumerated()), id: \.element.id) { idx, entry in
                    let placement = placements[idx]
                    stampItem(
                        entry: entry,
                        index: idx,
                        size: CGSize(width: diameter, height: diameter),
                        rotation: placement.rotation
                    )
                    .position(x: placement.x, y: placement.y)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func stampItem(entry: PassportEntry, index: Int, size: CGSize, rotation: Double) -> some View {
        let stamp = PassportStampView(
            entry: entry,
            stampSize: size,
            rotation: rotation
        )
        if let trip = entry.trips.first, let onTripSelected {
            Button { onTripSelected(trip) } label: { stamp }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
        } else {
            stamp
        }
    }
}

// MARK: - Stamp Views

struct PassportStampView: View {
    let entry: PassportEntry
    var stampSize = CGSize(width: 138, height: 138)
    var rotation: Double?

    var body: some View {
        PassportStampCard(
            entry: entry,
            stampSize: stampSize,
            rotation: rotation
        )
    }
}

private enum PassportStampTypography {
    static let countrySize: CGFloat = 15
    static let dateSize: CGFloat = 11.5
    static let entrySize: CGFloat = 10.5
    static let flagHeight: CGFloat = 17
}

private struct PassportStampCard: View {
    let entry: PassportEntry
    var stampSize = CGSize(width: 138, height: 138)
    var rotation: Double?
    @Environment(\.colorScheme) private var colorScheme

    private var style: PassportStampStyle { PassportStampStyle(entry: entry) }
    private var displayRotation: Double { rotation ?? style.rotation }
    private var inkOpacity: Double { max(style.inkOpacity, colorScheme == .dark ? 1.0 : 0.80) }
    private var stampOpacity: Double { colorScheme == .dark ? 1.0 : 0.92 }
    private var wearOpacity: Double {
        colorScheme == .dark ? min(style.wearOpacity * 0.45, 0.07) : min(style.wearOpacity, 0.14)
    }
    private var stampBlendMode: BlendMode {
        .normal
    }

    private var stampColor: Color {
        let code = entry.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch code {
        case "JP":         return stampInk(light: (0.64, 0.08, 0.12), dark: (0.92, 0.18, 0.26))
        case "GB", "UK":   return stampInk(light: (0.10, 0.18, 0.42), dark: (0.34, 0.49, 0.92))
        case "TR":         return stampInk(light: (0.58, 0.20, 0.14), dark: (0.88, 0.31, 0.23))
        case "FR":         return stampInk(light: (0.14, 0.30, 0.62), dark: (0.32, 0.52, 0.96))
        case "IT":         return stampInk(light: (0.12, 0.36, 0.22), dark: (0.28, 0.66, 0.42))
        case "DE":         return stampInk(light: (0.34, 0.20, 0.48), dark: (0.64, 0.40, 0.88))
        case "TH":         return stampInk(light: (0.14, 0.40, 0.36), dark: (0.30, 0.72, 0.64))
        case "ES":         return stampInk(light: (0.62, 0.22, 0.10), dark: (0.90, 0.38, 0.20))
        case "US":         return stampInk(light: (0.16, 0.22, 0.50), dark: (0.38, 0.48, 0.90))
        case "CN":         return stampInk(light: (0.60, 0.10, 0.10), dark: (0.90, 0.20, 0.20))
        case "AU":         return stampInk(light: (0.10, 0.30, 0.44), dark: (0.30, 0.58, 0.74))
        case "KR":         return stampInk(light: (0.12, 0.28, 0.58), dark: (0.34, 0.52, 0.94))
        case "IN":         return stampInk(light: (0.72, 0.36, 0.10), dark: (0.96, 0.54, 0.20))
        default:
            let hue = Double(PassportStampStyle.mix(style.designSeed &+ 41) % 360) / 360
            return Color(hue: hue, saturation: colorScheme == .dark ? 0.62 : 0.48, brightness: colorScheme == .dark ? 0.82 : 0.52)
        }
    }

    private func stampInk(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        let rgb = colorScheme == .dark ? dark : light
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private var englishCountryName: String {
        Locale(identifier: "en_US").localizedString(forRegionCode: entry.countryCode)?
            .uppercased() ?? entry.countryName.uppercased()
    }

    private var englishDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd MMM yyyy"
        return f.string(from: entry.firstVisit).uppercased()
    }

    var body: some View {
        ZStack {
            stampShapeLayer
            stampContents
        }
        .frame(width: stampSize.width, height: stampSize.height)
        .rotationEffect(.degrees(displayRotation))
        .opacity(stampOpacity)
        .blendMode(stampBlendMode)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stampShapeLayer: some View {
        let fill = stampColor.opacity(0.010)
        let bleed = stampColor.opacity(max(style.bleedOpacity, 0.10) * 1.4)
        Circle().fill(fill)
            .overlay {
                Circle().stroke(stampColor.opacity(inkOpacity), lineWidth: 2.2)
                Circle().stroke(stampColor.opacity(inkOpacity * 0.62), lineWidth: 1).padding(5)
                Circle().stroke(stampColor.opacity(inkOpacity * 0.36), style: StrokeStyle(lineWidth: 0.9, dash: [5, 4])).padding(17)
            }
            .overlay { Circle().stroke(bleed, lineWidth: 5).blur(radius: 1.4).padding(3).scaleEffect(1.04) }
            .overlay { StampInkWear(seed: style.seed, opacity: wearOpacity).clipShape(Circle()) }
    }

    /// 国ごとのランドマーク線画。
    /// 国旗絵文字だと OS のカラー絵文字がスタンプのインク表現から浮くため、
    /// 単色の線画に置き換えている（参考写真の実物スタンプに近づける）。
    private var emblemArchetype: PassportEmblemArchetype {
        PassportEmblemArchetype.archetype(
            forCountryCode: entry.countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    @ViewBuilder
    private var stampContents: some View {
        let baseWidth = max(stampSize.width, 80)
        let scale = baseWidth / 138
        let titleFontSize = max(10, min(baseWidth * 0.116, 18))
        let dateFontSize = max(8, min(baseWidth * 0.083, 14))
        let entryFontSize = max(7.5, min(baseWidth * 0.076, 13))
        let titleTracking = englishCountryName.count > 10 ? max(0.2, 0.55 * scale) : 0.8 * scale
        VStack(spacing: 3) {
            Text(entry.flagEmoji)
                .font(.system(size: PassportStampTypography.flagHeight * scale))
                .frame(
                    width: PassportStampTypography.flagHeight * scale * 1.6,
                    height: PassportStampTypography.flagHeight * scale
                )
                .layoutPriority(1)

            Text(englishCountryName)
                .font(.system(
                    size: titleFontSize,
                    weight: .semibold,
                    design: .serif
                ))
                .tracking(titleTracking)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)
                .multilineTextAlignment(.center)
                .frame(
                    width: max(stampSize.width - 22, 64),
                    height: titleFontSize * 2.55,
                    alignment: .center
                )
                .layoutPriority(2)

            Text(englishDate)
                .font(.system(
                    size: dateFontSize,
                    weight: .semibold,
                    design: .serif
                ))
                .tracking(0.45 * scale)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .allowsTightening(true)
                .frame(width: max(stampSize.width - 22, 64))

            Text(verbatim: "ENTRY")
                .font(.system(
                    size: entryFontSize,
                    weight: .semibold,
                    design: .serif
                ))
                .tracking(1.8 * scale)
                .opacity(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .foregroundStyle(stampColor.opacity(inkOpacity))
    }

}

// MARK: - Passport Page View (standalone, used in previews / outside curl)

struct PassportPageView: View {
    let entries: [PassportEntry]
    let pageNumber: Int
    @ObservedObject var tripStore: TripStore
    var onTripSelected: ((Trip) -> Void)?

    var body: some View {
        PassportStampPageContent(
            entries: entries,
            pageNumber: pageNumber,
            tripStore: tripStore,
            onTripSelected: onTripSelected
        )
        .aspectRatio(0.70, contentMode: .fit)
    }
}

// MARK: - Main Passport View

/// スタンプ再集計の要否を判定するための軽量な指紋。
/// 旅行の件数・都市数・最終更新時刻が変わったときだけ再計算する。
private struct PassportEntriesFingerprint: Hashable {
    let tripCount: Int
    let cityCount: Int
    let latestUpdate: TimeInterval

    init(trips: [Trip]) {
        tripCount = trips.count
        cityCount = trips.reduce(0) { $0 + $1.cities.count }
        latestUpdate = trips
            .map(\.updatedAt.timeIntervalSinceReferenceDate)
            .max() ?? 0
    }
}


private enum PassportDisplayState {
    case closed
    case opening
    case open
    case closing
}

struct PassportView: View {
    @ObservedObject var tripStore: TripStore
    var resetToCoverToken = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Passport タブに入ったら最初に表紙を見せ、左スワイプでスタンプページへ移る。
    @State private var displayState: PassportDisplayState = .closed
    @State private var coverRotation: Double = 0
    @State private var coverLift: CGFloat = 0
    /// 集計済みスタンプ。`makeEntries()` の結果をキャッシュする。
    @State private var entries: [PassportEntry] = []
    /// 表紙アニメーションの完了待ちタスク。View 消滅時にキャンセルする。
    @State private var coverTransitionTask: Task<Void, Never>?
    @GestureState private var coverDragOffset: CGFloat = 0
    @AppStorage("atlas.username") private var username = ""

    private var passportDisplayName: String? {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholders = ["ユーザー","ユーザ","user","ゲスト","未設定","name","user name"]
        guard !clean.isEmpty, !placeholders.contains(clean.lowercased()) else { return nil }
        return clean
    }

    var body: some View {
        Group {
            if !tripStore.isLoaded && !tripStore.trips.isEmpty {
                WanderlustLoadingView()
            } else {
                passportContent(entries: entries)
            }
        }
        .background(background(isEmpty: entries.isEmpty))
        .navigationTitle(WanderlustL10n.string("Passport", table: .passport))
        .toolbar(.hidden, for: .navigationBar)
        // スタンプ集計は旅行数 × 都市数のコストがかかるため body から切り離し、
        // 旅行データが実際に変化したときだけ再計算する。
        // （以前は computed property を body 評価のたびに実行していた）
        .task(id: PassportEntriesFingerprint(trips: tripStore.trips)) {
            let rebuilt = makeEntries()
            guard !Task.isCancelled else { return }
            entries = rebuilt
        }
#if DEBUG
        .onAppear { validatePassportAssets() }
#endif
        // 表紙へ戻すのは「Passport タブへ入り直したとき」だけ。
        // ContentView が .id() で View を作り直すため displayState は初期値 .closed に戻る。
        // ここで onAppear からリセットすると、旅行詳細シートを閉じただけでも
        // 表紙に戻ってしまうため行わない。
        .onDisappear { cancelCoverTransition() }
        .onChange(of: resetToCoverToken) { _, _ in
            guard displayState != .closed else { return }
            resetToCover()
        }
    }

    private var isTransitioning: Bool {
        displayState == .opening || displayState == .closing
    }

    private var showsReader: Bool {
        displayState == .open || displayState == .opening || displayState == .closing
    }

    private var showsCover: Bool {
        displayState == .closed || displayState == .opening || displayState == .closing
    }

    private func passportContent(entries: [PassportEntry]) -> some View {
        ZStack {
            if showsReader {
                PassportReaderView(
                    entries: entries,
                    username: passportDisplayName,
                    onRequestCloseFromFirstPage: closePassport
                )
                .transition(.opacity)
            }

            if showsCover {
                coverScreen(entries: entries)
                    .zIndex(2)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: displayState)
    }

    private func coverScreen(entries: [PassportEntry]) -> some View {
        GeometryReader { geometry in
            let safeH = geometry.size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom
            let maxCoverHeight = max(safeH - 44, 200)
            let coverWidth = max(min(geometry.size.width * 0.95, maxCoverHeight / 1.5), 120)
            let dotCount = PassportStampLayout.pageCount(for: entries.count) + 1

            ZStack {
                PassportCoverView(username: passportDisplayName, entryCount: entries.count)
                    .frame(width: coverWidth, height: coverWidth * 1.5)
                    .frame(maxWidth: .infinity)
                    .offset(y: coverLift)
                    .shadow(
                        color: (colorScheme == .dark
                            ? Color(red: 0.010, green: 0.008, blue: 0.006).opacity(0.30)
                            : .black.opacity(0.13)),
                        radius: 14,
                        x: 6,
                        y: 8
                    )
                    .gesture(entries.isEmpty ? nil : coverTurnGesture(containerWidth: geometry.size.width))

                if !entries.isEmpty {
                    coverPageIndicator(dotCount: dotCount)
                        .offset(y: coverWidth * 0.75 + 28)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(WanderlustL10n.string("Open Passport", table: .passport))
    }

    private func coverPageIndicator(dotCount: Int) -> some View {
        let activeColor = Color(red: 0.0, green: 0.478, blue: 1.0)

        return HStack(spacing: 7) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(index == 0 ? AnyShapeStyle(activeColor) : AnyShapeStyle(Color.secondary.opacity(0.32)))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.top, WanderlustSpacing.small)
        .padding(.bottom, WanderlustSpacing.xSmall)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Page"))
        .accessibilityValue("1 / \(dotCount)")
    }

    private func coverTurnGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($coverDragOffset) { value, state, _ in
                guard displayState == .closed else { return }
                state = min(value.translation.width, 0)
            }
            .onEnded { value in
                guard displayState == .closed else { return }
                let projectedTurn = min(value.translation.width, value.predictedEndTranslation.width)
                if projectedTurn < -containerWidth * 0.28 {
                    openPassport()
                }
            }
    }

    private func openPassport() {
        guard displayState == .closed, !isTransitioning, !entries.isEmpty else { return }
        coverTransitionTask?.cancel()
        coverRotation = 0
        coverLift = 0

        if reduceMotion {
            displayState = .open
        } else {
            withAnimation(.easeInOut(duration: 0.30)) {
                displayState = .open
            }
        }
    }

    private func cancelCoverTransition() {
        coverTransitionTask?.cancel()
        coverTransitionTask = nil
    }

    private func closePassport() {
        guard displayState == .open, !isTransitioning else { return }
        coverTransitionTask?.cancel()

        if reduceMotion {
            resetToCover()
        } else {
            withAnimation(.easeInOut(duration: 0.30)) {
                resetToCover()
            }
        }
    }

    private func resetToCover() {
        displayState = .closed
        coverRotation = 0
        coverLift = 0
    }

    @ViewBuilder
    private func background(isEmpty: Bool) -> some View {
        PassportBackground().ignoresSafeArea()
    }

    /// スタンプ一覧を組み立てる。
    ///
    /// 国の同定は `VisitedCountryAggregator` に委譲する。
    /// 以前はここに独自の重複排除ロジックがあり、内側ループで
    /// `trip.cities.filter` と `GeoJSONLoader` 参照を繰り返していたため
    /// 旅行数が増えると二乗で重くなり、かつ他画面と国数が食い違っていた。
    private func makeEntries() -> [PassportEntry] {
        let visited = VisitedCountryAggregator.visitedCountries(in: tripStore.trips)
        let tripsByID = Dictionary(
            tripStore.trips.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return visited.map { country in
            let trips = country.tripIDs
                .compactMap { tripsByID[$0] }
                .sorted { $0.startDate < $1.startDate }

            return PassportEntry(
                id: country.id,
                countryName: country.displayName,
                countryCode: country.isoCode,
                flagEmoji: country.flagEmoji,
                continent: country.continent,
                firstVisit: country.firstVisit,
                lastVisit: country.lastVisit,
                tripCount: trips.count,
                cityNames: country.cityNames,
                trips: trips
            )
        }
    }
}

// MARK: - Country Detail Sheet

struct PassportCountryDetail: View {
    let entry: PassportEntry
    @Environment(\.dismiss) private var dismiss
    // シングルトンは View の所有物ではないので @ObservedObject を使う
    @ObservedObject private var tripStore = TripStore.shared

    var body: some View {
        NavigationStack {
            List {
                headerSection; dateSection
                if !entry.cityNames.isEmpty { citiesSection }
                if !entry.trips.isEmpty { tripsSection }
            }
            .navigationTitle(entry.countryName)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 16) {
                Text(entry.flagEmoji).wanderlustDecorativeFont(52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.countryName).font(.title2.bold())
                    if !entry.continent.isEmpty {
                        Text(WanderlustL10n.continentName(entry.continent)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        WanderlustInlineCount(systemImage: "building.2", text: PluralizationFormatter.compactCities(entry.cityNames.count))
                        WanderlustInlineCount(systemImage: "suitcase.fill", text: PluralizationFormatter.compactTrips(entry.tripCount))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var dateSection: some View {
        Section(WanderlustL10n.string("Visit History", table: .trips)) {
            LabeledContent(WanderlustL10n.string("First Visit", table: .trips), value: WanderlustDateFormatter.date(entry.firstVisit))
            if entry.tripCount > 1 {
                LabeledContent(WanderlustL10n.string("Last Visit", table: .trips), value: WanderlustDateFormatter.date(entry.lastVisit))
            }
        }
    }

    private var citiesSection: some View {
        Section(WanderlustL10n.string("Cities", table: .trips)) {
            ForEach(entry.cityNames, id: \.self) { Text($0) }
        }
    }

    private var tripsSection: some View {
        Section(WanderlustL10n.string("Trips", table: .trips)) {
            ForEach(entry.trips) { trip in
                NavigationLink {
                    TripDetailView(tripID: trip.id, tripStore: tripStore)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trip.displayTitle).font(.headline)
                        Text(trip.dateRangeText).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
