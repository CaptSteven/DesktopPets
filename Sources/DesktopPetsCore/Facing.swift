/// Which way the sprite faces. Left-facing frames are drawn by flipping the right-facing art.
public enum Facing: String, Equatable {
    case left
    case right

    public var isFlipped: Bool { self == .left }

    public init(fromX: Double, toX: Double) {
        self = toX < fromX ? .left : .right
    }
}
