import AppKit
import ServiceManagement
import WidgetKit

/// Background agent: watches Spotify/Music, writes NowPlaying + artwork for the widget,
/// and runs the widget's button commands (the sandboxed widget can't script other apps).
final class Controller: NSObject {
    private var last: NowPlaying?
    private var preferred = "Spotify"
    private var artLoading: String?         // artKey whose download is in flight
    private var playPauseTapAt = Date.distantPast
    private static let bundleIDs = ["Spotify": "com.spotify.client", "Music": "com.apple.Music"]

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(spotifyChanged), name: .init("com.spotify.client.PlaybackStateChanged"), object: nil, suspensionBehavior: .deliverImmediately)
        dnc.addObserver(self, selector: #selector(musicChanged), name: .init("com.apple.Music.playerInfo"), object: nil, suspensionBehavior: .deliverImmediately)
        dnc.addObserver(self, selector: #selector(command(_:)), name: Shared.commandNote, object: nil, suspensionBehavior: .deliverImmediately)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        // Catches seeks and anything the players don't announce.
        Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        refresh()
    }

    @objc private func spotifyChanged() { preferred = "Spotify"; refresh() }
    @objc private func musicChanged() { preferred = "Music"; refresh() }

    @objc private func command(_ note: Notification) {
        let verbs = ["playpause": "playpause", "next": "next track", "previous": "previous track"]
        guard let verb = verbs[note.object as? String ?? ""] else { return }
        // Nothing running: this launches the preferred player.
        let player = last?.player ?? preferred
        if note.object as? String == "playpause" { playPauseTapAt = Date() }
        _ = script("tell application \"\(player)\" to \(verb)")
        // The widget waits for our next state write, so refresh fast; the player's own notification covers a slow switch.
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.refresh() }
    }

    @objc func refresh() {
        let order = preferred == "Spotify" ? ["Spotify", "Music"] : ["Music", "Spotify"]
        let found = order.compactMap(query)
        guard let pick = found.first(where: { $0.0.isPlaying }) ?? found.first else {
            if last != nil { last = nil; try? FileManager.default.removeItem(at: Shared.stateURL); reload() }
            return
        }
        var np = pick.0
        guard Self.changed(last, np) else { return }
        let artChanged = np.artKey != last?.artKey
        let sameTrack = last.map { ($0.title, $0.artist) == (np.title, np.artist) } ?? false
        if sameTrack { np.lyrics = last?.lyrics } else { fetchLyrics(np) }
        last = np
        guard artChanged else {
            // While new artwork downloads, publishing would pair the new title with the old picture; the download saves.
            guard artLoading != np.artKey else { return }
            np.save()
            // A widget play/pause tap already redrew the widget for free; don't spend the daily reload budget on it.
            if !(sameTrack && Date().timeIntervalSince(playPauseTapAt) < 2) { reload() }
            return
        }
        artLoading = np.artKey
        loadArt(np.player, pick.1) { data in
            // Skipping fast starts several downloads; a late one for an earlier song must not overwrite the current art.
            guard self.last?.artKey == np.artKey else { return }
            self.artLoading = nil
            if let data { try? data.write(to: Shared.artURL, options: .atomic) }
            else { try? FileManager.default.removeItem(at: Shared.artURL) }
            self.last?.save(); self.reload()
        }
    }

    /// Synced lyrics from LRCLIB (free, no key). Spotify's own lyrics aren't reachable from outside.
    private func fetchLyrics(_ np: NowPlaying) {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [.init(name: "track_name", value: np.title), .init(name: "artist_name", value: np.artist)]
        var req = URLRequest(url: c.url!)
        req.setValue("MusicWidget/1.1 (personal desktop widget)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            struct Hit: Decodable { let duration: Double?; let syncedLyrics: String? }
            let hits = (try? JSONDecoder().decode([Hit].self, from: data ?? Data())) ?? []
            let gap = { (h: Hit) in abs((h.duration ?? 0) - np.duration) }
            // Another cut of the song (radio edit, live) would drift out of sync, so require a close duration.
            let best = hits.filter { $0.syncedLyrics != nil && gap($0) <= 5 }.min { gap($0) < gap($1) }
            let lines = best?.syncedLyrics.map(Self.parseLRC) ?? []
            DispatchQueue.main.async {
                guard var cur = self.last, (cur.title, cur.artist) == (np.title, np.artist), !lines.isEmpty else { return }
                cur.lyrics = lines; self.last = cur; cur.save(); self.reload()
            }
        }.resume()
    }

    /// "[mm:ss.xx] text" lines → sorted lyrics. Lines without a timestamp are dropped.
    static func parseLRC(_ lrc: String) -> [Lyric] {
        lrc.split(whereSeparator: \.isNewline).compactMap { line -> Lyric? in
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
            let stamp = line[line.index(after: line.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let m = Double(stamp[0]), let sec = Double(stamp[1]) else { return nil }
            return Lyric(t: m * 60 + sec, s: line[line.index(after: close)...].trimmingCharacters(in: .whitespaces))
        }.sorted { $0.t < $1.t }
    }

    private func reload() { WidgetCenter.shared.reloadTimelines(ofKind: Shared.kind) }

    private func query(_ player: String) -> (NowPlaying, String)? {
        guard let id = Self.bundleIDs[player], !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty else { return nil }
        let art = player == "Spotify" ? "artwork url of current track" : "\"\""
        guard let d = script("""
            tell application "\(player)"
              if player state is stopped then return {}
              return {player state as string, name of current track, artist of current track, duration of current track, player position, \(art), album of current track}
            end tell
            """), d.numberOfItems == 7 else { return nil }
        let title = d.atIndex(2)?.stringValue ?? "", artist = d.atIndex(3)?.stringValue ?? ""
        var duration = d.atIndex(4)?.doubleValue ?? 0
        if player == "Spotify" { duration /= 1000 } // Spotify reports milliseconds
        let artURL = d.atIndex(6)?.stringValue ?? ""
        let np = NowPlaying(player: player, title: title, artist: artist, album: d.atIndex(7)?.stringValue ?? "",
                            isPlaying: d.atIndex(1)?.stringValue == "playing",
                            duration: duration, position: d.atIndex(5)?.doubleValue ?? 0, updated: Date(),
                            artKey: player == "Spotify" ? artURL : "\(title)|\(artist)")
        return (np, artURL)
    }

    private func loadArt(_ player: String, _ url: String, done: @escaping (Data?) -> Void) {
        if player == "Music" {
            return done(script("tell application \"Music\" to get raw data of artwork 1 of current track").flatMap { Self.jpeg($0.data) })
        }
        guard let u = URL(string: url) else { return done(nil) }
        URLSession.shared.dataTask(with: u) { data, _, _ in
            let jpg = data.flatMap(Self.jpeg)
            DispatchQueue.main.async { done(jpg) }
        }.resume()
    }

    private func script(_ source: String) -> NSAppleEventDescriptor? {
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err { NSLog("MusicWidget AppleScript error: %@", err) }
        return err == nil ? r : nil
    }

    /// Widgets have a tight memory budget; Music artwork can be 3000px, so cap at 600px.
    static func jpeg(_ data: Data) -> Data? {
        guard let src = NSBitmapImageRep(data: data) else { return nil }
        let side = min(600, max(src.pixelsWide, src.pixelsHigh))
        let scale = Double(side) / Double(max(src.pixelsWide, src.pixelsHigh))
        let w = Int(Double(src.pixelsWide) * scale), h = Int(Double(src.pixelsHigh) * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        src.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    /// Reload the widget only on a real change: new track, play/pause, or a seek (>3s off the expected position).
    static func changed(_ old: NowPlaying?, _ new: NowPlaying) -> Bool {
        guard let old else { return true }
        if (old.player, old.title, old.artist, old.isPlaying, old.artKey) != (new.player, new.title, new.artist, new.isPlaying, new.artKey) { return true }
        return abs(old.position(at: new.updated) - new.position) > 3
    }
}

#if DEBUG
private func selfCheck() {
    let t = Date()
    let a = NowPlaying(player: "Spotify", title: "A", artist: "X", album: "", isPlaying: true, duration: 200, position: 10, updated: t, artKey: "")
    var b = a; b.updated = t.addingTimeInterval(10); b.position = 20
    assert(!Controller.changed(a, b), "steady playback must not reload")
    b.position = 90; assert(Controller.changed(a, b), "seek must reload")
    b = a; b.isPlaying = false; assert(Controller.changed(a, b), "pause must reload")
    b = a; b.artKey = "new-cover"; assert(Controller.changed(a, b), "artwork change must reload")
    b = a; b.title = "B"; assert(Controller.changed(a, b), "new track must reload")
    assert(Controller.changed(nil, a))
    let l = Controller.parseLRC("[ti:x]\n[01:02.00]\n[00:12.50] Salom dunyo\nbad")
    assert(l.count == 2 && l[0].t == 12.5 && l[0].s == "Salom dunyo" && l[1].t == 62 && l[1].s == "", "LRC parse")
}
#endif

#if DEBUG
selfCheck()
#endif
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
controller.start()
try? SMAppService.mainApp.register() // start at login so the widget buttons always work
app.run()
