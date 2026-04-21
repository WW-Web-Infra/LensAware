import Foundation
import MWDATCore

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

    init() {
        // Always-on observers — never miss a state change
        startObservingRegistration()
        startObservingDevices()
    }

    deinit {
        registrationTask?.cancel()
        devicesTask?.cancel()
    }

    // MARK: - Public API

    func startConnection() {
        if case .searching = connectionState { return }
        if case .connected = connectionState { return }

        connectionState = .searching

        Task {
            let current = wearables.registrationState

            switch current {
            case .registered:
                connectionState = .connected(wearables.devices.first ?? "glasses")
                return

            case .unavailable:
                connectionState = .error(
                    "SDK unavailable. Ensure Developer Mode is on in the Meta AI app."
                )
                return

            case .registering:
                try? await wearables.startUnregistration()
                try? await Task.sleep(nanoseconds: 2_000_000_000)

            case .available:
                break

            @unknown default:
                break
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000)

            do {
                try await wearables.startRegistration()
            } catch {
                connectionState = .error("\(error)")
            }
        }
    }

    func handleUrl(_ url: URL) async {
        do {
            _ = try await wearables.handleUrl(url)
            connectionState = .connected(wearables.devices.first ?? "glasses")
        } catch {
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

    func disconnect() {
        connectionState = .disconnected
        availableDevices = []
        Task { try? await wearables.startUnregistration() }
    }

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var connectedDeviceID: DeviceIdentifier? {
        if case .connected(let id) = connectionState { return id }
        return nil
    }

    // MARK: - Always-on observers

    private func startObservingRegistration() {
        registrationTask = Task { [weak self] in
            guard let self else { return }
            for await state in wearables.registrationStateStream() {
                guard !Task.isCancelled else { break }
                self.registrationState = state
                if state == .unavailable || state == .available {
                    if case .connected = self.connectionState {
                        self.connectionState = .disconnected
                    }
                }
            }
        }
    }

    private func startObservingDevices() {
        devicesTask = Task { [weak self] in
            guard let self else { return }
            for await devices in wearables.devicesStream() {
                guard !Task.isCancelled else { break }
                self.availableDevices = devices
                if let first = devices.first {
                    self.connectionState = .connected(first)
                } else if case .connected = self.connectionState {
                    self.connectionState = .searching
                }
            }
        }
    }
}
