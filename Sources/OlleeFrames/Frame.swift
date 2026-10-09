/// One Ollee NUS frame: `00 LEN AA 55 CRC 02 TARGET PAYLOAD`.
public struct Frame: Equatable, Sendable {
    public var command: UInt8
    public var target: UInt8
    public var payload: [UInt8]

    public init(target: UInt8, payload: [UInt8], command: UInt8 = 0x02) {
        self.command = command
        self.target = target
        self.payload = payload
    }

    public var inner: [UInt8] {
        [command, target] + payload
    }

    public func encoded() -> [UInt8] {
        let body = inner
        let crc = CRC16.ccittFalse(body)
        let length = body.count + 4
        precondition(length <= 0xFF, "frame exceeds single-byte LEN")
        return [
            0x00,
            UInt8(length),
            0xAA,
            0x55,
            UInt8(crc >> 8),
            UInt8(crc & 0xFF),
        ] + body
    }

    public static func parse(_ bytes: [UInt8]) -> Frame? {
        guard bytes.count >= 8, bytes[2] == 0xAA, bytes[3] == 0x55 else {
            return nil
        }
        let inner = Array(bytes[6...])
        let crc = (UInt16(bytes[4]) << 8) | UInt16(bytes[5])
        guard CRC16.ccittFalse(inner) == crc else {
            return nil
        }
        return Frame(target: inner[1], payload: Array(inner.dropFirst(2)), command: inner[0])
    }

    public static func attChunks(_ bytes: [UInt8], size: Int = 20) -> [[UInt8]] {
        guard size > 0, !bytes.isEmpty else {
            return bytes.isEmpty ? [] : [bytes]
        }
        return stride(from: 0, to: bytes.count, by: size).map { start in
            Array(bytes[start..<min(start + size, bytes.count)])
        }
    }

    public static func read(target: UInt8) -> Frame {
        Frame(target: target, payload: [])
    }

    /// Reassembles notify fragments into frames. Drains every complete frame in the buffer.
    struct Assembler {
        private var buffer: [UInt8] = []

        mutating func push(_ chunk: [UInt8]) -> [Frame] {
            buffer += chunk
            var frames: [Frame] = []
            while buffer.count >= 2 {
                let total = 2 + Int(buffer[1])
                guard buffer.count >= total else { break }
                let bytes = Array(buffer.prefix(total))
                buffer.removeFirst(total)
                if let frame = Frame.parse(bytes) {
                    frames.append(frame)
                }
            }
            return frames
        }
    }
}
