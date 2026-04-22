import SwiftUI

// LiveDetectionView is superseded by CaptureView (in ContentView.swift) as of Task 7.
// Kept for reference; not part of the active navigation graph.

struct LiveDetectionView: View {
    @EnvironmentObject private var detectionManager: HealthDetectionManager

    let onDisconnect: () -> Void

    @StateObject private var streamManager = CameraStreamManager()

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let frame = streamManager.lastFrame {
                    Image(uiImage: frame).resizable().scaledToFill()
                } else {
                    Color.black
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
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

                Spacer()

                if let analysis = detectionManager.lastAnalysis {
                    VStack(alignment: .leading, spacing: 12) {
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
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }

                switch detectionManager.captureState {
                case .analyzing:
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Analysing…").font(.footnote).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
                case .error(let message):
                    Text(message).font(.caption).foregroundStyle(.red.opacity(0.9)).padding(.bottom, 12)
                default:
                    Text("Point glasses at food or your monitor")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 12)
                }
            }
        }
        .task {
            streamManager.frameDelegate = detectionManager
            streamManager.startStream()
        }
        .onDisappear {
            streamManager.stopStream()
        }
    }
}
