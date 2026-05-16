//
//  StatisticsView.swift
//  YawnDetector
//
//  Отображение статистики и графиков зевоты.
//
//  Назначение:
//  - Отображение счётчика зевков
//  - Отображение текущей частоты зевоты (зевков/мин)
//  - Отображение текущего Aspect Ratio рта (для отладки)
//  - Визуализация индикатора статуса (Normal / Yawning / Alert)
//  - График частоты зевоты за последние 60 секунд (Swift Charts)
//
//  Используемые технологии:
//  - Swift Charts (Apple) для построения графика
//  - Скользящее окно 60 секунд для расчёта частоты
//  - Пороговая линия на графике (3 зевка/мин = предупреждение)
//

import SwiftUI
import Charts

// MARK: - Statistics View

struct StatisticsView: View {
    
    @ObservedObject var viewModel: YawnDetectorViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            // Индикатор статуса
            StatusIndicatorView(status: viewModel.status)
            
            // Счётчики
            HStack(spacing: 20) {
                StatCard(
                    title: "Всего зевков",
                    value: "\(viewModel.totalYawnCount)",
                    icon: "mouth",
                    color: .blue
                )
                
                StatCard(
                    title: "Зевков/мин",
                    value: String(format: "%.1f", viewModel.yawnFrequency),
                    icon: "chart.line.uptrend.xyaxis",
                    color: viewModel.yawnFrequency >= 3 ? .red : .green
                )
            }
            
            // Текущий AR рта (для отладки)
            HStack {
                Text("AR рта:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.3f", viewModel.currentMouthAR))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(viewModel.faceData.isYawning ? .red : .primary)
                
                Spacer()
                
                // Индикатор порога
                Text("Порог: 0.25")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            // График частоты
            YawnFrequencyChart(dataPoints: viewModel.frequencyHistory)
                .frame(height: 120)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Status Indicator

struct StatusIndicatorView: View {
    
    let status: DrowsinessStatus
    
    var body: some View {
        HStack(spacing: 8) {
            // Пульсирующий индикатор
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .overlay {
                    if status == .alert {
                        Circle()
                            .stroke(statusColor, lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.5)
                            .animation(
                                .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true),
                                value: status
                            )
                    }
                }
            
            Text(status.rawValue)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.3), value: status)
    }
    
    private var statusColor: Color {
        switch status {
        case .normal: return .green
        case .yawning: return .yellow
        case .alert: return .red
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            
            Text(value)
                .font(.title2.monospacedDigit())
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Frequency Chart

struct YawnFrequencyChart: View {
    
    let dataPoints: [YawnFrequencyDataPoint]
    
    /// Порог предупреждения о сонливости
    private let alertThreshold: Double = 3.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Частота зевков (последние 60с)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Chart {
                // Основной график частоты
                ForEach(dataPoints) { point in
                    LineMark(
                        x: .value("Время", point.timestamp),
                        y: .value("Частота", point.frequency)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    
                    AreaMark(
                        x: .value("Время", point.timestamp),
                        y: .value("Частота", point.frequency)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.blue.opacity(0.3), .cyan.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                
                // Пороговая линия (3 зевка/мин)
                RuleMark(y: .value("Порог", alertThreshold))
                    .foregroundStyle(.red.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Опасно")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                            .background(.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
            }
            .chartYScale(domain: 0...6)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 1, 2, 3, 4, 5, 6]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)")
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Previews

#Preview("Statistics View") {
    let viewModel = YawnDetectorViewModel()
    
    return ZStack {
        Color.black.opacity(0.8)
        
        StatisticsView(viewModel: viewModel)
            .padding()
    }
}

#Preview("Status Indicators") {
    VStack(spacing: 20) {
        StatusIndicatorView(status: .normal)
        StatusIndicatorView(status: .yawning)
        StatusIndicatorView(status: .alert)
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
