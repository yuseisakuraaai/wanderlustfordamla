import SwiftUI
import UIKit

// MARK: - Passport kit tokens

enum PassportKitTheme {
    static let coverTop = Color(red: 0.09, green: 0.14, blue: 0.24)
    static let coverBottom = Color(red: 0.05, green: 0.08, blue: 0.15)
    static let coverNavy = Color(red: 0.07, green: 0.11, blue: 0.20)
    static let paperBase = Color(red: 0.93, green: 0.90, blue: 0.83)
    static let paperShade = Color(red: 0.86, green: 0.82, blue: 0.72)
    static let paperInk = Color(red: 0.45, green: 0.40, blue: 0.32)
    static let paperDarkBase = Color(red: 0.212, green: 0.188, blue: 0.165)
    static let paperDarkInk = Color(red: 0.700, green: 0.620, blue: 0.500)

    static let goldGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 0.80, green: 0.63, blue: 0.30), location: 0.00),
            .init(color: Color(red: 0.95, green: 0.84, blue: 0.53), location: 0.30),
            .init(color: Color(red: 1.00, green: 0.95, blue: 0.78), location: 0.50),
            .init(color: Color(red: 0.93, green: 0.80, blue: 0.47), location: 0.70),
            .init(color: Color(red: 0.82, green: 0.65, blue: 0.33), location: 1.00)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

enum StampShapeKind: String, Codable {
    case rect
    case circle
    case octagon
    case ticket
}

struct StampDesign: Identifiable, Hashable {
    let id: String
    let title: String
    let ink: Color
    let shape: StampShapeKind
    let artwork: String
    let symbolFallback: String

    static let initialData: [StampDesign] = [
        .init(id: "GB", title: "UNITED KINGDOM", ink: Color(red: 0.16, green: 0.30, blue: 0.55), shape: .rect, artwork: "stamp.gb", symbolFallback: "building.columns"),
        .init(id: "JP", title: "JAPAN", ink: Color(red: 0.78, green: 0.19, blue: 0.19), shape: .circle, artwork: "stamp.jp", symbolFallback: "mountain.2"),
        .init(id: "TR", title: "TÜRKIYE", ink: Color(red: 0.60, green: 0.16, blue: 0.16), shape: .octagon, artwork: "stamp.tr", symbolFallback: "moon.stars"),
        .init(id: "FR", title: "FRANCE", ink: Color(red: 0.42, green: 0.29, blue: 0.60), shape: .rect, artwork: "stamp.fr", symbolFallback: "tower.broadcast"),
        .init(id: "IT", title: "ITALY", ink: Color(red: 0.15, green: 0.42, blue: 0.28), shape: .circle, artwork: "stamp.it", symbolFallback: "theatermasks"),
        .init(id: "DE", title: "GERMANY", ink: Color(red: 0.20, green: 0.32, blue: 0.50), shape: .rect, artwork: "stamp.de", symbolFallback: "building.columns.fill"),
        .init(id: "TH", title: "THAILAND", ink: Color(red: 0.78, green: 0.48, blue: 0.13), shape: .ticket, artwork: "stamp.th", symbolFallback: "building.2")
    ]
    static let library = initialData

    static func design(forCountryCode code: String, title fallbackTitle: String) -> StampDesign {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let design = initialData.first(where: { $0.id == normalized }) {
            return design
        }

        let seed = Double(abs(normalized.hashValue % 1000)) / 1000.0
        let shapes: [StampShapeKind] = [.rect, .circle, .octagon, .ticket]
        let shape = shapes[min(Int(seed * Double(shapes.count)), shapes.count - 1)]
        let hue = seed
        return StampDesign(
            id: normalized.isEmpty ? fallbackTitle.uppercased() : normalized,
            title: fallbackTitle.uppercased(),
            ink: Color(hue: hue, saturation: 0.48, brightness: 0.48),
            shape: shape,
            artwork: "stamp.\(normalized.lowercased())",
            symbolFallback: "building.columns"
        )
    }
}

// MARK: - Cover

struct PassportKitCoverView: View {
    let holderName: String
    var visitedCountryCount: Int = 0
    var fixedWidth: CGFloat = 360

    private var visitedCountryText: String {
        switch visitedCountryCount {
        case 1:
            return "1 COUNTRY VISITED"
        default:
            return "\(visitedCountryCount) COUNTRIES VISITED"
        }
    }

    var body: some View {
        let w = fixedWidth
        let h = fixedWidth * 1.5
        let shape = RoundedRectangle(cornerRadius: w * 0.0733, style: .continuous)

        ZStack {
            coverLeatherSurface(w: w, h: h)

            LinearGradient(
                colors: [
                    .white.opacity(0.045),
                    .clear,
                    .white.opacity(0.015)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)

            foilFrames(w: w)

            coverContent(w: w, h: h)
        }
        .frame(width: w, height: h)
        .clipShape(shape)
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 12)
        .shadow(color: .black.opacity(0.10), radius: 3, y: 1.5)
    }

    @ViewBuilder
    private func coverLeatherSurface(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            PassportKitTheme.coverNavy

            Image("PassportLeatherGrain")
                .resizable()
                .scaledToFill()
                .saturation(0)
                .brightness(-0.12)
                .contrast(1.05)
                .blendMode(.overlay)
                .opacity(0.30)
                .allowsHitTesting(false)
        }
        .frame(width: w, height: h)
        .clipped()
        .drawingGroup()
    }

    private func foilFrames(w: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: w * 0.055, style: .continuous)
                .strokeBorder(PassportKitTheme.goldGradient, lineWidth: w * 0.0053)
                .padding(w * 0.0525)
                .shadow(color: .black.opacity(0.22), radius: 1, x: 0, y: 1)

            RoundedRectangle(cornerRadius: w * 0.045, style: .continuous)
                .strokeBorder(PassportKitTheme.goldGradient, lineWidth: w * 0.0027)
                .opacity(0.75)
                .padding(w * 0.075)
                .shadow(color: .black.opacity(0.22), radius: 1, x: 0, y: 1)
        }
    }

    private func coverContent(w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: h * 0.11)

            CompassRose(points: 8, innerRatio: 0.38)
                .fill(PassportKitTheme.goldGradient)
                .frame(width: w * 0.11, height: w * 0.11)
                .shadow(color: .black.opacity(0.22), radius: 1, x: 0, y: 1)

            Spacer().frame(height: h * 0.035)

            foilText("WANDERLUST", size: w * 0.072, weight: .regular, tracking: w * 0.015)

            Spacer().frame(height: h * 0.016)

            HStack(spacing: w * 0.028) {
                foilText("PASSPORT", size: w * 0.036, weight: .medium, tracking: w * 0.016)
            }

            Spacer(minLength: h * 0.03)

            GlobeEmblem(size: w * 0.52)
                .frame(width: w * 0.52, height: w * 0.52)

            Spacer()
                .frame(maxHeight: h * 0.07)

            VStack(spacing: w * 0.050) {
                foilText(holderName.uppercased(), size: w * 0.048, weight: .semibold, tracking: w * 0.014)
                    .opacity(holderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)

                foilText(visitedCountryText, size: w * 0.028, weight: .medium, tracking: w * 0.008)
                    .opacity(0.78)
            }
        }
        .padding(.horizontal, w * 0.11)
        .padding(.bottom, h * 0.16)
        .compositingGroup()
    }

    private func foilText(_ text: String, size: CGFloat, weight: Font.Weight, tracking: CGFloat) -> some View {
        Text(verbatim: text)
            .font(.system(size: size, weight: weight, design: .serif))
            .tracking(tracking)
            .lineLimit(1)
            .minimumScaleFactor(0.56)
            .foregroundStyle(PassportKitTheme.goldGradient)
            .shadow(color: .black.opacity(0.45), radius: 0.6, x: 0, y: 1.0)
            .compositingGroup()
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Page

struct PassportKitPageView: View {
    let stamps: [StampDesign]
    let pageNumber: Int
    var fixedWidth: CGFloat?
    var onStampTapped: ((StampDesign) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    private let slots: [CGPoint] = [
        CGPoint(x: 0.31, y: 0.22), CGPoint(x: 0.70, y: 0.33),
        CGPoint(x: 0.29, y: 0.45), CGPoint(x: 0.71, y: 0.56),
        CGPoint(x: 0.32, y: 0.68), CGPoint(x: 0.72, y: 0.79),
        CGPoint(x: 0.30, y: 0.90)
    ]

    var body: some View {
        let width = fixedWidth ?? 360
        pageContent(w: width, h: width * 1.5)
            .frame(width: width, height: width * 1.5)
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .shadow(color: .black.opacity(0.22), radius: 18, y: 12)
    }

    private func pageContent(w: CGFloat, h: CGFloat) -> some View {
        let pageShape = RoundedRectangle(cornerRadius: w * 0.0467, style: .continuous)
        return ZStack {
                pageBackground(w: w, h: h)

                CompassRose(points: 16, innerRatio: 0.45)
                    .stroke(pageInk.opacity(colorScheme == .dark ? 0.09 : 0.05), lineWidth: max(w * 0.0033, 1))
                    .frame(width: w * 0.26, height: w * 0.26)
                    .offset(x: w * 0.30, y: -h * 0.32)
                    .allowsHitTesting(false)
                    .zIndex(10)

                VStack(spacing: w * 0.010) {
                    HStack(spacing: w * 0.018) {
                        Image(systemName: "globe")
                            .font(.system(size: w * 0.055, weight: .regular, design: .serif))
                        Text(verbatim: "WANDERLUST")
                            .font(.system(size: w * 0.048, weight: .semibold, design: .serif))
                            .tracking(w * 0.012)
                    }
                    Text(verbatim: "— PASSPORT —")
                        .font(.system(size: w * 0.028, weight: .regular, design: .serif))
                }
                .foregroundStyle(pageInk.opacity(colorScheme == .dark ? 0.52 : 0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, h * 0.045)
                .zIndex(20)

                slotStamp(index: 0, w: w, h: h)
                slotStamp(index: 1, w: w, h: h)
                slotStamp(index: 2, w: w, h: h)
                slotStamp(index: 3, w: w, h: h)
                slotStamp(index: 4, w: w, h: h)
                slotStamp(index: 5, w: w, h: h)
                slotStamp(index: 6, w: w, h: h)

                Text(String(format: "%02d", pageNumber))
                    .font(.system(size: w * 0.055, weight: .regular, design: .serif))
                    .foregroundStyle(pageInk.opacity(colorScheme == .dark ? 0.78 : 0.5))
                    .padding(w * 0.08)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .clipShape(pageShape)
    }

    @ViewBuilder
    private func pageBackground(w: CGFloat, h: CGFloat) -> some View {
        let textureName = colorScheme == .dark ? "PassportPaperTextureDark" : "PassportPaperTexture"
        if let image = UIImage(named: textureName) {
            ZStack {
                colorScheme == .dark ? PassportKitTheme.paperDarkBase : PassportKitTheme.paperBase
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()
                    .blendMode(colorScheme == .dark ? .normal : .multiply)
                    .opacity(colorScheme == .dark ? 1 : 0.92)
            }
            .colorEffect(ShaderLibrary.fineGrain(.float(0.035)))
            .drawingGroup()
        } else {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [PassportKitTheme.paperDarkBase, Color(red: 0.165, green: 0.145, blue: 0.128)]
                    : [PassportKitTheme.paperBase, PassportKitTheme.paperShade],
                startPoint: .top,
                endPoint: .bottom
            )
            .colorEffect(ShaderLibrary.fineGrain(.float(0.055)))
            .drawingGroup()
        }
    }

    private var pageInk: Color {
        colorScheme == .dark ? PassportKitTheme.paperDarkInk : PassportKitTheme.paperInk
    }

    @ViewBuilder
    private func slotStamp(index: Int, w: CGFloat, h: CGFloat) -> some View {
        if stamps.indices.contains(index), slots.indices.contains(index) {
            let stamp = stamps[index]
            let slot = slots[index]
            let size = w * 0.32
            let x = min(max(w * slot.x, size * 0.52), w - size * 0.52)
            let y = min(max(h * slot.y, size * 0.52), h - size * 0.52)
            stampView(stamp, size: size)
                .frame(width: size, height: size)
                .position(x: x, y: y)
                .zIndex(30)
        }
    }

    @ViewBuilder
    private func stampView(_ stamp: StampDesign, size: CGFloat) -> some View {
        if let onStampTapped {
            Button { onStampTapped(stamp) } label: {
                StampView(design: stamp, stampSize: size)
            }
            .buttonStyle(.plain)
        } else {
            StampView(design: stamp, stampSize: size)
        }
    }
}

// MARK: - Stamp

struct StampView: View {
    let design: StampDesign
    var stampSize: CGFloat = 180
    @Environment(\.colorScheme) private var colorScheme

    private var seed: Double {
        Double(abs(design.id.hashValue % 1000)) / 1000.0
    }

    private var rotation: Double { -7 + seed * 14 }
    var body: some View {
        let s = stampSize
        ZStack {
            StampBorderShape(kind: design.shape, insetAmount: s * 0.075)
                .stroke(lineWidth: s * 0.030)
            StampBorderShape(kind: design.shape, insetAmount: s * 0.130)
                .stroke(lineWidth: s * 0.010)

            artwork(s: s)
                .position(x: s * 0.50, y: design.shape == .circle ? s * 0.60 : s * 0.42)

            stampTitle(s: s)
                .frame(width: s * 0.76)
                .position(x: s * 0.50, y: design.shape == .circle ? s * 0.27 : s * 0.72)
        }
        .foregroundStyle(adaptiveInk)
        .opacity(colorScheme == .dark ? 1.0 : 0.92)
        .rotationEffect(.degrees(rotation))
        .drawingGroup()
        .frame(width: s, height: s)
    }

    private var adaptiveInk: Color {
        guard colorScheme == .dark else {
            return design.ink
        }

        let uiColor = UIColor(design.ink)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return design.ink
        }

        return Color(
            hue: Double(hue),
            saturation: Double(min(max(saturation * 0.82, 0.34), 0.72)),
            brightness: Double(max(brightness, 0.78)),
            opacity: Double(alpha)
        )
    }

    private func stampTitle(s: CGFloat) -> some View {
        Text(verbatim: design.title)
            .font(.system(size: s * 0.115, weight: .semibold, design: .serif))
            .tracking(s * 0.012)
            .lineLimit(2)
            .minimumScaleFactor(0.50)
            .multilineTextAlignment(.center)
    }

    private func artwork(s: CGFloat) -> some View {
        stampArtwork
            .frame(width: s * 0.46, height: s * 0.46)
    }

    @ViewBuilder
    private var stampArtwork: some View {
        switch resolvedArtwork {
        case .asset(let image):
            Image(uiImage: image.withRenderingMode(.alwaysTemplate))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        case .symbol(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.monochrome)
                .fontWeight(.medium)
        }
    }

    private var resolvedArtwork: StampArtworkSource {
        if let image = UIImage(named: design.artwork) {
            return .asset(image)
        }
        if UIImage(systemName: design.symbolFallback) != nil {
            return .symbol(design.symbolFallback)
        }
#if DEBUG
        print("Missing stamp artwork and symbol fallback for \(design.id): \(design.artwork), \(design.symbolFallback)")
#endif
        return .symbol("mappin.and.ellipse")
    }
}

// MARK: - Shapes and ornaments

private enum StampArtworkSource {
    case asset(UIImage)
    case symbol(String)
}

private struct StampBorderShape: Shape {
    let kind: StampShapeKind
    let insetAmount: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        switch kind {
        case .rect:
            return Rectangle().path(in: r)
        case .circle:
            return Circle().path(in: r)
        case .octagon:
            return cutCornerPath(in: r, ratio: 0.26)
        case .ticket:
            return cutCornerPath(in: r, ratio: 0.12)
        }
    }

    private func cutCornerPath(in rect: CGRect, ratio: CGFloat) -> Path {
        let cut = min(rect.width, rect.height) * ratio
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }
}

private struct CompassRose: Shape {
    let points: Int
    let innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) * 0.5
        let inner = outer * innerRatio
        var path = Path()
        let total = max(points * 2, 4)
        for index in 0..<total {
            let angle = (Double(index) / Double(total)) * .pi * 2 - .pi / 2
            let radius: CGFloat
            if index.isMultiple(of: 2) {
                radius = (index / 2).isMultiple(of: 2) ? outer : outer * 0.75
            } else {
                radius = inner
            }
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct GlobeEmblem: View {
    let size: CGFloat

    var body: some View {
        let s = size
        Image(systemName: "globe.europe.africa.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(PassportKitTheme.goldGradient)
            .frame(width: s * 0.58, height: s * 0.58)
            .frame(width: s, height: s)
        .frame(width: s, height: s)
        .shadow(color: .black.opacity(0.65), radius: s * 0.006, y: s * 0.008)
        .shadow(color: .white.opacity(0.10), radius: s * 0.004, y: -s * 0.006)
    }
}

private struct DashedBindingThread: View {
    let color: Color
    let dashHeight: CGFloat
    let gap: CGFloat
    let width: CGFloat

    var body: some View {
        DashedLineShape(dashHeight: dashHeight, gap: gap, width: width)
            .fill(color)
        .allowsHitTesting(false)
    }
}

private struct DashedLineShape: Shape {
    let dashHeight: CGFloat
    let gap: CGFloat
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var y = rect.minY
        let step = max(dashHeight + gap, 1)
        let x = rect.midX - width / 2
        while y < rect.maxY {
            path.addRect(CGRect(x: x, y: y, width: width, height: min(dashHeight, rect.maxY - y)))
            y += step
        }
        return path
    }
}

private struct PassportKitLeatherFallback: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 5
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let seed = (Int(x) * 31 + Int(y) * 17) % 97
                    let width = CGFloat(seed % 4 + 1)
                    let height = CGFloat(seed % 3 + 1) * 0.55
                    let opacity = 0.06 + Double(seed % 7) * 0.008
                    let rect = CGRect(x: x, y: y, width: width, height: height)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))

                    if seed % 5 == 0 {
                        let darkRect = CGRect(x: x + 1, y: y + 1.8, width: width * 0.8, height: 0.55)
                        context.fill(Path(ellipseIn: darkRect), with: .color(.black.opacity(0.045)))
                    }

                    x += step
                }
                y += step
            }
        }
    }
}

#Preview("Cover") {
    PassportKitCoverView(holderName: "YUSEI SAKURAI", visitedCountryCount: 2)
        .padding()
        .background(Color(red: 0.957, green: 0.945, blue: 0.921))
}

#Preview("Page") {
    PassportKitPageView(stamps: StampDesign.library, pageNumber: 1, fixedWidth: 360)
        .padding()
        .background(Color(red: 0.957, green: 0.945, blue: 0.921))
}

#Preview("Paper") {
    LinearGradient(
        colors: [PassportKitTheme.paperBase, PassportKitTheme.paperShade],
        startPoint: .top,
        endPoint: .bottom
    )
    .colorEffect(ShaderLibrary.fineGrain(.float(0.055)))
    .aspectRatio(2.0 / 3.0, contentMode: .fit)
    .padding()
    .background(Color(red: 0.957, green: 0.945, blue: 0.921))
}
