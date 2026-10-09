public enum ClockCounter {
    public static let writeTarget: UInt8 = 0x34
    public static let readTarget: UInt8 = 0x35
    public static let headerSize = 4
    public static let minimum = 0
    public static let maximum = 7

    public static func frame(count: Int, worldTimeHeader: [UInt8]) throws -> Frame {
        guard worldTimeHeader.count == headerSize else {
            throw ClockCounterError.badHeader
        }
        let clamped = min(maximum, max(minimum, count))
        let slot = " \(clamped)"
        let names = String(repeating: slot, count: 7)
        return Frame(target: writeTarget, payload: worldTimeHeader + Array(names.utf8))
    }
}

public enum ClockCounterError: Error, Equatable {
    case badHeader
}
