//
//  CameraViewController.swift
//  YawnDetector
//
//  Контроллер для управления камерой через AVFoundation.
//
//  Назначение:
//  - Настройка и управление AVCaptureSession
//  - Получение видеопотока с фронтальной камеры
//  - Передача кадров в ViewModel для обработки Vision
//  - Отображение превью камеры
//
//  Принципы работы:
//  1. Создаём AVCaptureSession с пресетом .high для качественного видео
//  2. Подключаем фронтальную камеру как input
//  3. Добавляем AVCaptureVideoDataOutput для получения кадров
//  4. Кадры обрабатываются на выделенной очереди (не блокируем UI)
//  5. Каждый кадр передаётся в ViewModel через делегат
//
//  Жизненный цикл:
//  - viewDidLoad: настройка сессии
//  - viewWillAppear: запуск сессии
//  - viewWillDisappear: остановка сессии
//

import UIKit
import AVFoundation

// MARK: - Delegate Protocol

/// Протокол для передачи кадров камеры
protocol CameraViewControllerDelegate: AnyObject {
    /// Вызывается при получении нового кадра
    /// - Parameter sampleBuffer: буфер с изображением
    func cameraViewController(_ controller: CameraViewController, didCapture sampleBuffer: CMSampleBuffer)
    
    /// Вызывается при ошибке камеры
    /// - Parameter error: описание ошибки
    func cameraViewController(_ controller: CameraViewController, didEncounterError error: String)
}

// MARK: - Camera View Controller

final class CameraViewController: UIViewController {
    
    // MARK: - Properties
    
    /// Делегат для передачи кадров
    weak var delegate: CameraViewControllerDelegate?
    
    /// Сессия захвата видео
    private let captureSession = AVCaptureSession()
    
    /// Слой для отображения превью камеры
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    /// Очередь для обработки видео кадров (фоновый поток)
    private let videoDataOutputQueue = DispatchQueue(
        label: "com.yawndetector.videodata",
        qos: .userInteractive,
        attributes: [],
        autoreleaseFrequency: .workItem
    )
    
    /// Флаг: сессия настроена
    private var isSessionConfigured = false
    
    /// Флаг: сессия запущена
    private var isSessionRunning = false
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        // Проверяем разрешение на использование камеры
        checkCameraAuthorization()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    // MARK: - Camera Authorization
    
    /// Проверка и запрос разрешения на использование камеры
    private func checkCameraAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // Разрешение уже получено
            setupCaptureSession()
            
        case .notDetermined:
            // Запрашиваем разрешение
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCaptureSession()
                    } else {
                        self?.delegate?.cameraViewController(
                            self!,
                            didEncounterError: "Camera access denied. Please enable camera access in Settings."
                        )
                    }
                }
            }
            
        case .denied, .restricted:
            delegate?.cameraViewController(
                self,
                didEncounterError: "Camera access denied. Please enable camera access in Settings."
            )
            
        @unknown default:
            delegate?.cameraViewController(
                self,
                didEncounterError: "Unknown camera authorization status."
            )
        }
    }
    
    // MARK: - Capture Session Setup
    
    /// Настройка сессии захвата видео
    private func setupCaptureSession() {
        guard !isSessionConfigured else { return }
        
        captureSession.beginConfiguration()
        
        // Устанавливаем качество видео
        captureSession.sessionPreset = .high
        
        // Настраиваем вход (фронтальная камера)
        guard setupCameraInput() else {
            captureSession.commitConfiguration()
            return
        }
        
        // Настраиваем выход (поток кадров)
        setupVideoOutput()
        
        // Настраиваем превью слой
        setupPreviewLayer()
        
        captureSession.commitConfiguration()
        isSessionConfigured = true
        
        // Запускаем сессию
        startSession()
    }
    
    /// Настройка входа камеры
    /// - Returns: true если настройка успешна
    private func setupCameraInput() -> Bool {
        // Ищем фронтальную камеру
        guard let frontCamera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else {
            delegate?.cameraViewController(
                self,
                didEncounterError: "Front camera not available on this device."
            )
            return false
        }
        
        do {
            let cameraInput = try AVCaptureDeviceInput(device: frontCamera)
            
            if captureSession.canAddInput(cameraInput) {
                captureSession.addInput(cameraInput)
                return true
            } else {
                delegate?.cameraViewController(
                    self,
                    didEncounterError: "Could not add camera input to capture session."
                )
                return false
            }
        } catch {
            delegate?.cameraViewController(
                self,
                didEncounterError: "Could not create camera input: \(error.localizedDescription)"
            )
            return false
        }
    }
    
    /// Настройка выхода видеопотока
    private func setupVideoOutput() {
        let videoOutput = AVCaptureVideoDataOutput()
        
        // Настраиваем формат пикселей
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        // Пропускаем кадры если обработка не успевает
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        // Устанавливаем делегат для получения кадров
        videoOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            
            // Настраиваем ориентацию видео
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
        }
    }
    
    /// Настройка слоя превью
    private func setupPreviewLayer() {
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
    }
    
    // MARK: - Session Control
    
    /// Запуск сессии захвата
    private func startSession() {
        guard isSessionConfigured, !isSessionRunning else { return }
        
        videoDataOutputQueue.async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = true
            }
        }
    }
    
    /// Остановка сессии захвата
    func stopSession() {
        guard isSessionRunning else { return }
        
        videoDataOutputQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = false
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Передаём кадр делегату для обработки Vision
        delegate?.cameraViewController(self, didCapture: sampleBuffer)
    }
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Кадр был пропущен из-за перегрузки
        // Это нормально при высокой нагрузке, не требует действий
    }
}
