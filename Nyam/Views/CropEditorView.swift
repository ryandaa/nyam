import SwiftUI
import UIKit

/// Simple in-app crop editor. The user picks a photo from the library, this
/// sheet shows the image with a draggable crop rectangle and corner handles,
/// and on Done it produces a cropped UIImage ready for the scan pipeline.
///
/// State is held in **normalized image coordinates** (0…1 on both axes) so
/// the math doesn't care about screen size or rotation.
struct CropEditorView: View {
    let image: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    /// Crop rect in normalized image-space. (0,0) = top-left, (1,1) = bottom-right.
    /// Default = full image so a user who just taps Done passes the whole thing through.
    @State private var cropNorm: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    private let minCropSize: CGFloat = 0.12   // 12% of either dimension minimum
    private let handleSize: CGFloat = 26

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let layout = imageLayout(in: geo.size)
                let cropFrame = screenRect(for: cropNorm, layout: layout)

                ZStack(alignment: .topLeading) {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .frame(width: layout.size.width, height: layout.size.height)
                        .offset(x: layout.origin.x, y: layout.origin.y)

                    // Darken outside the crop rectangle.
                    Color.black.opacity(0.55)
                        .mask {
                            Rectangle()
                                .overlay(alignment: .topLeading) {
                                    Rectangle()
                                        .frame(width: cropFrame.width, height: cropFrame.height)
                                        .offset(x: cropFrame.minX, y: cropFrame.minY)
                                        .blendMode(.destinationOut)
                                }
                                .compositingGroup()
                        }
                        .allowsHitTesting(false)

                    // Crop rectangle border + thirds grid.
                    cropBorder(frame: cropFrame)

                    // Corner drag handles.
                    ForEach(Corner.allCases) { corner in
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().stroke(Color.NyamSage.shade5, lineWidth: 2))
                            .frame(width: handleSize, height: handleSize)
                            .offset(handleOffset(for: corner, frame: cropFrame))
                            .gesture(cornerDragGesture(corner: corner, layout: layout))
                    }
                }
                .contentShape(Rectangle())
            }
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .principal) {
                    Text("Drag the corners to focus")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") { confirmCrop() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.NyamSage.tint5)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Layout helpers

    private struct ImageLayout {
        let origin: CGPoint
        let size: CGSize
    }

    /// Aspect-fit the image into `containerSize`.
    private func imageLayout(in containerSize: CGSize) -> ImageLayout {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height
        let size: CGSize
        if imageAspect > containerAspect {
            size = CGSize(width: containerSize.width, height: containerSize.width / imageAspect)
        } else {
            size = CGSize(width: containerSize.height * imageAspect, height: containerSize.height)
        }
        let origin = CGPoint(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2
        )
        return ImageLayout(origin: origin, size: size)
    }

    /// Map a normalized rect to screen coords given the displayed image's layout.
    private func screenRect(for norm: CGRect, layout: ImageLayout) -> CGRect {
        CGRect(
            x: layout.origin.x + norm.minX * layout.size.width,
            y: layout.origin.y + norm.minY * layout.size.height,
            width: norm.width * layout.size.width,
            height: norm.height * layout.size.height
        )
    }

    private enum Corner: CaseIterable, Identifiable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        var id: Self { self }
    }

    private func handleOffset(for corner: Corner, frame: CGRect) -> CGSize {
        let cx: CGFloat = frame.minX - handleSize / 2
        let cxR: CGFloat = frame.maxX - handleSize / 2
        let cy: CGFloat = frame.minY - handleSize / 2
        let cyR: CGFloat = frame.maxY - handleSize / 2
        switch corner {
        case .topLeading:     return CGSize(width: cx,  height: cy)
        case .topTrailing:    return CGSize(width: cxR, height: cy)
        case .bottomLeading:  return CGSize(width: cx,  height: cyR)
        case .bottomTrailing: return CGSize(width: cxR, height: cyR)
        }
    }

    @ViewBuilder
    private func cropBorder(frame: CGRect) -> some View {
        ZStack {
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 2)
                .frame(width: frame.width, height: frame.height)

            // Rule-of-thirds grid lines, dimmed.
            ForEach(1..<3) { i in
                Path { p in
                    let x = frame.width * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: frame.height))
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 0.7)
                .frame(width: frame.width, height: frame.height)
            }
            ForEach(1..<3) { i in
                Path { p in
                    let y = frame.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: frame.width, y: y))
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 0.7)
                .frame(width: frame.width, height: frame.height)
            }
        }
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
    }

    // MARK: - Drag handling

    private func cornerDragGesture(corner: Corner, layout: ImageLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Convert the drag's screen-space location into normalized image-space.
                let nx = (value.location.x - layout.origin.x) / layout.size.width
                let ny = (value.location.y - layout.origin.y) / layout.size.height
                let cx = max(0, min(1, nx))
                let cy = max(0, min(1, ny))

                var rect = cropNorm
                switch corner {
                case .topLeading:
                    let maxX = rect.maxX
                    let maxY = rect.maxY
                    rect.origin.x = min(cx, maxX - minCropSize)
                    rect.origin.y = min(cy, maxY - minCropSize)
                    rect.size.width = maxX - rect.origin.x
                    rect.size.height = maxY - rect.origin.y
                case .topTrailing:
                    let maxY = rect.maxY
                    rect.origin.y = min(cy, maxY - minCropSize)
                    rect.size.width = max(cx - rect.minX, minCropSize)
                    rect.size.height = maxY - rect.origin.y
                case .bottomLeading:
                    let maxX = rect.maxX
                    rect.origin.x = min(cx, maxX - minCropSize)
                    rect.size.width = maxX - rect.origin.x
                    rect.size.height = max(cy - rect.minY, minCropSize)
                case .bottomTrailing:
                    rect.size.width = max(cx - rect.minX, minCropSize)
                    rect.size.height = max(cy - rect.minY, minCropSize)
                }
                cropNorm = rect
            }
    }

    // MARK: - Confirm

    private func confirmCrop() {
        // If the user left the rect at the full image, skip the cropping
        // operation entirely — pass the original through.
        let untouched = cropNorm.origin.x < 0.01 && cropNorm.origin.y < 0.01
            && cropNorm.width > 0.99 && cropNorm.height > 0.99
        if untouched {
            onConfirm(image)
            return
        }
        onConfirm(crop(image, normRect: cropNorm) ?? image)
    }

    private func crop(_ image: UIImage, normRect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        // Convert normalized rect (in displayed orientation) to the cgImage's
        // pixel rect, which is always in the raw bitmap's coordinate space.
        let pixelRect = CGRect(
            x: normRect.minX * w,
            y: normRect.minY * h,
            width: normRect.width * w,
            height: normRect.height * h
        )
            .integral
        guard let croppedCG = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }
}

#Preview {
    CropEditorView(
        image: UIImage(systemName: "photo")!,
        onConfirm: { _ in },
        onCancel: {}
    )
}
