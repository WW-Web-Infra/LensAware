import SwiftUI

struct DetectView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var detectionManager: HealthDetectionManager

    @StateObject private var streamManager = CameraStreamManager()
    @State private var showProfilePicker = false

    var body: some View {
        ZStack(alignment: .bottom) {
            cameraBackground

            VStack(spacing: 0) {
                topBar
                Spacer()

                if let analysis = detectionManager.lastAnalysis {
                    HealthSummaryCard(analysis: analysis) {
                        detectionManager.clearLastAnalysis()
                        Task { await appState.refreshStats() }
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
        .sheet(isPresented: $showProfilePicker) {
            profilePickerSheet
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
            ConnectionStatusPill(isConnected: appState.isGlassesConnected) {}
                .allowsHitTesting(false)

            Spacer()

            Text("Detect")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            Button {
                showProfilePicker = true
            } label: {
                Image(systemName: "cpu")
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
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

    // MARK: - Profile picker sheet

    private var profilePickerSheet: some View {
        NavigationStack {
            List(appState.allProfiles) { profile in
                Button {
                    Task {
                        await appState.setActiveProfile(profile)
                        showProfilePicker = false
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(profile.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if profile.isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Switch Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showProfilePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - HealthSummaryCard

struct HealthSummaryCard: View {
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
