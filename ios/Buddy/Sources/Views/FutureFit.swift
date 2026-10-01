import UIKit

// MARK: - FutureFit
// Shrink-to-fit for the Future list — the iOS twin of the Mac's fitFuture()
// (FUTURE_FIT = { FS:[24,18], MIN:[110,59], STEPS:12 }).
//
// As items are added, the row text and the row floor shrink in 12 even steps from the
// big Future row (24pt text / 110pt rows) down to the "Sent to today!" row's size — on iOS
// that's the Donezo/sent size: RowFit.doneFont(24) = 15pt text, donePad = 14pt padding, the
// measured sent-row height as the floor (the Mac's 18px / 59px). We pick the LARGEST step at
// which every row's natural height fits the panel; only past the smallest step does the list
// scroll under the pinned Add. Mid-edit the step is HELD so the row being typed in never jumps.
//
// Then, like Today, the flex rows (plain rows + draft + Add) share the panel equally; a row
// only gets more than its share when its own (≤2-line) text wouldn't fit in it.
enum FutureFit {
    static let steps = 12
    static let fontMax: CGFloat = 24, fontMin: CGFloat = RowFit.doneFont(for: 24)          // 24 → 15
    static let padMax: CGFloat = 16,  padMin: CGFloat = RowFit.donePad(for: RowFit.padMax)  // 16 → 14
    static let rowMax: CGFloat = 110
    static let lineSpacing: CGFloat = 2
    static let maxLines = 2                       // display rows clamp to 2 lines (Mac line-clamp:2)

    struct Result: Equatable {
        let step: Int
        let font: CGFloat
        let vpad: CGFloat
        let floorH: CGFloat
        let heights: [CGFloat]   // one per flex row, in order; the LAST is the Add row
        let overflow: Bool
    }

    static func t(_ k: Int) -> CGFloat { CGFloat(min(max(k, 0), steps - 1)) / CGFloat(steps - 1) }
    static func font(_ k: Int) -> CGFloat { fontMax + (fontMin - fontMax) * t(k) }
    static func vpad(_ k: Int) -> CGFloat { padMax + (padMin - padMax) * t(k) }
    static func floorH(_ k: Int, sentH: CGFloat) -> CGFloat { (rowMax + (sentH - rowMax) * t(k)).rounded() }

    /// "N more ↓" size: the Mac's fixed 15px count sits beside an Add that shrinks 24→18px, so its
    /// ratio to the Add text runs 15/24 → 15/18. Same ratio per step here: 15pt → 12.5pt.
    static func moreFont(_ k: Int) -> CGFloat { font(k) * (15.0 / 24 + (15.0 / 18 - 15.0 / 24) * t(k)) }

    /// The compact "Sent to today!" row: one 15pt line + donePad top/bottom. Computed from font
    /// metrics (not measured after layout) so the very first frame already picks the right
    /// step — no first-open jump. The sent row is pinned to this exact height.
    static let sentRowHeight: CGFloat = {
        let uf = UIFont(name: "Geist-SemiBold", size: fontMin) ?? .systemFont(ofSize: fontMin, weight: .semibold)
        return ceil(uf.lineHeight + 2 * padMin)
    }()

    // Text measurement is the only costly part — memoised per (text, size, width), main thread only.
    private static var heightCache: [String: CGFloat] = [:]

    /// Height of `text` set in Geist Medium at `font` within `width`, clamped to `maxLines`.
    static func textHeight(_ text: String, font: CGFloat, width: CGFloat) -> CGFloat {
        let key = "\(font)|\(width)|\(text)"
        if let h = heightCache[key] { return h }
        if heightCache.count > 4000 { heightCache.removeAll() }
        let h = measureText(text, font: font, width: width)
        heightCache[key] = h
        return h
    }

    private static func measureText(_ text: String, font: CGFloat, width: CGFloat) -> CGFloat {
        let uf = UIFont(name: "Geist-Medium", size: font) ?? .systemFont(ofSize: font, weight: .medium)
        let s = text.isEmpty ? " " : text
        let rect = (s as NSString).boundingRect(
            with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: uf, .kern: -0.02 * font], context: nil)
        let lines = max(1, min(maxLines, Int((rect.height / uf.lineHeight).rounded())))
        return CGFloat(lines) * uf.lineHeight + CGFloat(lines - 1) * lineSpacing
    }

    /// - texts: the flex rows' texts in order (plain rows, then the draft) — the Add row is implied.
    /// - heldStep: non-nil while editing → keep that step (no jump mid-type).
    static func compute(texts: [String], sentCount: Int, sentH: CGFloat, height H: CGFloat, width W: CGFloat,
                        heldStep: Int? = nil,
                        measure: (String, CGFloat, CGFloat) -> CGFloat = textHeight) -> Result {
        let dividers = CGFloat(texts.count + sentCount)                 // one between each row, incl. above Add
        let avail = H - CGFloat(sentCount) * sentH - dividers
        let innerW = max(40, W - 64)                                    // 32pt gutter each side
        func naturals(_ k: Int) -> [CGFloat] {
            let f = font(k), p = vpad(k), fl = floorH(k, sentH: sentH)
            return (texts + ["Add +"]).map { max(fl, measure($0, f, innerW) + 2 * p) }
        }
        var k: Int
        if let heldStep { k = min(max(heldStep, 0), steps - 1) }
        else {
            // Smallest step first (doesn't fit → scroll there); else binary-search the LARGEST
            // size that fits — totals only shrink as k grows, so this is exact in ≤ 5 probes.
            func fits(_ i: Int) -> Bool { naturals(i).reduce(0, +) <= avail }
            if !fits(steps - 1) { k = steps - 1 }
            else {
                var lo = 0, hi = steps - 1                       // invariant: fits(hi)
                while lo < hi { let mid = (lo + hi) / 2; if fits(mid) { hi = mid } else { lo = mid + 1 } }
                k = hi
            }
        }
        let nat = naturals(k)
        let overflow = H <= 0 || nat.reduce(0, +) > avail + 0.5
        var heights = nat
        if !overflow {
            // Equal shares; a row whose text needs more keeps its natural height, others re-share.
            var big = Set<Int>()
            while true {
                let rest = nat.indices.filter { !big.contains($0) }
                guard !rest.isEmpty else { break }
                let share = (avail - big.reduce(0) { $0 + nat[$1] }) / CGFloat(rest.count)
                let grow = rest.filter { nat[$0] > share }
                if grow.isEmpty {
                    for i in rest { heights[i] = floor(share) }
                    break
                }
                big.formUnion(grow)
            }
        }
        return Result(step: k, font: font(k), vpad: vpad(k), floorH: floorH(k, sentH: sentH),
                      heights: heights, overflow: overflow)
    }
}
