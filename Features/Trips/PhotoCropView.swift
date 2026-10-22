import SwiftUI
import UIKit

struct PhotoCropView: View {
    let image: UIImage
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var scale: CGFloat = 1
    @State private var gestureStartScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let outputSize: CGFloat = 768
    private let maximumScale: CGFloat = 3.25

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let cropSize = min(proxy.size.width - 36, proxy.size.height * 0.58, 420)
                let effectiveScale = max(scale, minimumScale(cropSize: cropSize))

                VStack(spacing: 18) {
                    Spacer(minLength: 12)

                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(effectiveScale)
                            .offset(offset)
                            .frame(width: cropSize, height: cropSize)
                            .simultaneousGesture(dragGesture(cropSize: cropSize))
                            .simultaneousGesture(magnifyGesture(cropSize: cropSize))

                        Circle()
                            .fill(colorScheme == .dark ? .black.opacity(0.10) : .white.opacity(0.08))
                            .frame(width: cropSize, height: cropSize)
                            .allowsHitTesting(false)

                        Circle()
                            .stroke(colorScheme == .dark ? .white.opacity(0.95) : .white.opacity(0.98), lineWidth: 2)
                            .frame(width: cropSize, height: cropSize)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: cropSize)
                    .clipped()
                    .background(Color.black.opacity(colorScheme == .dark ? 0.26 : 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 14)

                    Text(WanderlustL10n.string("Pinch to zoom and drag to adjust.", table: .trips))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
                .navigationTitle(WanderlustL10n.string("Adjust Photo", table: .account))
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) {
                            guard !isSaving else { return }
                            onCancel()
                            dismiss()
                        }
                        .tint(.blue)
                        .fontWeight(.regular)
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Save")) {
                            saveCroppedImage(cropSize: cropSize)
                        }
                        .tint(.blue)
                        .fontWeight(.regular)
                        .disabled(isSaving)
                    }
                }
                .overlay {
                    if isSaving {
                        ProgressView()
                            .padding(18)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .onAppear {
                    let minScale = minimumScale(cropSize: cropSize)
                    scale = max(scale, minScale)
                    gestureStartScale = scale
                    offset = clampedOffset(offset, cropSize: cropSize)
                    lastOffset = offset
                }
                .onChange(of: cropSize) { _, newCropSize in
                    let minScale = minimumScale(cropSize: newCropSize)
                    scale = max(scale, minScale)
                    gestureStartScale = max(gestureStartScale, minScale)
                    offset = clampedOffset(offset, cropSize: newCropSize)
                    lastOffset = offset
                }
            }
        }
        .alert(
            WanderlustL10n.string("Profile Photo", table: .account),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func clampedOffset(_ proposed: CGSize, cropSize: CGFloat) -> CGSize {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        let baseScale = min(cropSize / imageSize.width, cropSize / imageSize.height)
        let minimumScale = minimumScale(cropSize: cropSize)
        let effectiveScale = max(scale, minimumScale)
        let displayedWidth = imageSize.width * baseScale * effectiveScale
        let displayedHeight = imageSize.height * baseScale * effectiveScale
        let maxX = max((displayedWidth - cropSize) / 2, 0)
        let maxY = max((displayedHeight - cropSize) / 2, 0)

        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func dragGesture(cropSize: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clampedOffset(
                    CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    ),
                    cropSize: cropSize
                )
            }
            .onEnded { _ in
                offset = clampedOffset(offset, cropSize: cropSize)
                lastOffset = offset
            }
    }

    private func magnifyGesture(cropSize: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(gestureStartScale * value.magnification, minimumScale(cropSize: cropSize)), maximumScale)
                offset = clampedOffset(offset, cropSize: cropSize)
            }
            .onEnded { _ in
                scale = min(max(scale, minimumScale(cropSize: cropSize)), maximumScale)
                gestureStartScale = scale
                offset = clampedOffset(offset, cropSize: cropSize)
                lastOffset = offset
            }
    }

    private func minimumScale(cropSize: CGFloat) -> CGFloat {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return 1
        }
        let baseScale = min(cropSize / imageSize.width, cropSize / imageSize.height)
        let fittedWidth = imageSize.width * baseScale
        let fittedHeight = imageSize.height * baseScale
        return max(cropSize / max(fittedWidth, 1), cropSize / max(fittedHeight, 1), 1)
    }

    private func saveCroppedImage(cropSize: CGFloat) {
        guard !isSaving else { return }
        isSaving = true
        let image = image
        let scale = max(scale, minimumScale(cropSize: cropSize))
        let offset = offset
        let outputSize = outputSize

        #if DEBUG
        let start = CFAbsoluteTimeGetCurrent()
        print("[WanderlustPerformance] photo_save_start source=\(Int(image.size.width))x\(Int(image.size.height))")
        #endif

        Task { @MainActor in
            let cropped = ProfilePhotoRenderer.renderCroppedImage(
                image: image,
                cropSize: cropSize,
                scale: scale,
                offset: offset,
                outputSize: outputSize
            )
            #if DEBUG
            print(String(format: "[WanderlustPerformance] photo_save %.1fms", (CFAbsoluteTimeGetCurrent() - start) * 1000))
            #endif
            onSave(cropped)
            isSaving = false
            dismiss()
        }
    }

}

enum ProfilePhotoRenderer {
    @MainActor
    static func renderCroppedImage(
        image: UIImage,
        cropSize: CGFloat,
        scale: CGFloat,
        offset: CGSize,
        outputSize: CGFloat
    ) -> UIImage {
        let normalized = image.normalizedOrientation()
        let imageSize = normalized.size
        let baseScale = min(cropSize / imageSize.width, cropSize / imageSize.height)
        let effectiveScale = baseScale * scale
        let displayedWidth = imageSize.width * effectiveScale
        let displayedHeight = imageSize.height * effectiveScale
        let drawX = (cropSize - displayedWidth) / 2 + offset.width
        let drawY = (cropSize - displayedHeight) / 2 + offset.height
        let factor = outputSize / cropSize
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize))
        return renderer.image { ctx in
            ctx.cgContext.addEllipse(in: CGRect(x: 0, y: 0, width: outputSize, height: outputSize))
            ctx.cgContext.clip()
            normalized.draw(in: CGRect(
                x: drawX * factor, y: drawY * factor,
                width: displayedWidth * factor, height: displayedHeight * factor
            ))
        }
    }

    static func previewImage(from data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.normalizedOrientation()
        }.value
    }
}

extension UIImage {
    nonisolated func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }

        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    nonisolated func resized(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
