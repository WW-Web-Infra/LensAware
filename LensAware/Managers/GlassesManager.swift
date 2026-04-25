import Foundation
import MWDATCore
import os.log

private let connLog = Logger(subsystem: "com.lensaware", category: "GlassesManager")

// MARK: - Connection state

enum GlassesConnectionState: Equatable {
    case disconnected
    case searching
    case connected(DeviceIdentifier)
    case error(String)
}

// MARK: - GlassesManager

@MainActor
final class GlassesManager: ObservableObject {
    @Published private(set) var connectionState: GlassesConnectionState = .disconnected
    @Published private(set) var registrationState: RegistrationState = .unavailable
    @Published private(set) var cameraPermission: PermissionStatus = .denied
    @Published private(set) var availableDevices: [DeviceIdentifier] = []

    private let wearables = Wearables.shared
    private var registrationTask: Task<Void, Never>?
    private var devicesTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    init() {
        // Always-on observers — never miss a state change
        startObservingRegistration()
        startObservingDevices()
    }

    deinit {
        registrationTask?.cancel()
        devicesTask?.cancel()
        reconnectTask?.cancel()
    }

    // MARK: - Public API

    func startConnection() {
        if case .searching = connectionState { return }
        if case .connected = connectionState { return }

        connectionState = .searching
        connLog.info("startConnection() — registrationState=\(String(describing: self.wearables.registrationState)) devices=\(self.wearables.devices)")

        Task {
            let current = wearables.registrationState
            connLog.info("startConnection Task — registrationState=\(String(describing: current))")

            switch current {
            case .registered:
                // Mirror FloraLens exactly — trust registration state and connect immediately.
                // AutoDeviceSelector handles actual device discovery during streaming.
                let device = wearables.devices.first ?? "glasses"
                connLog.info("registered — connecting as \(device)")
                connectionState = .connected(device)
                return

            case .unavailable:
                connLog.error("SDK unavailable")
                connectionState = .error("SDK unavailable. Ensure Developer Mode is on in the Meta AI app.")
                return

            case .registering:
                connLog.warning("SDK in .registering — unregistering first")
                try? await wearables.startUnregistration()
                try? await Task.sleep(nanoseconds: 2_000_000_000)

            case .available:
                connLog.info("SDK .available — calling startRegistration()")

            @unknown default:
                break
            }

            do {
                try await wearables.startRegistration()
                connLog.info("startRegistration() completed")
            } catch {
                connLog.error("startRegistration() failed: \(error)")
                connectionState = .error("\(error)")
            }
        }
    }

    func handleUrl(_ url: URL) async {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let action = components?.queryItems?.first(where: { $0.name == "metaWearablesAction" })?.value
        connLog.info("handleUrl called: action=\(action ?? "unknown") url=\(url.absoluteString)")

        do {
            _ = try await wearables.handleUrl(url)
            connLog.info("wearables.handleUrl completed — action=\(action ?? "unknown")")

            guard action == "register" else {
                // Unregister deep link — registrationStateStream will update state.
                // Do not set .connected here; that causes a spurious connect/disconnect cycle.
                connLog.info("handleUrl: unregister processed, letting registrationStateStream drive state")
                return
            }

            // After the register deep link, Meta AI just backgrounded. Its XPC service needs
            // a few seconds to start in background mode before wearables.devices is populated.
            connLog.info("handleUrl: register complete — waiting 3s for XPC service to start")
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            let device = wearables.devices.first ?? "glasses"
            connLog.info("handleUrl: after wait — devices=\(self.wearables.devices) → connecting as \(device)")
            startObservingDevices()
            connectionState = .connected(device)

        } catch {
            connLog.error("handleUrl failed: \(error)")
            connectionState = .error(error.localizedDescription)
        }
    }

    func requestCameraAccess() async {
        do {
            cameraPermission = try await wearables.checkPermissionStatus(.camera)
            if cameraPermission != .granted {
                cameraPermission = try await wearables.requestPermission(.camera)
            }
        } catch {
            // Non-fatal — stream will surface permission errors
        }
    }

    // Opens Meta AI to warm the XPC relay, then polls wearables.devices directly.
    // devicesStream is a change-stream: a fresh iterator won't emit the current device
    // list unless a connect/disconnect event fires. Direct polling catches the warm-up
    // window reliably regardless of whether an event fires.
    func reconnect() {
        reconnectTask?.cancel()
        connectionState = .searching
        availableDevices = []
        registrationTask?.cancel()
        devicesTask?.cancel()
        startObservingRegistration()
        startObservingDevices()
        connLog.info("reconnect() — restarting observers, calling startConnection()")
        startConnection()
    }

    // Restart the devicesStream subscription on a now-warm XPC relay.
    func refreshDeviceObserver() {
        devicesTask?.cancel()
        startObservingDevices()
    }

    // Nuclear option: forces a fresh Meta AI session via startRegistration().
    // Only use when startConnection() can't recover (e.g. stream stuck in waitingForDevice).
    func reregister() {
        reconnectTask?.cancel()
        connectionState = .searching
        connLog.info("reregister() — opening Meta AI for fresh session")
        Task {
            do {
                try await wearables.startRegistration()
                connLog.info("reregister() — startRegistration returned, waiting for handleUrl() deep link")
            } catch {
                connLog.error("reregister() — startRegistration failed: \(error)")
                connectionState = .error("\(error)")
            }
        }
    }

    func disconnect() {
        reconnectTask?.cancel()
        connectionState = .disconnected
        availableDevices = []
    }

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var connectedDeviceID: DeviceIdentifier? {
        if case .connected(let id) = connectionState { return id }
        return nil
    }

    // MARK: - Helpers

    // Waits for registrationStateStream to emit the target state, with a 5s timeout.
    private func waitForRegistrationState(_ target: RegistrationState) async {
        if wearables.registrationState == target { return }
        let deadline = Date().addingTimeInterval(5)
        for await state in wearables.registrationStateStream() {
            if state == target { return }
            if Date() > deadline { return }
        }
    }

    // MARK: - Always-on observers

    private func startObservingRegistration() {
        registrationTask = Task { [weak self] in
            guard let self else { return }
            for await state in wearables.registrationStateStream() {
                guard !Task.isCancelled else { break }
                connLog.info("registrationStateStream → \(String(describing: state))")
                self.registrationState = state
                switch state {
                case .unavailable, .available:
                    if case .connected = self.connectionState {
                        self.connectionState = .disconnected
                    }
                default:
                    break
                }
            }
        }
    }

    private func startObservingDevices() {
        devicesTask = Task { [weak self] in
            guard let self else { return }
            for await devices in wearables.devicesStream() {
                guard !Task.isCancelled else { break }
                connLog.info("devicesStream → \(devices) (connectionState=\(String(describing: self.connectionState)))")
                self.availableDevices = devices
                if let first = devices.first {
                    switch self.connectionState {
                    case .searching, .connected:
                        connLog.info("devicesStream: promoting to .connected(\(first))")
                        self.connectionState = .connected(first)
                    default:
                        connLog.info("devicesStream: device seen but state=\(String(describing: self.connectionState)) — ignoring")
                    }
                } else if case .connected = self.connectionState {
                    connLog.info("devicesStream: empty list while connected — reverting to .searching")
                    self.connectionState = .searching
                }
            }
        }
    }
}
