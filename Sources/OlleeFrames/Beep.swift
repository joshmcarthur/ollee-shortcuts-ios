public enum Beep {
    public static let writeTarget: UInt8 = 0x25
    public static let readTarget: UInt8 = 0x2B
    public static let playNowOffset = 8
    public static let writeLength = 13
    public static let readLength = 12

    public static func previewFrame(storedReadback: [UInt8]?) throws -> Frame {
        let record: [UInt8]
        if let stored = storedReadback {
            switch stored.count {
            case readLength:
                record = Array(stored.prefix(playNowOffset)) + [1] + Array(stored[playNowOffset...])
            case writeLength:
                var copy = stored
                copy[playNowOffset] = 1
                record = copy
            default:
                throw BeepError.badRecord
            }
        } else {
            var empty = [UInt8](repeating: 0, count: writeLength)
            empty[playNowOffset] = 1
            empty[writeLength - 1] = 0xFF
            record = empty
        }
        return Frame(target: writeTarget, payload: record)
    }
}

public enum BeepError: Error, Equatable {
    case badRecord
}
