import Foundation
import UIKit
import MWDATCore
import MWDATCamera
import os.log

private let streamLog = Logger(subsystem: "com.lensaware", category: "CameraStream")

// MARK: - Stream state

enum StreamState: Equatable {
    case idle
    case starting
    case waitingForDevice
    case streaming
    case paused
    case stopped
    case error(String)
}

// MARK: - Frame delegate

protocol CameraFrameDelegate: AnyObject, Sendable {
    func didReceiveFrame(_ imageData: Data)
}

// MARK: - CameraStreamManager

@MainActor
final class CameraStreamManager: ObservableObject {
    @Published private(set) var streamState: StreamState = .idle
    @Published private(set) var lastFrame: UIImage?

    weak var frameDelegate: (any CameraFrameDelegate)?

    private var streamSession: StreamSession?
    private var stateToken: (any AnyListenerToken)?
    private var frameToken: (any AnyListenerToken)?
    private var errorToken: (any AnyListenerToken)?

    private var lastProcessedTime: Date = .distantPast
    private let processInterval: TimeInterval = 3.0

    // Watchdog: detects the silent camera-locked state (recv bitrate: 0 indefinitely).
    // When SDK reports .streaming but no frames arrive within 10s, the glasses
    // camera is locked. We stop the session so the UI shows the Restart button.
    private var noFramesWatchdog: Task<Void, Never>?
    private var hasReceivedFirstFrame = false

    // MARK: - Public API

    func startStream() {
        switch streamState {
        case .idle, .stopped, .error: break
        default:
            streamLog.debug("startStream() skipped — already in state: \(String(describing: self.streamState))")
            return
        }

        streamLog.info("startStream() called — entering .starting")
        streamState = .starting
        lastProcessedTime = .distantPast
        hasReceivedFirstFrame = false

        let wearables = Wearables.shared
        let regState  = wearables.registrationState
        streamLog.info("SDK registrationState at stream start: \(String(describing: regState))")

        let devices = wearables.devices
        streamLog.info("SDK devices at stream start: \(devices)")

        let selector = AutoDeviceSelector(wearables: wearables)
        let config = StreamSessionConfig(videoCodec: .raw, resolution: .low, frameRate: 15)
        streamLog.debug("StreamSessionConfig: codec=raw resolution=low fps=15")
        let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
        streamSession = session

        stateToken = session.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                streamLog.info("Session state → \(String(describing: state))")
                switch state {
                case .streaming:
                    self.streamState = .streaming
                    self.startNoFramesWatchdog()
                case .waitingForDevice:
                    streamLog.warning("waitingForDevice — glasses not seen by SDK yet")
                    self.streamState = .waitingForDevice
                case .starting:         self.streamState = .starting
                case .paused:           self.streamState = .paused
                case .stopped:
                    self.noFramesWatchdog?.cancel()
                    self.streamState = .stopped
                    self.lastFrame = nil
                case .stopping:         break
                @unknown default:       break
                }
            }
        }

        // frame.makeUIImage() must be called synchronously before entering Task
        frameToken = session.videoFramePublisher.listen { [weak self] frame in
            guard let self else { return }
            let image = frame.makeUIImage()
            Task { @MainActor [weak self] in
                guard let self, let image else { return }
                if !self.hasReceivedFirstFrame {
                    self.hasReceivedFirstFrame = true
                    self.noFramesWatchdog?.cancel()
                    streamLog.info("First frame received — \(Int(image.size.width))×\(Int(image.size.height))")
                }
                self.lastFrame = image
                self.processFrameIfNeeded(image)
            }
        }

        errorToken = session.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                streamLog.error("Stream error: \(error)")
                self?.noFramesWatchdog?.cancel()
                self?.streamState = .error(error.localizedDescription)
            }
        }

        Task {
            let wearables = Wearables.shared
            do {
                var status = try await wearables.checkPermissionStatus(.camera)
                if status != .granted {
                    status = try await wearables.requestPermission(.camera)
                }
                guard status == .granted else {
                    streamLog.error("Camera permission denied in Meta AI — aborting stream start")
                    streamState = .error("Camera permission denied in Meta AI.")
                    return
                }
            } catch {
                // XPC relay is cold — proceed anyway.
                // The caller is responsible for warming the relay via requestPermission
                // before startStream() is invoked (reconnect() handles this).
                streamLog.warning("checkPermissionStatus threw \(error) — starting anyway")
            }
            streamLog.info("Calling session.start()")
            await session.start()
            streamLog.info("session.start() returned")
        }
    }

    func stopStream() {
        noFramesWatchdog?.cancel()
        noFramesWatchdog = nil

        let session = streamSession
        let st = stateToken
        let ft = frameToken
        let et = errorToken

        streamSession = nil
        stateToken = nil
        frameToken = nil
        errorToken = nil
        lastFrame = nil
        streamState = .stopped

        Task {
            await st?.cancel()
            await ft?.cancel()
            await et?.cancel()
            await session?.stop()
        }
    }

    // MARK: - Watchdog

    private func startNoFramesWatchdog() {
        noFramesWatchdog?.cancel()
        streamLog.debug("Watchdog started — will fire in 10s if no frame arrives")
        noFramesWatchdog = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, !hasReceivedFirstFrame else { return }
            streamLog.error("Watchdog fired — SDK reported .streaming but no frames in 10s (camera locked?). Stopping.")
            stopStream()
        }
    }

    var isStreaming: Bool { streamState == .streaming }

    // MARK: - Private

    private func processFrameIfNeeded(_ image: UIImage) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessedTime) >= processInterval else { return }
        lastProcessedTime = now
        guard let imageData = resizedJPEG(from: image) else { return }
        print("[LensAware] Frame dispatched — \(imageData.count / 1024)KB")
        frameDelegate?.didReceiveFrame(imageData)
    }

    private func resizedJPEG(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1568
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

// MARK: - StreamSessionError description

extension StreamSessionError {
    var localizedDescription: String {
        switch self {
        case .permissionDenied:     return "Camera permission denied."
        case .deviceNotFound:       return "Glasses not found."
        case .deviceNotConnected:   return "Glasses disconnected."
        case .hingesClosed:         return "Open the glasses hinges to stream."
        case .thermalCritical:      return "Device too hot to stream."
        case .timeout:              return "Stream timed out."
        default:                    return "Streaming error."
        }
    }
}
