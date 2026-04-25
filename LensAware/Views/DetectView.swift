import SwiftUI

struct DetectView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var detectionManager: HealthDetectionManager
    @EnvironmentObject private var glassesManager: GlassesManager

    @StateObject private var streamManager = CameraStreamManager()
    @State private var showProfilePicker = false
    @State private var showCreateProfileComingSoon = false

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

                if let profile = appState.activeProfile {
                    Text(profile.name)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer().frame(height: 48)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: detectionManager.captureState)
        .task {
            // Only start stream once glasses are connected — mirrors FloraLens SearchingView gate
            if appState.isGlassesConnected {
                streamManager.startStream()
            }
        }
        .onChange(of: appState.isGlassesConnected) { _, connected in
            if connected {
                streamManager.startStream()
            } else {
                streamManager.stopStream()
            }
        }
        .onChange(of: glassesManager.availableDevices) { _, devices in
            // AutoDeviceSelector doesn't re-select once started with empty devices[].
            // When a real device appears, restart the stream so it can be picked up.
            guard !devices.isEmpty else { return }
            guard case .waitingForDevice = streamManager.streamState else { return }
            streamManager.stopStream()
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                streamManager.startStream()
            }
        }
        .onDisappear {
            streamManager.stopStream()
            detectionManager.resetCaptureState()
        }
        .onChange(of: appState.activeProfile) { _, profile in
            guard let profile else { return }
            detectionManager.setActiveProfile(profile)
        }
        .sheet(isPresented: $showProfilePicker) {
            profilePickerSheet
        }
        .alert("Coming Soon", isPresented: $showCreateProfileComingSoon) {
            Button("OK") {}
        } message: {
            Text("Profile creation is available from the Rules tab.")
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
                        Image(systemName: appState.isGlassesConnected ? "camera.viewfinder" : "eyeglasses")
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.3))

                        if !appState.isGlassesConnected {
                            Text("Glasses not connected")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                            Text("Open the Meta AI app and make sure your Ray-Bans are on.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.4))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Button("Reconnect") {
                                glassesManager.reconnect()
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(Color.blue)
                            .clipShape(Capsule())
                        } else {
                            streamStatusOverlay
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var streamStatusOverlay: some View {
        switch streamManager.streamState {
        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange.opacity(0.8))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Retry") {
                    streamManager.startStream()
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Color.orange)
                .clipShape(Capsule())
            }
        case .stopped:
            VStack(spacing: 12) {
                Text("Stream stopped")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Button("Restart Stream") {
                    streamManager.stopStream()
                    // Wait 10s for the glasses camera service to fully release
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
        case .waitingForDevice:
            VStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("Waiting for glasses…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text("Make sure your Ray-Bans are on and camera sharing is active in Meta AI.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        default:
            VStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("Starting camera…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            ConnectionStatusPill(isConnected: appState.isGlassesConnected) {
                glassesManager.reconnect()
            }

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
            List {
                ForEach(appState.allProfiles) { profile in
                    Button {
                        Task {
                            await appState.setActiveProfile(profile)
                            detectionManager.setActiveProfile(profile)
                            showProfilePicker = false
                        }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(profile.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    TriggerTypeBadge(trigger: profile.triggerType)
                                }
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

                Button {
                    showProfilePicker = false
                    showCreateProfileComingSoon = true
                } label: {
                    Label("Create new profile", systemImage: "plus.circle")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
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

// MARK: - TriggerTypeBadge

private struct TriggerTypeBadge: View {
    let trigger: TriggerType

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var label: String {
        switch trigger {
        case .visionAI:        return "Vision AI"
        case .qrCode:          return "QR"
        case .textOCR:         return "OCR"
        case .objectDetection: return "Objects"
        case .faceRecognition: return "Faces"
        case .combined:        return "Multi"
        }
    }

    private var color: Color {
        switch trigger {
        case .visionAI:        return .blue
        case .qrCode:          return .green
        case .textOCR:         return .orange
        case .objectDetection: return .purple
        case .faceRecognition: return .pink
        case .combined:        return .gray
        }
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
