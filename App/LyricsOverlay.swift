import AppKit
import SwiftUI

final class LiveState: ObservableObject {
    @Published var np: NowPlaying?
    @Published var snapped = false
}

/// macOS redraws a desktop widget only every few seconds and skips some timeline entries, so lyrics
/// drawn by the widget lag. The app draws them live instead, in a window snapped over the widget's panel.
final class LyricsOverlay: NSObject, NSWindowDelegate {
    let state = LiveState()
    var onSnap: (Bool) -> Void = { _ in }
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 330, height: 170), styleMask: .borderless, backing: .buffered, defer: false)
    private var settle: DispatchWorkItem?

    override init() {
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Desktop widgets sit at desktop-icon level + 2: one above them, below every app window.
        window.level = .init(Int(CGWindowLevelForKey(.desktopIconWindow)) + 3)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = true
        window.contentView = DragHost(rootView: OverlayView(state: state))
        if let f = UserDefaults.standard.string(forKey: "lyricsFrame") { window.setFrame(NSRectFromString(f), display: false) } else { window.center() }
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

    /// Lands on the lyrics panel of the widget it was dropped near; anywhere else it floats with its own background.
    func snap() {
        let me = window.frame, frames = Self.widgetFrames()
        guard !frames.isEmpty else { return } // a full-screen app's space or Edit Widgets: keep the last state
        let near = frames.map(Self.panel).filter { hypot($0.minX - me.minX, $0.maxY - me.maxY) < 60 }.first
        if let near, near != me { window.setFrame(near, display: true) }
        if state.snapped != (near != nil) { state.snapped = near != nil; onSnap(near != nil) }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "lyricsFrame")
    }

    /// Large desktop widget windows. Only frames are readable without screen-recording permission,
    /// so the overlay can't tell which widget is ours: the user drops it on the right one.
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

    /// The widget's lyrics panel inside its host window, mirroring NowPlayingView's layout.
    // shortcut: the 8pt shadow margin around the widget was measured on macOS 27; re-measure if the overlay sits off.
    static func panel(_ host: NSRect) -> NSRect {
        let w = host.insetBy(dx: 8, dy: 8)
        let side = Layout.artSide(width: w.width)
        return NSRect(x: w.minX + Layout.pad, y: w.minY + Layout.pad,
                      width: w.width - Layout.pad * 2, height: w.height - Layout.pad * 2 - side - Layout.gap)
    }
}

/// Lets the borderless window be dragged from anywhere, even while another app is active.
private final class DragHost<V: View>: NSHostingView<V> {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct OverlayView: View {
    @ObservedObject var state: LiveState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { t in
            LyricsText(np: state.np, pos: state.np?.position(at: t.date) ?? 0)
        }
        .foregroundStyle(.white)
        // Snapped, the widget's own panel shows through, so it matches whatever tint the desktop applies.
        .background(state.snapped ? Color.clear : Color(white: 0.12),
                    in: RoundedRectangle(cornerRadius: Layout.panelRadius, style: .continuous))
    }
}
