import SwiftUI

// MARK: - App navigation states

enum AppScreen {
    case connection
    case live
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
                ConnectionView(onConnected: { currentScreen = .live })

            case .live:
                LiveDetectionView(
                    onDisconnect: {
                        glassesManager.disconnect()
                        currentScreen = .connection
                    }
                )
            }
        }
    }
}
