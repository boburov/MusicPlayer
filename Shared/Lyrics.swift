import SwiftUI

/// Widget layout numbers, shared so the app can lay its live lyrics exactly over the widget's panel.
enum Layout {
    static let pad: CGFloat = 14
    static let gap: CGFloat = 12
    static let panelRadius: CGFloat = 22
    static func artSide(width: CGFloat) -> CGFloat { (width - pad * 2 - gap) * 0.42 }
}

/// The line being sung at `pos` (♪ before the first one) and up to 3 lines after it.
struct LyricsText: View {
    let np: NowPlaying?
    let pos: Double

    var body: some View {
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
