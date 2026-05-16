//
//  ContentView.swift
//  YawnDetector
//
//  Основной экран приложения.
//
//  Структура UI:
//  1. Заголовок с названием приложения
//  2. Видео с камеры + наложение landmarks
//  3. Панель статистики с графиком
//  4. Кнопка сброса сессии
//

import SwiftUI

struct ContentView: View {
    
    @StateObject private var viewModel = YawnDetectorViewModel()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Заголовок
                    HeaderView()
                    
                    // Основная область: камера + наложения
                    CameraContainerView(viewModel: viewModel)
                        .frame(height: geometry.size.height * 0.55)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 16)
                    
                    // Статистика
                    StatisticsView(viewModel: viewModel)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    
                    Spacer(minLength: 8)
                    
                    // Кнопка сброса
                    ResetButton(action: viewModel.resetSession)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
        }
        .alert("Ошибка камеры", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("ОК") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Неизвестная ошибка")
        }
        .alert("⚠️ Обнаружена усталость!", isPresented: $viewModel.showDrowsinessAlert) {
            Button("Я в порядке", role: .cancel) {
                viewModel.showDrowsinessAlert = false
            }
            Button("Сбросить сессию", role: .destructive) {
                viewModel.resetSession()
            }
        } message: {
            Text("Вы зевнули более 3 раз за последнюю минуту. Это может означать усталость. Сделайте перерыв!")
        }
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - Camera Container View

/// Контейнер для камеры с правильным вычислением размеров
struct CameraContainerView: View {
    @ObservedObject var viewModel: YawnDetectorViewModel
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Видео с камеры
                CameraView(viewModel: viewModel)
                
                // Наложение: рамки лица и рта
                // Используем точный размер контейнера
                FaceLandmarksView(
                    faceData: viewModel.faceData,
                    viewSize: geometry.size
                )
                
                // Сообщение если лицо не детектировано
                if !viewModel.faceData.isFaceDetected {
                    NoFaceDetectedOverlay()
                }
                
                // Debug overlay (AR value)
                VStack {
                    HStack {
                        Spacer()
                        DebugOverlay(viewModel: viewModel)
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Debug Overlay

struct DebugOverlay: View {
    @ObservedObject var viewModel: YawnDetectorViewModel
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("AR: \(String(format: "%.2f", viewModel.currentMouthAR))")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            
            Text(viewModel.faceData.isFaceDetected ? "Лицо: ✓" : "Лицо: ✗")
                .font(.system(size: 10, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Header View

struct HeaderView: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Детектор зевоты")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                Text("Система мониторинга усталости")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            
            Spacer()
            
            Image(systemName: "camera.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .symbolEffect(.pulse, options: .repeating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black)
    }
}

// MARK: - No Face Detected Overlay

struct NoFaceDetectedOverlay: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "face.dashed")
                .font(.system(size: 50))
                .foregroundStyle(.gray)
            
            Text("Лицо не обнаружено")
                .font(.headline)
                .foregroundStyle(.gray)
            
            Text("Расположите лицо в поле зрения камеры")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Reset Button

struct ResetButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                Text("Сбросить сессию")
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.gray.opacity(0.3))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
