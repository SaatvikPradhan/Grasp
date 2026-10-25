import AVKit
import GraspKit
import SwiftUI

/// A video read like a page: the player (or, for YouTube, its picture), the moments worth jumping
/// back to, and the facts said, each with its time. Click a time to jump there; hover for the frame.
struct VideoCardView: View {
    let cardID: UUID
    let document: PageDocument
    let video: VideoSource

    @Environment(\.isCanvasSnapshot) private var isSnapshot

    private var reading: VideoReading { video.reading }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(reading.kind.uppercased() + (video.duration.map { " · " + VideoReading.clock($0) } ?? ""))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(reading.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(reading.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }

            player
                .frame(height: 244)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("MOMENTS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
            ForEach(Array(reading.moments.prefix(6).enumerated()), id: \.offset) { index, moment in
                HStack(spacing: 10) {
                    TimeChip(seconds: moment.seconds)
                    Text(moment.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 21)
                .contentShape(Rectangle())
                .hoverSource(.moment(document: document.id, index: index))
                .onTapGesture { VideoPlayers.shared.seek(document, to: moment.seconds) }
            }

            if !reading.facts.isEmpty {
                Text("SAID IN IT")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.hot)
                    .padding(.top, 4)
                ForEach(reading.facts.prefix(5), id: \.key) { fact in
                    let seconds = reading.seconds(of: fact.quote)
                    HStack(spacing: 10) {
                        if let seconds { TimeChip(seconds: seconds) }
                        Text(fact.label)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(fact.asPrinted)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    .frame(height: 19)
                    .contentShape(Rectangle())
                    .hoverSource(.fact(document: document.id, key: fact.key))
                    .onTapGesture { seconds.map { VideoPlayers.shared.seek(document, to: $0) } }
                }
            }
            Spacer(minLength: 0)
            Text("Click a time to jump there · notes typed beside it get the time")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var player: some View {
        if !isSnapshot, let player = VideoPlayers.shared.player(for: document) {
            PlayerView(player: player)
        } else {
            Image(nsImage: document.image)
                .resizable()
                .scaledToFit()
                .overlay {
                    if case .youTube = video.location {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { VideoPlayers.shared.seek(document, to: 0) }
        }
    }
}

/// A time in a video, as a small capsule: "0:36".
struct TimeChip: View {
    let seconds: Double

    var body: some View {
        Text(VideoReading.clock(seconds))
            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.accent))
            .fixedSize()
    }
}

/// AppKit's player view. SwiftUI's own `VideoPlayer` aborts at launch in this app (its AVKit
/// overlay fails to set up), so this wraps the AppKit one instead.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
