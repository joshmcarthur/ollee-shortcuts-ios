import AppIntents
import SwiftUI

struct SetOlleeTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Ollee text"
    static var description = IntentDescription("Push up to 6 ASCII characters to the Ollee name tag.")

    @Parameter(title: "Text")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        try await OlleeClient.shared.setNameTag(text)
        return .result()
    }
}

struct BeepOlleeIntent: AppIntent {
    static var title: LocalizedStringResource = "Beep Ollee"
    static var description = IntentDescription("Play the Ollee chime preview without saving a new alarm.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try await OlleeClient.shared.beep()
        return .result()
    }
}

private struct RGBBytes {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}

enum OlleeLightPreset: String, AppEnum {
    case red, green, blue, cyan, white, orange

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ollee light")
    static var caseDisplayRepresentations: [OlleeLightPreset: DisplayRepresentation] = [
        .red: "Red",
        .green: "Green",
        .blue: "Blue",
        .cyan: "Cyan",
        .white: "White",
        .orange: "Orange",
    ]

    fileprivate var rgb: RGBBytes {
        switch self {
        case .red: return RGBBytes(red: 255, green: 40, blue: 40)
        case .green: return RGBBytes(red: 40, green: 220, blue: 80)
        case .blue: return RGBBytes(red: 40, green: 80, blue: 255)
        case .cyan: return RGBBytes(red: 40, green: 210, blue: 190)
        case .white: return RGBBytes(red: 255, green: 255, blue: 255)
        case .orange: return RGBBytes(red: 255, green: 140, blue: 40)
        }
    }
}

struct SetOlleeLightIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Ollee light"
    static var description = IntentDescription("Set RGB color and illuminate. Fails until the register is published.")

    @Parameter(title: "Color")
    var color: OlleeLightPreset

    @MainActor
    func perform() async throws -> some IntentResult {
        try await OlleeClient.shared.showLight(
            red: color.rgb.red,
            green: color.rgb.green,
            blue: color.rgb.blue
        )
        return .result()
    }
}

struct SetOlleeClockCounterIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Ollee clock counter"
    static var description = IntentDescription("Write an integer 0–7 to the Clock-face weekday badge.")

    @Parameter(title: "Count")
    var count: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        try await OlleeClient.shared.setClockCounter(count)
        return .result()
    }
}

struct OlleeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetOlleeTextIntent(),
            phrases: [
                "Set Ollee text \(\.$text) with \(.applicationName)",
            ],
            shortTitle: "Set Ollee text",
            systemImageName: "textformat"
        )
        AppShortcut(
            intent: BeepOlleeIntent(),
            phrases: [
                "Beep \(.applicationName)",
            ],
            shortTitle: "Beep Ollee",
            systemImageName: "bell"
        )
        AppShortcut(
            intent: SetOlleeLightIntent(),
            phrases: [
                "Set Ollee light \(\.$color) with \(.applicationName)",
            ],
            shortTitle: "Set Ollee light",
            systemImageName: "lightbulb"
        )
        AppShortcut(
            intent: SetOlleeClockCounterIntent(),
            phrases: [
                "Set Ollee clock counter \(\.$count) with \(.applicationName)",
            ],
            shortTitle: "Set clock counter",
            systemImageName: "number"
        )
    }
}
