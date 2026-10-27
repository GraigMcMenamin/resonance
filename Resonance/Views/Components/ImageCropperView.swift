//
//  ImageCropperView.swift
//  Resonance
//

import SwiftUI

struct ImageCropperView: View {
    let image: UIImage
    let onCropped: (UIImage) -> Void
    let onCancel: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var cropSize: CGFloat = 300
    
    private var imageAspect: CGFloat {
        guard image.size.height > 0 else { return 1 }
        return image.size.width / image.size.height
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Move and Scale")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 16)
                .padding(.bottom, 8)
            
            // Crop area
            GeometryReader { geometry in
                let size = min(geometry.size.width - 32, geometry.size.height - 32)
                
                ZStack {
                    // Image layer — moves and scales
                    Image(uiImage: image)
                        .resizable()
                        .frame(
                            width: displaySize(cropSize: size).width,
                            height: displaySize(cropSize: size).height
                        )
                        .offset(offset)
                    
                    // Darkened border outside the crop square
                    CropOverlay(cropSize: size, cornerRadius: 12)
                        .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)
                    
                    // Crop border
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        .frame(width: size, height: size)
                        .allowsHitTesting(false)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(dragGesture(cropSize: size))
                .gesture(magnificationGesture(cropSize: size))
                .onAppear {
                    cropSize = size
                }
                .onChange(of: size) { newSize in
                    cropSize = newSize
                }
            }
            
            // Bottom hint
            Text("Pinch to zoom, drag to reposition")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 12)
            
            // Buttons below the image
            HStack(spacing: 20) {
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)
                }
                
                Button {
                    cropImage()
                } label: {
                    Text("Done")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
    }
    
    // MARK: - Gestures
    
    private func dragGesture(cropSize: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                clampOffset(cropSize: cropSize)
                lastOffset = offset
            }
    }
    
    private func magnificationGesture(cropSize: CGFloat) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = lastScale * value
                scale = max(1.0, min(newScale, 5.0))
            }
            .onEnded { _ in
                lastScale = scale
                clampOffset(cropSize: cropSize)
                lastOffset = offset
            }
    }
    
    // MARK: - Helpers
    
    /// Displayed image size: short side fills the crop square at scale 1, long side extends beyond it.
    private func displaySize(cropSize: CGFloat) -> CGSize {
        if imageAspect >= 1 {
            let height = cropSize * scale
            return CGSize(width: height * imageAspect, height: height)
        } else {
            let width = cropSize * scale
            return CGSize(width: width, height: width / imageAspect)
        }
    }
    
    private func clampOffset(cropSize: CGFloat) {
        let display = displaySize(cropSize: cropSize)
        let maxOffsetX = max(0, (display.width - cropSize) / 2)
        let maxOffsetY = max(0, (display.height - cropSize) / 2)
        
        withAnimation(.easeOut(duration: 0.15)) {
            offset.width = min(maxOffsetX, max(-maxOffsetX, offset.width))
            offset.height = min(maxOffsetY, max(-maxOffsetY, offset.height))
        }
    }
    
    private func cropImage() {
        let imageSize = image.size
        let shortSide = min(imageSize.width, imageSize.height)
        
        // How much of the image is visible at current scale
        let visibleSize = shortSide / scale
        
        // Convert screen offset to image-space offset (the displayed image is zoomed by `scale`)
        let pixelsPerPoint = visibleSize / cropSize
        
        let offsetXInPixels = -offset.width * pixelsPerPoint
        let offsetYInPixels = -offset.height * pixelsPerPoint
        
        let centerX = imageSize.width / 2 + offsetXInPixels
        let centerY = imageSize.height / 2 + offsetYInPixels
        
        var cropRect = CGRect(
            x: centerX - visibleSize / 2,
            y: centerY - visibleSize / 2,
            width: visibleSize,
            height: visibleSize
        )
        
        // Clamp to image bounds
        cropRect.origin.x = max(0, min(cropRect.origin.x, imageSize.width - cropRect.width))
        cropRect.origin.y = max(0, min(cropRect.origin.y, imageSize.height - cropRect.height))
        cropRect.size.width = min(cropRect.width, imageSize.width)
        cropRect.size.height = min(cropRect.height, imageSize.height)
        
        // Drawing (rather than cgImage cropping) respects image orientation and point/pixel scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: cropRect.size, format: format)
        let croppedImage = renderer.image { _ in
            image.draw(at: CGPoint(x: -cropRect.origin.x, y: -cropRect.origin.y))
        }
        onCropped(croppedImage)
    }
}
    
    // MARK: - Crop Overlay Shape
    
    /// Draws a filled shape everywhere EXCEPT the center square cutout
    struct CropOverlay: Shape {
        let cropSize: CGFloat
        let cornerRadius: CGFloat
        
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addRect(rect)
            
            let cutout = CGRect(
                x: (rect.width - cropSize) / 2,
                y: (rect.height - cropSize) / 2,
                width: cropSize,
                height: cropSize
            )
            let roundedCutout = Path(roundedRect: cutout, cornerRadius: cornerRadius)
            path.addPath(roundedCutout)
            
            return path
        }
    }

