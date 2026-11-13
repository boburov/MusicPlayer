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
            if karaoke, let np, np.lyrics?.contains(where: { !$0.s.isEmpty }) == true {
                KaraokeLyrics(np: np, pos: pos)
            } else if let (now, next) = lyric {
                Text(now)
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(2)
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



/// Live card lyrics: the current line fills word by word with a soft glowing edge while it's sung,
/// and lines glide up when the next one starts. Core Animation runs it; the card isn't redrawn per frame.
struct KaraokeLyrics: View {
    let np: NowPlaying
    let pos: Double

    var body: some View {
        let lines = np.lyrics?.filter { !$0.s.isEmpty } ?? []
        let cur = lines.lastIndex { $0.t <= pos }
        let from = cur ?? -1
        VStack(alignment: .leading, spacing: 8) {
            if cur == nil {
                Text("♪").font(.system(size: 19, weight: .bold)).transition(.glide)
            }
            ForEach(lines.indices.filter { $0 >= from && $0 <= from + 3 }, id: \.self) { k in
                // A stable container per line: becoming current crossfades in place; only arriving/leaving glides.
                VStack(alignment: .leading, spacing: 0) {
                    if k == cur {
                        // A seek or play/pause restarts the fill from the right spot.
                        KaraokeLine(line: lines[k], end: lineEnd(lines[k]), pos: pos, playing: np.isPlaying)
                            .id("\(np.isPlaying)|\(Int(np.startDate.timeIntervalSince1970 * 10))")
                    } else {
                        Text(lines[k].s).font(.system(size: 15, weight: .semibold)).lineLimit(1).opacity(0.4)
                    }
                }
                .transition(.glide)
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: cur)
    }

    /// Sung until the next timestamp (an empty one marks a pause), capped so a long break doesn't stall it.
    private func lineEnd(_ l: Lyric) -> Double {
        min(np.lyrics?.first { $0.t > l.t }?.t ?? np.duration, l.t + 8)
    }
}

private extension AnyTransition {
    /// The sung line drifts up and out; new lines rise in from below.
    static var glide: AnyTransition {
        // Short drifts, not full-height moves: a sung line sliding its whole height overlapped the next one.
        .asymmetric(insertion: .offset(y: 14).combined(with: .opacity),
                    removal: .offset(y: -18).combined(with: .opacity).animation(.easeOut(duration: 0.25)))
    }
}

/// One line, words laid out like text and wrapped onto as many rows as needed. The line's time is
/// shared out by word length, since LRC files only time whole lines.
struct KaraokeLine: View {
    let line: Lyric
    let end: Double
    let pos: Double
    let playing: Bool

    var body: some View {
        let words = line.s.split(separator: " ").map(String.init)
        let span = max(end - line.t, 0.1)
        let total = Double(words.reduce(0) { $0 + $1.count + 1 })
        var at = line.t
        let timed = words.map { w -> (String, Double, Double) in
            let d = span * Double(w.count + 1) / total
            defer { at += d }
            return (w, at, d)
        }
        return Flow {
            ForEach(Array(timed.enumerated()), id: \.offset) { _, t in
                KaraokeWord(word: t.0, start: t.1, duration: t.2, pos: pos, playing: playing)
            }
        }
    }
}

struct KaraokeWord: View {
    let word: String
    let wait: Double        // seconds until this word starts filling
    let duration: Double    // seconds left to fill; 0 = hold still
    @State private var p: Double

    init(word: String, start: Double, duration: Double, pos: Double, playing: Bool) {
        self.word = word
        let done = min(max((pos - start) / duration, 0), 1)
        _p = State(initialValue: done)
        wait = playing ? max(start - pos, 0) : 0
        self.duration = playing && done < 1 ? duration * (1 - done) : 0
    }

    var body: some View {
        let text = Text(word).font(.system(size: 19, weight: .bold))
        text.opacity(0.35)
            .overlay {
                text.mask(alignment: .leading) {
                    GeometryReader { g in
                        // A feathered edge, so the fill drifts in like a cloud instead of a hard wipe.
                        let soft = max(g.size.width * 0.5, 16)
                        let full = g.size.width + soft
                        LinearGradient(stops: [.init(color: .white, location: 0),
                                               .init(color: .white, location: g.size.width / full),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: full)
                            .offset(x: (p - 1) * full)
                    }
                }
                .shadow(color: .white.opacity(0.55), radius: 6)
            }
            .onAppear {
                guard duration > 0 else { return }
                withAnimation(.linear(duration: duration).delay(wait)) { p = 1 }
            }
    }
}

/// Lays words out left to right and wraps them like text.
struct Flow: SwiftUI.Layout {
    var spacing: CGFloat = 5
    var rowSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let r = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? r.width, height: r.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        for (i, pt) in arrange(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pt.x, y: bounds.minY + pt.y), proposal: .unspecified)
        }
    }

    private func arrange(_ maxWidth: CGFloat, _ subviews: LayoutSubviews) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth { x = 0; y += rowHeight + rowSpacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (points, width, y + rowHeight)
    }
}
