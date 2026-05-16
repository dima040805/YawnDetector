//
//  YawnDetectorViewModel.swift
//  YawnDetector
//
//  Детектор зевоты на основе Vision Framework.
//
//  Алгоритм AR (Mouth Aspect Ratio):
//  - Ширина рта: из outerLips (полный контур губ) - maxX - minX
//  - Высота открытия: из innerLips (внутренний контур) - maxY - minY
//  - AR = высота_открытия / ширина_рта
//
//  При закрытом рте: AR ≈ 0.1 - 0.3
//  При зевке: AR > 0.5
//

import Foundation
import Vision
import AVFoundation
import Combine

// MARK: - Models

enum DrowsinessStatus: String {
    case normal = "Норма"
    case yawning = "Зевок"
    case alert = "ВНИМАНИЕ: УСТАЛОСТЬ!"
}

struct YawnFrequencyDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let frequency: Double
}

struct FaceDetectionData {
    var faceBoundingBox: CGRect = .zero
    var mouthBoundingBox: CGRect = .zero
    var isYawning: Bool = false
    var isFaceDetected: Bool = false
}

// MARK: - ViewModel

@MainActor
final class YawnDetectorViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var totalYawnCount: Int = 0
    @Published private(set) var yawnFrequency: Double = 0.0
    @Published private(set) var status: DrowsinessStatus = .normal
    @Published private(set) var faceData: FaceDetectionData = FaceDetectionData()
    @Published private(set) var currentMouthAR: Double = 0.0
    @Published private(set) var frequencyHistory: [YawnFrequencyDataPoint] = []
    @Published var errorMessage: String?
    @Published var showDrowsinessAlert: Bool = false
    
    // MARK: - Configuration
    
    private let yawnARThreshold: Double = 0.25
    private let yawnMinDuration: TimeInterval = 0.3
    private let yawnDebounceInterval: TimeInterval = 2.0
    private let frequencyWindowSize: TimeInterval = 60.0
    private let drowsinessThreshold: Double = 3.0
    
    // MARK: - Internal State
    
    private var yawnTimestamps: [Date] = []
    private var yawnStartTime: Date?
    private var lastYawnTime: Date?
    private var isCurrentlyYawning: Bool = false
    private var hasRegisteredCurrentYawn: Bool = false
    /// Чтобы алерт не всплывал снова на каждом кадре после «Я в порядке», пока частота не упадёт ниже порога.
    private var wasDrowsinessFrequencyAboveThreshold: Bool = false
    private var graphUpdateTimer: Timer?
    
    private lazy var faceDetectionRequest: VNDetectFaceLandmarksRequest = {
        VNDetectFaceLandmarksRequest { [weak self] request, error in
            self?.handleFaceDetectionResults(request: request, error: error)
        }
    }()
    
    private let visionQueue = DispatchQueue(label: "com.yawndetector.vision", qos: .userInteractive)
    
    // MARK: - Init
    
    init() {
        startGraphUpdateTimer()
    }
    
    deinit {
        graphUpdateTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    nonisolated func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // AVFoundation уже применяет videoRotationAngle=90 и isVideoMirrored=true
        // Поэтому Vision должен получить .up (без дополнительных преобразований)
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        
        visionQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try handler.perform([self.faceDetectionRequest])
            } catch {
                Task { @MainActor in
                    self.errorMessage = "Vision error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func resetSession() {
        totalYawnCount = 0
        yawnFrequency = 0.0
        status = .normal
        yawnTimestamps.removeAll()
        frequencyHistory.removeAll()
        yawnStartTime = nil
        lastYawnTime = nil
        isCurrentlyYawning = false
        hasRegisteredCurrentYawn = false
        wasDrowsinessFrequencyAboveThreshold = false
        showDrowsinessAlert = false
    }
    
    // MARK: - Vision Processing
    
    private func handleFaceDetectionResults(request: VNRequest, error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.errorMessage = "Detection error: \(error.localizedDescription)"
                self.faceData.isFaceDetected = false
            }
            return
        }
        
        guard let results = request.results as? [VNFaceObservation],
              let face = results.first,
              let landmarks = face.landmarks,
              let outerLips = landmarks.outerLips,
              let innerLips = landmarks.innerLips else {
            Task { @MainActor in
                self.faceData.isFaceDetected = false
                self.status = .normal
            }
            return
        }
        
        let faceBox = face.boundingBox
        let outerPoints = outerLips.normalizedPoints
        let innerPoints = innerLips.normalizedPoints
        
        // Вычисляем метрики рта
        let (mouthRect, aspectRatio) = calculateMouthMetrics(
            outerPoints: outerPoints,
            innerPoints: innerPoints,
            faceBox: faceBox
        )
        
        let isYawning = analyzeYawn(aspectRatio: aspectRatio)
        
        #if DEBUG
        print("DEBUG FACE: box=(x:\(String(format: "%.2f", faceBox.origin.x)), y:\(String(format: "%.2f", faceBox.origin.y)), w:\(String(format: "%.2f", faceBox.width)), h:\(String(format: "%.2f", faceBox.height)))")
        print("DEBUG MOUTH: rect=(x:\(String(format: "%.2f", mouthRect.origin.x)), y:\(String(format: "%.2f", mouthRect.origin.y)), w:\(String(format: "%.2f", mouthRect.width)), h:\(String(format: "%.2f", mouthRect.height)))")
        print("DEBUG AR: \(String(format: "%.3f", aspectRatio)) | threshold=\(yawnARThreshold) | yawning=\(isYawning)")
        #endif
        
        Task { @MainActor in
            self.faceData = FaceDetectionData(
                faceBoundingBox: faceBox,
                mouthBoundingBox: mouthRect,
                isYawning: isYawning,
                isFaceDetected: true
            )
            self.currentMouthAR = aspectRatio
            self.updateStatus(isYawning: isYawning)
        }
    }
    
    /// Вычисление метрик рта
    /// - outerPoints: точки внешнего контура губ (для ширины и позиции)
    /// - innerPoints: точки внутреннего контура (для высоты открытия)
    ///
    /// ВАЖНО: normalizedPoints от Vision нормализованы в координатах faceBox (0..1).
    /// Для корректного AR нужно учитывать реальные пропорции faceBox!
    private func calculateMouthMetrics(
        outerPoints: [CGPoint],
        innerPoints: [CGPoint],
        faceBox: CGRect
    ) -> (CGRect, Double) {
        
        guard outerPoints.count >= 4, innerPoints.count >= 4 else {
            return (.zero, 0.0)
        }
        
        // Ширина рта из OUTER lips (полный контур)
        let outerXs = outerPoints.map { $0.x }
        let outerYs = outerPoints.map { $0.y }
        
        guard let outerMinX = outerXs.min(), let outerMaxX = outerXs.max(),
              let outerMinY = outerYs.min(), let outerMaxY = outerYs.max() else {
            return (.zero, 0.0)
        }
        
        // Высота открытия из INNER lips
        let innerYs = innerPoints.map { $0.y }
        guard let innerMinY = innerYs.min(), let innerMaxY = innerYs.max() else {
            return (.zero, 0.0)
        }
        
        // Нормализованные размеры (в координатах faceBox 0..1)
        let normalizedMouthWidth = outerMaxX - outerMinX
        let normalizedMouthOpenHeight = innerMaxY - innerMinY
        
        // РЕАЛЬНЫЕ размеры с учётом пропорций faceBox
        // faceBox может быть НЕ квадратным (например w:0.27, h:0.49)
        let actualMouthWidth = normalizedMouthWidth * faceBox.width
        let actualMouthOpenHeight = normalizedMouthOpenHeight * faceBox.height
        
        // AR = высота открытия / ширина (в реальных пропорциях!)
        let aspectRatio: Double
        if actualMouthWidth > 0.001 {
            aspectRatio = Double(actualMouthOpenHeight / actualMouthWidth)
        } else {
            aspectRatio = 0.0
        }
        
        // Bounding box рта в координатах изображения (Vision space)
        let rectX = faceBox.origin.x + outerMinX * faceBox.width
        let rectY = faceBox.origin.y + outerMinY * faceBox.height
        let rectW = actualMouthWidth
        let rectH = (outerMaxY - outerMinY) * faceBox.height
        
        let mouthRect = CGRect(x: rectX, y: rectY, width: rectW, height: rectH)
        
        return (mouthRect, aspectRatio)
    }
    
    private func analyzeYawn(aspectRatio: Double) -> Bool {
        let now = Date()
        
        if aspectRatio > yawnARThreshold {
            if !isCurrentlyYawning {
                // Начало нового зевка
                yawnStartTime = now
                isCurrentlyYawning = true
                hasRegisteredCurrentYawn = false
            } else if let startTime = yawnStartTime,
                      !hasRegisteredCurrentYawn,
                      now.timeIntervalSince(startTime) >= yawnMinDuration {
                // Зевок длится достаточно долго и ещё не зарегистрирован
                registerYawn(at: now)
                hasRegisteredCurrentYawn = true
            }
            return true
        } else {
            // Рот закрыт — сбрасываем состояние зевка
            isCurrentlyYawning = false
            yawnStartTime = nil
            hasRegisteredCurrentYawn = false
            return false
        }
    }
    
    private func registerYawn(at timestamp: Date) {
        if let lastYawn = lastYawnTime,
           timestamp.timeIntervalSince(lastYawn) < yawnDebounceInterval {
            return
        }
        
        lastYawnTime = timestamp
        yawnTimestamps.append(timestamp)
        
        Task { @MainActor in
            self.totalYawnCount += 1
            self.updateFrequency()
        }
    }
    
    private func updateFrequency() {
        let cutoff = Date().addingTimeInterval(-frequencyWindowSize)
        yawnTimestamps.removeAll { $0 < cutoff }
        yawnFrequency = Double(yawnTimestamps.count)
    }
    
    private func updateStatus(isYawning: Bool) {
        updateFrequency()
        
        let drowsy = yawnFrequency >= drowsinessThreshold
        
        if drowsy {
            status = .alert
            // Показываем предупреждение только при переходе через порог (новый «эпизод» 3+ зевков за минуту).
            if !wasDrowsinessFrequencyAboveThreshold {
                showDrowsinessAlert = true
            }
            wasDrowsinessFrequencyAboveThreshold = true
        } else {
            wasDrowsinessFrequencyAboveThreshold = false
            if isYawning {
                status = .yawning
            } else {
                status = .normal
            }
        }
    }
    
    private func startGraphUpdateTimer() {
        graphUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let point = YawnFrequencyDataPoint(timestamp: Date(), frequency: self.yawnFrequency)
                self.frequencyHistory.append(point)
                let cutoff = Date().addingTimeInterval(-60)
                self.frequencyHistory.removeAll { $0.timestamp < cutoff }
            }
        }
    }
}
