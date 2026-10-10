import Foundation

/// Discovery hints for an Ollee radio. Nordic UART is shared hardware, so a match is
/// a candidate to pick, not a reason to connect automatically.
public enum OlleeAdvertisement: Equatable {
    case likelyOllee
    case nordicUART

    public static let nordicUARTService = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"

    public var rank: Int {
        switch self {
        case .likelyOllee:
            return 0
        case .nordicUART:
            return 1
        }
    }

    public static func match(name: String, advertisedServices: [String]) -> OlleeAdvertisement? {
        if looksLikeOlleeName(name) { return .likelyOllee }
        if advertisesNordicUART(advertisedServices) { return .nordicUART }
        return nil
    }

    public static func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed UART" : trimmed
    }

    private static func looksLikeOlleeName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("ollee") { return true }
        return trimmed.compare("CRS", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static func advertisesNordicUART(_ services: [String]) -> Bool {
        services.contains { $0.caseInsensitiveCompare(nordicUARTService) == .orderedSame }
    }
}
