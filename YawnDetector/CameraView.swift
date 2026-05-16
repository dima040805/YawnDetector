//
//  CameraView.swift
//  YawnDetector
//
//  SwiftUI обёртка для CameraViewController.
//
//  Принципы работы:
//  1. UIViewControllerRepresentable создаёт UIKit контроллер
//  2. Coordinator выступает как делегат CameraViewController
//  3. Кадры передаются в ViewModel через Coordinator
//  4. При dismount останавливается сессия камеры
//

import SwiftUI
import AVFoundation

struct CameraView: UIViewControllerRepresentable {
    
    @ObservedObject var viewModel: YawnDetectorViewModel
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
    
    static func dismantleUIViewController(_ uiViewController: CameraViewController, coordinator: Coordinator) {
        uiViewController.stopSession()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    final class Coordinator: NSObject, CameraViewControllerDelegate {
        
        private let viewModel: YawnDetectorViewModel
        
        init(viewModel: YawnDetectorViewModel) {
            self.viewModel = viewModel
            super.init()
        }
        
        func cameraViewController(
            _ controller: CameraViewController,
            didCapture sampleBuffer: CMSampleBuffer
        ) {
            // CMSampleBuffer нельзя передавать между потоками
            // processFrame сам выполняет обработку асинхронно
            viewModel.processFrame(sampleBuffer)
        }
        
        func cameraViewController(
            _ controller: CameraViewController,
            didEncounterError error: String
        ) {
            Task { @MainActor in
                viewModel.errorMessage = error
            }
        }
    }
}
