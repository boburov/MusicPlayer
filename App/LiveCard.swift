import AppKit
import SwiftUI

final class LiveState: ObservableObject {
    @Published var np: NowPlaying?
    @Published var art = NSImage(contentsOf: Shared.artURL)
    @Published var snapped = false
}

/// macOS redraws a desktop widget only every few seconds, skips timeline entries, and stops honoring the
/// app's reloads once a small daily budget is spent. So the app draws the widget's content live in its
/// own window, laid exactly over the real widget, which then shows only its background.
final class LiveCard: NSObject, NSWindowDelegate {
    let state = LiveState()
    var onSnap: (Bool) -> Void = { _ in }
    // Non-activating, so pressing a button doesn't pull focus from the app being used.
    private let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 344, height: 344),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var settle: DispatchWorkItem?

    init(send: @escaping (String) -> Void) {
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        // Desktop widgets sit at desktop-icon level + 2: one above them, below every app window.
        window.level = .init(Int(CGWindowLevelForKey(.desktopIconWindow)) + 3)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = ClickHost(rootView: CardView(state: state, send: send))
        if let f = UserDefaults.standard.string(forKey: "cardFrame") { window.setFrame(NSRectFromString(f), display: false) } else { window.center() }
        window.delegate = self
        window.orderFrontRegardless()
        // Follows the widget when it moves a little, and finds it again after the widget host restarts.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.snap() }
    }

    func windowDidMove(_ notification: Notification) {
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.snap() }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Lands on the widget it was dropped near; anywhere else it floats and can be dragged.
    func snap() {
        let me = window.frame, frames = Self.widgetFrames()
        guard !frames.isEmpty else { return } // a full-screen app's space or Edit Widgets: keep the last state
        let near = frames.map(Self.widgetRect).first { hypot($0.minX - me.minX, $0.maxY - me.maxY) < 60 }
        if let near, near != me { window.setFrame(near, display: true) }
        // Snapped, a drag would swallow button clicks; it frees itself when the widget moves away.
        window.isMovableByWindowBackground = near == nil
        if state.snapped != (near != nil) { state.snapped = near != nil; onSnap(near != nil) }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "cardFrame")
    }

    /// Large desktop widget host windows. Only frames are readable without screen-recording permission,
    /// so the card can't tell which widget is ours: the user drops it on the right one.
    private static func widgetFrames() -> [NSRect] {
        let host = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").map(\.processIdentifier))
        let layer = Int(CGWindowLevelForKey(.desktopIconWindow)) + 2
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { w in
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, host.contains(pid),
                  w[kCGWindowLayer as String] as? Int == layer,
                  let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
                  r.width >= 300, r.height >= 300 else { return nil }
            return NSRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height) // CG is top-left origin
        }
    }

    // shortcut: the 8pt shadow margin around the widget was measured on macOS 27; re-measure if the card sits off.
    static func widgetRect(_ host: NSRect) -> NSRect { host.insetBy(dx: 8, dy: 8) }
}

/// Buttons work on the first click even though this app is never the active one.
private final class ClickHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}

private struct CardView: View {
    @ObservedObject var state: LiveState
    let send: (String) -> Void

    private var lineStarts: [Date] {
        guard let np = state.np, np.isPlaying else { return [Date()] }
        let now = Date()
        return [now] + (np.lyrics ?? []).map { np.startDate.addingTimeInterval($0.t - lyricLead) }.filter { $0 > now }
    }

    var body: some View {
        // Redraws exactly when a lyric line starts (not on a fixed tick, which kept the CPU busy).
        TimelineView(.explicit(lineStarts)) { t in
            PlayerCard(np: state.np, art: state.art, pos: (state.np?.position(at: t.date) ?? 0) + lyricLead) { action, icon in
                AnyView(Button { send(action) } label: { icon })
            }
        }
        // Snapped, the widget's own background (glass or tinted, whatever the desktop uses) shows through.
        .background(state.snapped ? Color.clear : Layout.background, in: RoundedRectangle(cornerRadius: 27))
    }
}
