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
    var live = false
}


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
        guard let np = e.np, np.isPlaying, !e.live else { return completion(Timeline(entries: [e], policy: .never)) }
        // One entry exactly when each lyric line starts; wake at the song's end in case the app's reload is throttled.
        let end = np.endDate
        let starts = (np.lyrics ?? []).map { np.startDate.addingTimeInterval($0.t - lyricLead) }.filter { $0 > e.date && $0 < end }
        let entries = [e] + starts.prefix(900).map { Entry(date: $0, np: np, art: e.art) }
        completion(Timeline(entries: entries, policy: .after(end.addingTimeInterval(1))))
    }

    private func current() -> Entry {
        Entry(date: Date(), np: NowPlaying.load(), art: NSImage(contentsOf: Shared.artURL),
              live: FileManager.default.fileExists(atPath: Shared.liveURL.path))
    }
}

// MARK: - View

struct NowPlayingView: View {
    let entry: Entry

    var body: some View {
        Group {
            if entry.live {
                Color.clear // the app's live card draws on top of this widget's system (glass) background
            } else {
                PlayerCard(np: entry.np, art: entry.art, pos: (entry.np?.position(at: entry.date) ?? 0) + lyricLead) { action, icon in
                    AnyView(Button(intent: PlayerCommand(action)) { icon })
                }
            }
        }
        .containerBackground(for: .widget) { Layout.background }
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
