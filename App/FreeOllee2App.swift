import SwiftUI

@main
struct FreeOllee2App: App {
    @StateObject private var ollee = OlleeClient.shared

    var body: some Scene {
        WindowGroup {
            Text(status)
                .padding()
        }
    }

    private var status: String {
        switch ollee.state {
        case .poweredOff:
            return "Bluetooth is off"
        case .idle:
            return "Hold ALARM on Clock, or tap until LAP blinks"
        case .scanning:
            return "Scanning…"
        case .connecting:
            return "Connecting…"
        case .ready:
            return ollee.deviceName ?? "Connected"
        }
    }
}
