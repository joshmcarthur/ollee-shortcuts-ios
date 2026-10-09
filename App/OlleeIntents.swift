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

    var rgb: (UInt8, UInt8, UInt8) {
        switch self {
        case .red: return (255, 40, 40)
        case .green: return (40, 220, 80)
        case .blue: return (40, 80, 255)
        case .cyan: return (40, 210, 190)
        case .white: return (255, 255, 255)
        case .orange: return (255, 140, 40)
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
        try await OlleeClient.shared.showLight(red: color.rgb.0, green: color.rgb.1, blue: color.rgb.2)
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
