import CoreGraphics

/// The 21 hand points Vision reports.
public enum HandJoint: String, CaseIterable, Hashable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    /// Joint chains to draw as bones in a debug skeleton.
    public static let chains: [[HandJoint]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip],
        [.indexMCP, .middleMCP, .ringMCP, .littleMCP],
    ]
}

public enum HandChirality: Sendable, Equatable {
    case left, right, unknown
}

/// One hand in one camera frame.
///
/// Points are normalized 0...1 with the origin at the top left, already mirrored so that
/// moving your hand to your right moves it right on screen. Joints Vision was unsure of are left out.
public struct HandSample: Sendable, Equatable {
    public var chirality: HandChirality
    public var joints: [HandJoint: CGPoint]

    public init(chirality: HandChirality = .unknown, joints: [HandJoint: CGPoint]) {
        self.chirality = chirality
        self.joints = joints
    }
}

/// Every hand seen in one camera frame.
public struct HandFrame: Sendable {
    public var hands: [HandSample]
    /// Capture time in seconds, from any monotonic clock.
    public var time: Double
    /// Image width over height, so distances and angles can be measured in square units.
    public var aspect: Double

    public init(hands: [HandSample], time: Double, aspect: Double) {
        self.hands = hands
        self.time = time
        self.aspect = aspect
    }
}
