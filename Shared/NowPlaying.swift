import Foundation

enum Shared {
    /// "<TEAMID>.uz.musicwidget", filled in at build time so every developer team gets its own group.
    static let group = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as! String
    static let kind = "NowPlaying"
    static let commandNote = Notification.Name("uz.musicwidget.command")
    static var dir: URL { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)! }
    static var stateURL: URL { dir.appendingPathComponent("state.json") }
    static var artURL: URL { dir.appendingPathComponent("art.jpg") }
    /// Exists while the app's live card covers the widget; the widget then draws only its own background.
    static var liveURL: URL { dir.appendingPathComponent("live") }
}

/// What the host app last saw in Spotify / Music. Written by the app, read by the widget.
struct NowPlaying: Codable, Equatable {
    var player: String      // "Spotify" | "Music"
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var duration: Double    // seconds
    var position: Double    // seconds, as of `updated`
    var updated: Date
    var artKey: String
    var lyrics: [Lyric]? = nil

    var startDate: Date { updated.addingTimeInterval(-position) }
    var endDate: Date { startDate.addingTimeInterval(max(duration, position, 1)) }
    func position(at date: Date) -> Double {
        isPlaying ? min(position + date.timeIntervalSince(updated), duration) : position
    }

    static func load() -> NowPlaying? {
        try? JSONDecoder().decode(NowPlaying.self, from: Data(contentsOf: Shared.stateURL))
    }
    func save() { try? JSONEncoder().encode(self).write(to: Shared.stateURL, options: .atomic) }
}

struct Lyric: Codable, Equatable {
    var t: Double   // seconds into the song
    var s: String   // empty = instrumental gap
}

/// A stretch of the song shown as one karaoke row: a sung line, or music between lines (`text == nil`).
struct LyricSegment: Equatable {
    var text: String?
    var start: Double
    var end: Double
}

extension NowPlaying {
    /// LRC only says when each line starts, so a line's sung length is estimated from the song's own pace
    /// (median seconds per character); the rest of the gap before the next line becomes a music segment.
    var segments: [LyricSegment] {
        let all = lyrics ?? []
        let lines = all.filter { !$0.s.isEmpty }
        guard !lines.isEmpty else { return [] }
        let next = { (l: Lyric) in all.first { $0.t > l.t }?.t ?? max(self.duration, l.t) }
        let paces = lines.map { (next($0) - $0.t) / Double($0.s.count) }.sorted()
        let pace = min(max(paces[(paces.count - 1) / 2], 0.04), 0.25)
        let minMusic = 3.0  // shorter breaks just hold the finished line
        var out: [LyricSegment] = []
        if lines[0].t >= minMusic { out.append(LyricSegment(text: nil, start: 0, end: lines[0].t)) }
        for l in lines {
            let gapEnd = next(l)
            let sung = min(gapEnd, l.t + Double(l.s.count) * pace * 1.15)
            if gapEnd - sung >= minMusic {
                out.append(LyricSegment(text: l.s, start: l.t, end: sung))
                out.append(LyricSegment(text: nil, start: sung, end: gapEnd))
            } else {
                out.append(LyricSegment(text: l.s, start: l.t, end: gapEnd))
            }
        }
        return out
    }
}
