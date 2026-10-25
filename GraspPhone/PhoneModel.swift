import CoreImage
import GraspKit
import Observation
import UIKit

/// A capture as the phone shows it: the photo, then the Mac's boxes once it has read it.
struct PhoneScan: Identifiable {
    let id: UUID
    var image: UIImage
    /// Nil until the Mac answers.
    var highlights: [LinkHighlight]?
}

/// The phone's side of Grasp: camera in, frames out to the Mac, highlights back.
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
    /// The last capture, shown over the camera until dismissed.
    var scan: PhoneScan?
    /// Bumped on every capture, to flash the screen.
    private(set) var flashCount = 0
    var isLive = true {
        didSet { sender.setLive(isLive) }
    }
    /// Flick the phone to send. Remembered between launches; off stops all motion sensing.
    var isFlickEnabled = UserDefaults.standard.object(forKey: "flickToSend") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isFlickEnabled, forKey: "flickToSend")
            if isFlickEnabled { fling.start() } else { fling.stop() }
        }
    }

    @ObservationIgnored let camera = PhoneCamera()
    @ObservationIgnored private let link = MultipeerLink(role: .guest, displayName: UIDevice.current.name)
    @ObservationIgnored private lazy var sender = FrameSender(link: link)
    @ObservationIgnored private let fling = FlingDetector()
    @ObservationIgnored private var testPattern: DispatchSourceTimer?
    /// Recent captures, so the Mac can bring one back up with a spot boxed (hovering a number,
    /// answering a question).
    @ObservationIgnored private var captures: [(id: UUID, image: UIImage)] = []
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
            self?.handle(message)
        }
        sender.onCapture = { [weak self] id, jpeg in
            guard let self, let image = UIImage(data: jpeg) else { return }
            scan = PhoneScan(id: id, image: image)
            captures.append((id, image))
            if captures.count > 10 { captures.removeFirst() }
        }
        fling.onFling = { [weak self] in
            // The phone is blurry mid-flick, so send the frame from just before it.
            self?.capture(lookBack: 0.3)
        }
        link.start()
        if isFlickEnabled { fling.start() }

        #if targetEnvironment(simulator)
        startTestPattern(into: sender)
        cameraStatus = .testPattern
        #else
        camera.onFrame = { buffer in sender.offer(CIImage(cvPixelBuffer: buffer)) }
        cameraStatus = await camera.start() ? .running : .denied
        #endif
    }

    func capture(lookBack: Double = 0) {
        guard isConnected else { return }
        sender.requestCapture(lookBack: lookBack)
        flashCount += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func handle(_ message: LinkMessage) {
        switch message {
        case .received(let frameID, let sentAt):
            roundTripMs = sender.acknowledge(frameID: frameID, sentAt: sentAt)
        case .highlights(let captureID, let boxes):
            if scan?.id == captureID {
                scan?.highlights = boxes
            } else if let earlier = captures.last(where: { $0.id == captureID }) {
                scan = PhoneScan(id: captureID, image: earlier.image, highlights: boxes)
            } else {
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .frame:
            break
        }
    }

    /// The simulator has no camera: it sends a numbered, color-cycling frame ten times a
    /// second, and the demo props in turn (contract, window sticker, credit union quote)
    /// when you press the shutter, so the whole money flow can be rehearsed without an iPhone.
    private func startTestPattern(into sender: FrameSender) {
        let props = ["SimulatorProp1-contract", "SimulatorProp2-sticker", "SimulatorProp3-quote"]
            .compactMap { Bundle.main.url(forResource: $0, withExtension: "jpg").flatMap { CIImage(contentsOf: $0) } }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "grasp.phone.testpattern"))
        var count = 0
        var nextProp = 0
        var lastSent = 0
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
            guard let cgImage = image.cgImage else { return }
            sender.offer(CIImage(cgImage: cgImage), captureImage: props.isEmpty ? nil : props[nextProp % props.count])
            // Move on to the next prop once one has gone out as a capture.
            if sender.capturesSent != lastSent {
                lastSent = sender.capturesSent
                nextProp += 1
            }
        }
        timer.resume()
        testPattern = timer
    }
}
