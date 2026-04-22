import SwiftUI

// MARK: - App navigation

enum AppScreen {
    case connection
    case capture
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject private var glassesManager: GlassesManager
    @EnvironmentObject private var detectionManager: HealthDetectionManager

    @State private var currentScreen: AppScreen = .connection

    var body: some View {
        ZStack {
            switch currentScreen {
            case .connection:
                ConnectionView(onConnected: { currentScreen = .capture })

            case .capture:
                CaptureView(onDisconnect: {
                    glassesManager.disconnect()
                    currentScreen = .connection
                })
            }
        }
        .task {
            // 1. Ensure DB tables exist
            await detectionManager.setup()
            // 2. Start connecting to glasses
            glassesManager.startConnection()
        }
    }
}

// MARK: - CaptureView

private struct CaptureView: View {
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

                if let analysis = detectionManager.lastAnalysis {
                    HealthSummaryCard(analysis: analysis) {
                        detectionManager.clearLastAnalysis()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                captureStatusLabel
                    .padding(.bottom, 8)

                captureButton
                    .padding(.horizontal, 40)
                    .padding(.bottom, 48)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: detectionManager.captureState)
        .task {
            streamManager.startStream()
        }
        .onDisappear {
            streamManager.stopStream()
            detectionManager.resetCaptureState()
        }
    }

    // MARK: - Camera background

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
                        Text(streamManager.streamState == .stopped ? "Stream stopped" : "Starting camera…")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                        if streamManager.streamState == .stopped {
                            Button("Restart Stream") {
                                streamManager.stopStream()
                                Task {
                                    try? await Task.sleep(nanoseconds: 500_000_000)
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

    // MARK: - Top bar

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
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Status label

    @ViewBuilder
    private var captureStatusLabel: some View {
        switch detectionManager.captureState {
        case .idle:
            Text("Point glasses at food or your monitor")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

        case .capturing:
            statusPill("Capturing frame…", spinner: true)

        case .analyzing:
            statusPill("Analysing…", spinner: true)

        case .responding:
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(.white)
                Text("Playing response…")
                    .font(.footnote)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

        case .error(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Capture button

    @ViewBuilder
    private var captureButton: some View {
        if case .error = detectionManager.captureState {
            Button {
                detectionManager.resetCaptureState()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        } else {
            Button {
                guard let frame = streamManager.lastFrame,
                      let imageData = frame.jpegData(compressionQuality: 0.8)
                else { return }
                Task { await detectionManager.captureAndAnalyze(imageData) }
            } label: {
                HStack(spacing: 10) {
                    if detectionManager.captureState == .idle {
                        Image(systemName: "camera.circle.fill")
                            .font(.title2)
                    } else {
                        ProgressView().tint(.white)
                    }
                    Text(captureButtonLabel)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(detectionManager.captureState == .idle ? Color.blue : Color.gray.opacity(0.4))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(detectionManager.captureState != .idle)
        }
    }

    private var captureButtonLabel: String {
        switch detectionManager.captureState {
        case .idle:       return "Capture"
        case .capturing:  return "Capturing…"
        case .analyzing:  return "Analysing…"
        case .responding: return "Playing…"
        case .error:      return "Error"
        }
    }

    // MARK: - Helpers

    private func statusPill(_ text: String, spinner: Bool) -> some View {
        HStack(spacing: 8) {
            if spinner { ProgressView().tint(.white) }
            Text(text)
                .font(.footnote)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
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
                Label(
                    "\(analysis.foodAnalysis.mealType.capitalized) — \(analysis.foodAnalysis.totalCalories) kcal",
                    systemImage: "fork.knife"
                )
                .font(.subheadline)
            }

            if analysis.ergonomics.assessment == "needs_adjustment" {
                Label(analysis.ergonomics.suggestion, systemImage: "figure.seated.seatbelt")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            if analysis.diningContext.mindfulEatingScore <= 4 {
                Label(
                    "Mindful eating: \(analysis.diningContext.mindfulEatingScore)/10",
                    systemImage: "brain.head.profile"
                )
                .font(.subheadline)
                .foregroundStyle(.yellow)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
