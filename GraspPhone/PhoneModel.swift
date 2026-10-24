import CoreImage
import GraspKit
import Observation
import UIKit

/// The phone's side of Grasp: camera in, frames out to the Mac.
@MainActor @Observable
final class PhoneModel {
    enum CameraStatus {
        case starting, running, denied
        /// The simulator has no camera, so it sends a generated test frame instead.
        case testPattern
    }

    private(set) var linkState = MultipeerLink.State.searching
    private(set) var cameraStatus = CameraStatus.starting
    private(set) var roundTripMs: Double?
    private(set) var capturesSent = 0
    var isLive = true {
        didSet { sender.setLive(isLive) }
    }

    @ObservationIgnored let camera = PhoneCamera()
    @ObservationIgnored private let link = MultipeerLink(role: .guest, displayName: UIDevice.current.name)
    @ObservationIgnored private lazy var sender = FrameSender(link: link)
    @ObservationIgnored private var testPattern: DispatchSourceTimer?
    @ObservationIgnored private var started = false

    var isConnected: Bool {
        if case .connected = linkState { return true }
        return false
    }

    func start() async {
        guard !started else { return }
        started = true
        let sender = self.sender

        link.onState = { [weak self] state in
            self?.linkState = state
            if case .connected = state {} else { self?.roundTripMs = nil }
        }
        link.onMessage = { [weak self] message in
            guard case .received(let frameID, let sentAt) = message else { return }
            self?.roundTripMs = sender.acknowledge(frameID: frameID, sentAt: sentAt)
        }
        link.start()

        #if targetEnvironment(simulator)
        startTestPattern(into: sender)
        cameraStatus = .testPattern
        #else
        camera.onFrame = { buffer in sender.offer(CIImage(cvPixelBuffer: buffer)) }
        cameraStatus = await camera.start() ? .running : .denied
        #endif
    }

    func capture() {
        sender.requestCapture()
        capturesSent += 1
    }

    /// A numbered, color-cycling frame ten times a second, so the link can be tested without a camera.
    private func startTestPattern(into sender: FrameSender) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "grasp.phone.testpattern"))
        var count = 0
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler {
            count += 1
            let size = CGSize(width: 1080, height: 1440)
            let image = UIGraphicsImageRenderer(size: size, format: .init(for: .init(displayScale: 1))).image { context in
                UIColor(hue: CGFloat(count % 100) / 100, saturation: 0.5, brightness: 0.6, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let text = "Grasp test frame\n#\(count)" as NSString
                text.draw(
                    in: CGRect(x: 80, y: 560, width: size.width - 160, height: 400),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 110), .foregroundColor: UIColor.white]
                )
            }
            if let cgImage = image.cgImage {
                sender.offer(CIImage(cgImage: cgImage))
            }
        }
        timer.resume()
        testPattern = timer
    }
}
