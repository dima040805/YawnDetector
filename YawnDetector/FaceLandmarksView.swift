//
//  FaceLandmarksView.swift
//  YawnDetector
//
//  Визуализация детекции лица и рта.
//
//  Система координат Vision → Screen:
//  - Vision: normalized (0..1), origin BOTTOM-LEFT, Y grows UP
//  - Screen: pixels, origin TOP-LEFT, Y grows DOWN
//
//  ВАЖНО: AVCaptureVideoPreviewLayer с .resizeAspectFill масштабирует
//  и обрезает кадр. Vision обрабатывает ПОЛНЫЙ кадр, поэтому нужно
//  учитывать это при преобразовании координат.
//

import SwiftUI

struct FaceLandmarksView: View {
    
    let faceData: FaceDetectionData
    let viewSize: CGSize
    
    // Соотношение сторон камеры (1920x1080 для .high preset = 16:9)
    // После поворота на 90° становится 9:16 = 0.5625
    private let cameraAspectRatio: CGFloat = 9.0 / 16.0
    
    var body: some View {
        Canvas { context, size in
            guard faceData.isFaceDetected else { return }
            
            // Вычисляем параметры преобразования с учётом AspectFill
            let transform = calculateAspectFillTransform(viewSize: size)
            
            // Зелёная рамка вокруг лица
            let faceRect = convertVisionRect(
                faceData.faceBoundingBox,
                to: size,
                transform: transform
            )
            let facePath = Path(roundedRect: faceRect, cornerRadius: 10)
            context.stroke(facePath, with: .color(.green), lineWidth: 3)
            
            // Рамка рта (cyan = норма, red = зевок)
            if faceData.mouthBoundingBox != .zero {
                let mouthRect = convertVisionRect(
                    faceData.mouthBoundingBox,
                    to: size,
                    transform: transform
                )
                
                // Добавляем padding для лучшей видимости
                let paddedRect = mouthRect.insetBy(dx: -8, dy: -4)
                let mouthPath = Path(roundedRect: paddedRect, cornerRadius: 6)
                
                let color: Color = faceData.isYawning ? .red : .cyan
                let lineWidth: CGFloat = faceData.isYawning ? 4 : 2
                
                // Заливка при зевке
                if faceData.isYawning {
                    context.fill(mouthPath, with: .color(color.opacity(0.3)))
                }
                
                context.stroke(mouthPath, with: .color(color), lineWidth: lineWidth)
            }
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Coordinate Transform
    
    /// Параметры трансформации для AspectFill
    private struct AspectFillTransform {
        let scaleX: CGFloat
        let scaleY: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
    }
    
    /// Вычисляет параметры трансформации для AspectFill
    /// Camera frame масштабируется так, чтобы заполнить view, часть обрезается
    private func calculateAspectFillTransform(viewSize: CGSize) -> AspectFillTransform {
        let viewAspectRatio = viewSize.width / viewSize.height
        
        // AspectFill: масштабируем так, чтобы заполнить view полностью
        // Меньшая сторона подгоняется, большая обрезается
        
        if cameraAspectRatio < viewAspectRatio {
            // Camera уже чем view → масштабируем по ширине, обрезаем высоту
            let scale = viewSize.width / cameraAspectRatio / viewSize.height
            let visibleHeightRatio = 1.0 / scale
            let cropY = (1.0 - visibleHeightRatio) / 2.0
            
            return AspectFillTransform(
                scaleX: viewSize.width,
                scaleY: viewSize.height * scale,
                offsetX: 0,
                offsetY: -cropY * viewSize.height * scale
            )
        } else {
            // Camera шире чем view → масштабируем по высоте, обрезаем ширину
            let scale = viewSize.height * cameraAspectRatio / viewSize.width
            let visibleWidthRatio = 1.0 / scale
            let cropX = (1.0 - visibleWidthRatio) / 2.0
            
            return AspectFillTransform(
                scaleX: viewSize.width * scale,
                scaleY: viewSize.height,
                offsetX: -cropX * viewSize.width * scale,
                offsetY: 0
            )
        }
    }
    
    /// Преобразование Vision rect → Screen rect с учётом AspectFill
    private func convertVisionRect(
        _ visionRect: CGRect,
        to size: CGSize,
        transform: AspectFillTransform
    ) -> CGRect {
        // Vision: origin at bottom-left, Y up
        // Screen: origin at top-left, Y down
        
        let x = visionRect.origin.x * transform.scaleX + transform.offsetX
        let y = (1 - visionRect.origin.y - visionRect.height) * transform.scaleY + transform.offsetY
        let width = visionRect.width * transform.scaleX
        let height = visionRect.height * transform.scaleY
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

#Preview("Normal") {
    ZStack {
        Color.black
        FaceLandmarksView(
            faceData: FaceDetectionData(
                faceBoundingBox: CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.5),
                mouthBoundingBox: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.08),
                isYawning: false,
                isFaceDetected: true
            ),
            viewSize: CGSize(width: 400, height: 600)
        )
        .frame(width: 400, height: 600)
    }
}

#Preview("Yawning") {
    ZStack {
        Color.black
        FaceLandmarksView(
            faceData: FaceDetectionData(
                faceBoundingBox: CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.5),
                mouthBoundingBox: CGRect(x: 0.35, y: 0.32, width: 0.3, height: 0.15),
                isYawning: true,
                isFaceDetected: true
            ),
            viewSize: CGSize(width: 400, height: 600)
        )
        .frame(width: 400, height: 600)
    }
}
