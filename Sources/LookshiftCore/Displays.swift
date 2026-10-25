import CoreGraphics

public typealias DisplayID = UInt32

public struct DisplayInfo: Equatable, Sendable {
    public let id: DisplayID
    /// Global Quartz coordinates (origin at the top-left of the main display).
    public let bounds: CGRect
    public let isBuiltin: Bool
    public let name: String

    public init(id: DisplayID, bounds: CGRect, isBuiltin: Bool, name: String) {
        self.id = id
        self.bounds = bounds
        self.isBuiltin = isBuiltin
        self.name = name
    }
}

extension CGRect {
    public var center: CGPoint { CGPoint(x: midX, y: midY) }
}
