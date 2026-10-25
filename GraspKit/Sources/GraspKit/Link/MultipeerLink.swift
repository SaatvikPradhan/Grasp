import Foundation
import MultipeerConnectivity

/// The phone ↔ Mac connection. Multipeer Connectivity uses peer-to-peer Wi-Fi and Bluetooth,
/// so it works even when the venue Wi-Fi blocks device-to-device traffic.
///
/// The Mac hosts (advertises); the phone joins the first Mac it finds. Both apps need
/// `_grasp-link._tcp` and `_grasp-link._udp` in `NSBonjourServices`.
public final class MultipeerLink: NSObject, @unchecked Sendable {
    public enum Role: Sendable {
        /// The Mac: advertises and accepts every invitation.
        case host
        /// The phone: browses and joins.
        case guest
    }

    public enum State: Equatable, Sendable {
        case searching
        case connecting(peer: String)
        case connected(peer: String)
    }

    public static let serviceType = "grasp-link"

    /// Called on the main actor.
    public var onState: (@MainActor (State) -> Void)?
    /// Called on the main actor.
    public var onMessage: (@MainActor (LinkMessage) -> Void)?

    private let role: Role
    private let peerID: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    public init(role: Role, displayName: String) {
        self.role = role
        let name = displayName.isEmpty ? "Grasp" : String(displayName.prefix(63))
        peerID = MCPeerID(displayName: name)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    public var isConnected: Bool { !session.connectedPeers.isEmpty }

    public func start() {
        switch role {
        case .host:
            let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
        case .guest:
            let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
            browser.delegate = self
            browser.startBrowsingForPeers()
            self.browser = browser
        }
        report(.searching)
    }

    public func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }

    /// Sends to every connected peer. Safe from any thread. Returns false when nobody is connected.
    @discardableResult
    public func send(_ message: LinkMessage) -> Bool {
        let peers = session.connectedPeers
        guard !peers.isEmpty, let data = try? message.encoded() else { return false }
        do {
            try session.send(data, toPeers: peers, with: .reliable)
            return true
        } catch {
            return false
        }
    }

    private func report(_ state: State) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.onState?(state) }
        }
    }
}

extension MultipeerLink: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        // Events from different peers can arrive in any order (a phone app restarting leaves its
        // old peer to time out), so report what the session holds now, not just this event.
        if let connected = session.connectedPeers.first {
            report(.connected(peer: connected.displayName))
        } else if state == .connecting {
            report(.connecting(peer: peerID.displayName))
        } else {
            report(.searching)
            // A browser reports each peer once, so restart it to find the Mac again.
            browser?.stopBrowsingForPeers()
            browser?.startBrowsingForPeers()
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? LinkMessage.decoded(from: data) else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.onMessage?(message) }
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerLink: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

extension MultipeerLink: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard session.connectedPeers.isEmpty else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
