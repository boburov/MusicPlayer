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
