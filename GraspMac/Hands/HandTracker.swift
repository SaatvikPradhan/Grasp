import CoreMedia
import GraspKit
import Vision

/// Finds up to two hands in a webcam frame with Vision hand pose.
final class HandTracker {
    /// Joints Vision is less sure of than this are dropped.
    var minimumConfidence: Float = 0.2

    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()

    func detect(in buffer: CMSampleBuffer) -> HandFrame? {
        guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { return nil }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let hands = (request.results ?? []).compactMap(sample(from:))
        return HandFrame(
            hands: hands,
            time: CMSampleBufferGetPresentationTimeStamp(buffer).seconds,
            aspect: Double(CVPixelBufferGetWidth(pixels)) / Double(CVPixelBufferGetHeight(pixels))
        )
    }

    private func sample(from observation: VNHumanHandPoseObservation) -> HandSample? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        var joints: [HandJoint: CGPoint] = [:]
        for (name, joint) in Self.joints {
            guard let point = points[name], point.confidence >= minimumConfidence else { continue }
            // Vision's origin is the bottom left, and webcam frames are not mirrored.
            joints[joint] = CGPoint(x: 1 - point.location.x, y: 1 - point.location.y)
        }
        let chirality: HandChirality = switch observation.chirality {
        case .left: .left
        case .right: .right
        default: .unknown
        }
        return HandSample(chirality: chirality, joints: joints)
    }

    private static let joints: [(VNHumanHandPoseObservation.JointName, HandJoint)] = [
        (.wrist, .wrist),
        (.thumbCMC, .thumbCMC), (.thumbMP, .thumbMP), (.thumbIP, .thumbIP), (.thumbTip, .thumbTip),
        (.indexMCP, .indexMCP), (.indexPIP, .indexPIP), (.indexDIP, .indexDIP), (.indexTip, .indexTip),
        (.middleMCP, .middleMCP), (.middlePIP, .middlePIP), (.middleDIP, .middleDIP), (.middleTip, .middleTip),
        (.ringMCP, .ringMCP), (.ringPIP, .ringPIP), (.ringDIP, .ringDIP), (.ringTip, .ringTip),
        (.littleMCP, .littleMCP), (.littlePIP, .littlePIP), (.littleDIP, .littleDIP), (.littleTip, .littleTip),
    ]
}
