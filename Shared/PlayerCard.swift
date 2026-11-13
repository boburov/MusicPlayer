import AppKit
import SwiftUI

/// Widget layout numbers, shared by the widget and the app's live copy of it.
enum Layout {
    static let pad: CGFloat = 14
    static let gap: CGFloat = 12
    static let panelRadius: CGFloat = 22
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
    static func artSide(width: CGFloat) -> CGFloat { (width - pad * 2 - gap) * 0.42 }
}

/// Lines show this much before they're sung, like Spotify does, so they can be read in time.
/// LRCLIB timestamps mark when singing starts, and some files run a second or two late.
let lyricLead: TimeInterval = 1.5

/// The line being sung at `pos` (♪ before the first one) and up to 3 lines after it.
struct LyricsText: View {
    let np: NowPlaying?
    let pos: Double
    var karaoke = false     // only the app's live card can animate; a widget is a still image

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let (now, next) = lyric {
                if karaoke, let np, let cur = np.lyrics?.last(where: { $0.t <= pos && !$0.s.isEmpty }) {
                    // Sung until the next timestamp (an empty one marks a pause), capped so a long break doesn't stall it.
                    let end = min(np.lyrics?.first { $0.t > cur.t }?.t ?? np.duration, cur.t + 8)
                    KaraokeLine(text: cur.s, done: (pos - cur.t) / max(end - cur.t, 0.1),
                                remaining: np.isPlaying ? max(end - pos, 0) : 0)
                        // A new line, a seek or play/pause restarts the fill from the right spot.
                        .id("\(cur.t)|\(np.isPlaying)|\(Int(np.startDate.timeIntervalSince1970 * 10))")
                } else {
                    Text(now)
                        .font(.system(size: 19, weight: .bold))
                        .lineLimit(2)
                }
                ForEach(Array(next.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .opacity(0.4)
                }
            } else if np != nil {
                Text("So'zlar topilmadi")
                    .font(.system(size: 15, weight: .semibold))
                    .opacity(0.4)
            }
        }
        .minimumScaleFactor(0.8)
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var lyric: (now: String, next: [String])? {
        guard let lines = np?.lyrics?.filter({ !$0.s.isEmpty }), !lines.isEmpty else { return nil }
        let i = lines.lastIndex { $0.t <= pos }
        let next = lines[(i.map { $0 + 1 } ?? 0)...].prefix(3).map(\.s)
        return (i.map { lines[$0].s } ?? "♪", next)
    }
}

/// Layout: artwork top-left, title pill + controls pill top-right, lyrics panel across the bottom.
struct PlayerCard: View {
    let np: NowPlaying?
    let art: NSImage?
    let pos: Double             // song position the lyrics are shown for
    var karaoke = false
    /// Wraps a button's icon in the host's button: an App Intent in the widget, a direct call in the app.
    let control: (_ action: String, _ icon: AnyView) -> AnyView
    private let pad = Layout.pad
    private let gap = Layout.gap
    private let panel = Color.white.opacity(0.1)

    var body: some View {
        GeometryReader { g in
            let side = Layout.artSide(width: g.size.width)
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    artwork
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(spacing: gap) {
                        titlePill
                        controlsPill
                    }
                    .frame(height: side)
                }
                lyricsPanel
            }
            .padding(pad)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private var artwork: some View {
        if let art = art {
            Image(nsImage: art)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFill()
        } else {
            ZStack {
                panel
                Image(systemName: "music.note").font(.system(size: 40, weight: .light)).opacity(0.35)
            }
        }
    }

    private var titlePill: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(np?.title ?? "Hech narsa chalinmayapti")
                .font(.system(size: 15, weight: .bold))
            if let np = np {
                Text(np.artist.isEmpty ? np.player : np.artist)
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.6)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(panel, in: Capsule())
    }

    private var controlsPill: some View {
        let playing = np?.isPlaying ?? false
        return HStack(spacing: 0) {
            button("previous", "backward.fill", size: 18, label: "Oldingi qo'shiq")
            button("playpause", playing ? "pause.fill" : "play.fill", size: 24, label: playing ? "To'xtatish" : "Ijro etish")
            button("next", "forward.fill", size: 18, label: "Keyingi qo'shiq")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panel, in: Capsule())
    }

    private var lyricsPanel: some View {
        LyricsText(np: np, pos: pos, karaoke: karaoke)
            .background(panel, in: RoundedRectangle(cornerRadius: Layout.panelRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Layout.panelRadius, style: .continuous))
    }

    private func button(_ action: String, _ symbol: String, size: CGFloat, label: String) -> some View {
        control(action, AnyView(Image(systemName: symbol)
            .font(.system(size: size))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())))
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}


/// The current line fills left to right while it's sung. Core Animation runs the fill, so the card
/// isn't redrawn per frame.
// shortcut: a line wrapped onto 2 rows fills both rows at once; fill row by row if that looks off.
struct KaraokeLine: View {
    let text: String
    let remaining: Double   // seconds until fully sung; 0 = hold still (paused)
    @State private var progress: Double

    init(text: String, done: Double, remaining: Double) {
        self.text = text
        self.remaining = remaining
        _progress = State(initialValue: min(max(done, 0), 1))
    }

    var body: some View {
        let line = Text(text).font(.system(size: 19, weight: .bold)).lineLimit(2)
        line.opacity(0.35)
            .overlay(alignment: .topLeading) {
                line.mask(alignment: .leading) {
                    GeometryReader { g in Rectangle().frame(width: g.size.width * progress) }
                }
            }
            .onAppear {
                guard remaining > 0 else { return }
                withAnimation(.linear(duration: remaining)) { progress = 1 }
            }
    }
}
