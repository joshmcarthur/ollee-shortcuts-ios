/// RGB/backlight write is not in the published command catalogue
/// (Gadgetbridge Ollee / PR 6411 lineage and FreeOllee-Faces protocol notes).
public enum Light {
    public static let registerPublished = false

    public static func show(red _: UInt8, green _: UInt8, blue _: UInt8) throws -> Frame {
        throw LightError.registerUnpublished
    }
}

public enum LightError: Error, Equatable {
    case registerUnpublished
}
