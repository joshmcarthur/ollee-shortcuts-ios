import AppIntents
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var ollee = OlleeClient.shared
    @State private var nameTag = ""
    @State private var lightColor = Color(red: 0.16, green: 0.82, blue: 0.75)
    @State private var counter = 0
    @State private var busy = false
    @State private var message: String?

    private var linked: Bool { ollee.state == .ready }

    var body: some View {
        Form {
            deviceSection
            nameTagSection
            beepSection
            lightSection
            counterSection
            Section {
                ShortcutsLink()
            }
            if let banner = message ?? ollee.lastError {
                Section {
                    Text(banner)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                credits
            }
        }
        .disabled(busy)
    }

    private var deviceSection: some View {
        Section {
            Button(action: ollee.scan) {
                Label(chipTitle, systemImage: chipSymbol)
            }
            .accessibilityHint("Scan or pick an Ollee. Hold ALARM on Clock, or tap until LAP blinks.")
            if ollee.state == .scanning {
                ForEach(ollee.candidates) { candidate in
                    Button {
                        ollee.connect(to: candidate.id)
                    } label: {
                        HStack {
                            Text(candidate.name)
                            Spacer()
                            if candidate.isLastUsed {
                                Text("last used")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Ollee")
        } footer: {
            Text("Hold ALARM on Clock, or tap until LAP blinks.")
        }
    }

    private var chipTitle: String {
        switch ollee.state {
        case .poweredOff:
            return "Bluetooth off"
        case .idle:
            return "Scan"
        case .scanning:
            return "Scanning…"
        case .connecting:
            return "Connecting…"
        case .ready:
            return ollee.deviceName ?? "Ollee"
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

    private var nameTagSection: some View {
        Section("Name tag") {
            TextField("Name tag", text: $nameTag)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .onChange(of: nameTag) { _, newValue in
                    if newValue.count > NameTag.maxLength {
                        nameTag = String(newValue.prefix(NameTag.maxLength))
                    }
                }
            Button("Set", action: setName)
                .disabled(!linked)
        }
    }

    private var beepSection: some View {
        Section("Beep") {
            Button("Beep", action: beep)
                .disabled(!linked)
        }
    }

    private var lightSection: some View {
        Section("Light") {
            ColorPicker("Color", selection: $lightColor, supportsOpacity: false)
            Button("Show light", action: showLight)
                .disabled(!linked)
        }
    }

    private var counterSection: some View {
        Section("Clock counter") {
            Stepper("Clock counter \(counter)", value: $counter, in: 0...7)
            Button("Set") { Task { await run { try await ollee.setClockCounter(counter) } } }
                .disabled(!linked)
        }
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Arthur86000 / FreeOllee")
            Text("Ollee Watch by Ollee Technologies Inc.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
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
            message = nil
        } catch OlleeError.lightUnpublished {
            message = "RGB backlight write is not in the published command catalogue."
        } catch OlleeError.notReady {
            message = "Ollee is not connected. Hold ALARM on Clock, or tap until LAP blinks."
        } catch OlleeError.timeout {
            message = "Ollee did not answer in time."
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
