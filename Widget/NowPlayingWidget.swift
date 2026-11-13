import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Buttons

struct PlayerCommand: AppIntent {
    static var title: LocalizedStringResource = "Pleyer buyrug'i"
    static var isDiscoverable = false

    @Parameter(title: "Amal") var action: String

    init() {}
    init(_ action: String) { self.action = action }

    func perform() async throws -> some IntentResult {
        let before = NowPlaying.load()
        // Optimistic: play/pause redraws instantly; the app confirms with the real state right after.
        if action == "playpause", var s = before {
            s.position = s.position(at: Date()); s.isPlaying.toggle(); s.updated = Date(); s.save()
        }
        // Sandboxed sender: object must be a string, userInfo must be nil.
        DistributedNotificationCenter.default().postNotificationName(Shared.commandNote, object: action, userInfo: nil, deliverImmediately: true)
        // Skips: hold the system's post-tap redraw until the app has written the new track (max 1.5s),
        // so the widget jumps straight to the next song instead of waiting on a throttled reload.
        if action == "next" || action == "previous", let before {
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if let now = NowPlaying.load(), now.title != before.title || now.artKey != before.artKey { break }
            }
        }
        return .result()
    }
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    let np: NowPlaying?
    let art: NSImage?
}

/// macOS draws widget entries a little after their date, so lyric lines are scheduled this much early.
let lyricLead: TimeInterval = 1.0

struct Provider: TimelineProvider {
    private static let sample = NowPlaying(player: "Spotify", title: "Qo'shiq nomi", artist: "Ijrochi", album: "Albom",
                                           isPlaying: true, duration: 210, position: 80, updated: Date(), artKey: "")

    func placeholder(in context: Context) -> Entry { Entry(date: Date(), np: Self.sample, art: nil) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let e = current()
        completion(e.np == nil && context.isPreview ? placeholder(in: context) : e)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let e = current()
        guard let np = e.np, np.isPlaying else { return completion(Timeline(entries: [e], policy: .never)) }
        // One entry exactly when each lyric line starts; wake at the song's end in case the app's reload is throttled.
        let end = np.endDate
        let starts = (np.lyrics ?? []).map { np.startDate.addingTimeInterval($0.t - lyricLead) }.filter { $0 > e.date && $0 < end }
        let entries = [e] + starts.prefix(900).map { Entry(date: $0, np: np, art: e.art) }
        completion(Timeline(entries: entries, policy: .after(end.addingTimeInterval(1))))
    }

    private func current() -> Entry {
        Entry(date: Date(), np: NowPlaying.load(), art: NSImage(contentsOf: Shared.artURL))
    }
}

// MARK: - View

/// Layout: artwork top-left, title pill + controls pill top-right, lyrics panel across the bottom.
struct NowPlayingView: View {
    let entry: Entry
    private let pad: CGFloat = 14
    private let gap: CGFloat = 12
    private let panel = Color.white.opacity(0.1)

    var body: some View {
        GeometryReader { g in
            let side = (g.size.width - pad * 2 - gap) * 0.42
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
        .containerBackground(for: .widget) { Color(red: 0.11, green: 0.11, blue: 0.12) }
    }

    @ViewBuilder private var artwork: some View {
        if let art = entry.art {
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
            Text(entry.np?.title ?? "Hech narsa chalinmayapti")
                .font(.system(size: 15, weight: .bold))
            if let np = entry.np {
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
        let playing = entry.np?.isPlaying ?? false
        return HStack(spacing: 0) {
            button("previous", "backward.fill", size: 18, label: "Oldingi qo'shiq")
            button("playpause", playing ? "pause.fill" : "play.fill", size: 24, label: playing ? "To'xtatish" : "Ijro etish")
            button("next", "forward.fill", size: 18, label: "Keyingi qo'shiq")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panel, in: Capsule())
    }

    private var lyricsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let (now, next) = lyric {
                Text(now)
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(2)
                ForEach(Array(next.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .opacity(0.4)
                }
            } else if entry.np != nil {
                Text("So'zlar topilmadi")
                    .font(.system(size: 15, weight: .semibold))
                    .opacity(0.4)
            }
        }
        .minimumScaleFactor(0.8)
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// The line being sung at this entry's moment (♪ before the first one) and up to 3 lines after it.
    private var lyric: (now: String, next: [String])? {
        guard let np = entry.np, let lines = np.lyrics?.filter({ !$0.s.isEmpty }), !lines.isEmpty else { return nil }
        let pos = np.position(at: entry.date) + lyricLead
        let i = lines.lastIndex { $0.t <= pos }
        let next = lines[(i.map { $0 + 1 } ?? 0)...].prefix(3).map(\.s)
        return (i.map { lines[$0].s } ?? "♪", next)
    }

    private func button(_ action: String, _ symbol: String, size: CGFloat, label: String) -> some View {
        Button(intent: PlayerCommand(action)) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Widget

@main
struct NowPlayingWidget: Widget {
    private var families: [WidgetFamily] {
        if #available(macOS 27.0, *) { return [.systemLarge, .systemExtraLargePortrait] }
        return [.systemLarge]
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Shared.kind, provider: Provider()) { NowPlayingView(entry: $0) }
            .configurationDisplayName("Musiqa")
            .description("Hozir chalinayotgan qo'shiq: rasm, nom, so'zlar va tugmalar.")
            .supportedFamilies(families)
            .contentMarginsDisabled()
    }
}
