import SwiftUI

struct LiveDetectionView: View {
    @EnvironmentObject private var glassesManager: GlassesManager
    @EnvironmentObject private var detectionManager: HealthDetectionManager

    let onDisconnect: () -> Void

    @StateObject private var streamManager = CameraStreamManager()

    var body: some View {
        ZStack(alignment: .bottom) {
            cameraBackground

            VStack(spacing: 0) {
                topBar
                Spacer()
                detectionStatusBar
                if case .responded(let analysis) = detectionManager.detectionState {
                    HealthSummaryCard(analysis: analysis) {
                        detectionManager.resetState()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: detectionManager.detectionState)
        .task {
            streamManager.frameDelegate = detectionManager
            streamManager.startStream()
        }
        .onDisappear {
            streamManager.stopStream()
        }
    }

    // MARK: - Sub-views

    private var cameraBackground: some View {
        Group {
            if let frame = streamManager.lastFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black.overlay {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.3))
                        Text(streamManager.streamState == .stopped ? "Stream stopped" : "Starting stream…")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                        if streamManager.streamState == .stopped {
                            Button("Restart Stream") {
                                streamManager.stopStream()
                                Task {
                                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                                    streamManager.startStream()
                                }
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(Color.blue)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button(action: onDisconnect) {
                Image(systemName: "bolt.slash.fill")
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            Spacer()
            Text("LensAware")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            // Spacer for symmetric layout
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var detectionStatusBar: some View {
        switch detectionManager.detectionState {
        case .analyzing:
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("Analysing…")
                    .font(.footnote)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.bottom, 12)

        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red.opacity(0.9))
                .padding(.bottom, 12)

        default:
            Text("Point glasses at food or your monitor")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.bottom, 12)
        }
    }
}

// MARK: - HealthSummaryCard

private struct HealthSummaryCard: View {
    let analysis: LensAnalysis
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Health Snapshot")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            if analysis.foodAnalysis.foodDetected {
                Label("\(analysis.foodAnalysis.mealType.capitalized) — \(analysis.foodAnalysis.totalCalories) kcal", systemImage: "fork.knife")
                    .font(.subheadline)
            }

            if analysis.ergonomics.assessment == "needs_adjustment" {
                Label(analysis.ergonomics.suggestion, systemImage: "figure.seated.seatbelt")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            if analysis.diningContext.mindfulEatingScore <= 2 {
                Label("Mindful eating score: \(analysis.diningContext.mindfulEatingScore)/5", systemImage: "brain.head.profile")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
