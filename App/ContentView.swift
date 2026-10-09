import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var ollee = OlleeClient.shared
    @State private var nameTag = ""
    @State private var lightColor = Color(red: 0.16, green: 0.82, blue: 0.75)
    @State private var counter = 0
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                connectionChip
                Image("Hero")
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel(
                        "Pixel orca leaping from the ocean, a digital watch strapped around the sun"
                    )
                nameTagRow
                Button("Beep", action: beep)
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                lightRow
                counterRow
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                credits
            }
            .padding()
        }
        .disabled(busy)
    }

    private var connectionChip: some View {
        Button(action: ollee.scan) {
            Label(chipTitle, systemImage: chipSymbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Scan or reconnect. Hold ALARM on Clock, or tap until LAP blinks.")
    }

    private var chipTitle: String {
        switch ollee.state {
        case .poweredOff:
            return "Bluetooth off"
        case .idle:
            return "Scan · hold ALARM or tap until LAP blinks"
        case .scanning:
            return "Scanning…"
        case .connecting:
            return "Connecting…"
        case .ready:
            return ollee.deviceName ?? "Connected"
        }
    }

    private var chipSymbol: String {
        switch ollee.state {
        case .poweredOff:
            return "antenna.radiowaves.left.and.right.slash"
        case .idle:
            return "dot.radiowaves.left.and.right"
        case .scanning, .connecting:
            return "waveform"
        case .ready:
            return "checkmark.circle.fill"
        }
    }

    private var nameTagRow: some View {
        HStack {
            TextField("Name tag", text: $nameTag)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .onChange(of: nameTag) { _, newValue in
                    if newValue.count > NameTag.maxLength {
                        nameTag = String(newValue.prefix(NameTag.maxLength))
                    }
                }
            Button("Set", action: setName)
                .disabled(busy)
        }
    }

    private var lightRow: some View {
        HStack {
            ColorPicker("Light", selection: $lightColor, supportsOpacity: false)
            Button("Show light", action: showLight)
                .disabled(busy)
        }
    }

    private var counterRow: some View {
        HStack {
            Stepper("Clock counter \(counter)", value: $counter, in: 0...7)
            Button("Set") { Task { await run { try await ollee.setClockCounter(counter) } } }
                .disabled(busy)
        }
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Arthur86000 / FreeOllee")
            Text("Ollee Watch by Ollee Technologies Inc.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }

    private func setName() {
        Task { await run { try await ollee.setNameTag(nameTag) } }
    }

    private func beep() {
        Task { await run { try await ollee.beep() } }
    }

    private func showLight() {
        let rgb = lightColor.rgbBytes
        Task { await run { try await ollee.showLight(red: rgb.red, green: rgb.green, blue: rgb.blue) } }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            message = ollee.lastError
        } catch OlleeError.lightUnpublished {
            message = "RGB backlight write is not in the published command catalogue."
        } catch OlleeError.notReady {
            message = "Watch is not connected. Hold ALARM on Clock, or tap until LAP blinks."
        } catch OlleeError.bluetoothOff {
            message = "Bluetooth is off."
        } catch OlleeError.timeout {
            message = "The watch did not answer in time."
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct RGBBytes {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}

private extension Color {
    var rgbBytes: RGBBytes {
        let ui = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGBBytes(
            red: UInt8(red * 255),
            green: UInt8(green * 255),
            blue: UInt8(blue * 255)
        )
    }
}

#Preview {
    ContentView()
}
