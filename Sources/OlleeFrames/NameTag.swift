public enum NameTag {
    public static let maxLength = 6
    public static let target: UInt8 = 0x2F

    public static func frame(text: String) throws -> Frame {
        guard text.unicodeScalars.allSatisfy(\.isASCII) else {
            throw NameTagError.notASCII
        }
        let clamped = String(text.prefix(maxLength))
        let padded = clamped + String(repeating: " ", count: maxLength - clamped.count)
        return Frame(target: target, payload: Array(padded.utf8))
    }
}

public enum NameTagError: Error, Equatable {
    case notASCII
}
