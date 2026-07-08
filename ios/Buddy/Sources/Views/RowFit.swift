import SwiftUI
import UIKit

// MARK: - Adaptive row fitting (matches the Mac's fitWrap engine)
// Fit up to 6 (possibly multi-line) active rows in the fixed list column with NO scroll.
// ONE uniform font for the whole list — the largest at which every row's REAL wrapped
// text fits. Two stages: compress vertical padding first (barely noticeable), THEN shrink
// font, down to a legibility floor. Scroll only as a last resort when even floor + min
// padding overflows — never clip, never illegible.
//
// Clip-safety: we pick the largest (font, pad) whose NATURAL wrapped height ≤ available
// height, then flex-fill the rows. Filled rows are always ≥ natural, so text never clips.
enum RowFit {
    struct Result: Equatable { var font: CGFloat; var vpad: CGFloat; var scroll: Bool }

    static let padMax: CGFloat = 16, padMin: CGFloat = 8
    static let addBottomExtra: CGFloat = 8

    /// - active: the active task texts (the big, possibly multi-line rows).
    /// - doneCount: compact Donezo rows sitting above (fixed 15pt) — reserve their space.
    /// - height/width: the list card's available size. width is the card width (gutters removed inside).
    /// - ceil/floor: font ceiling & legibility floor (main view 24, morning 22).
    static func compute(active: [String], doneCount: Int, height H: CGFloat, width cardW: CGFloat,
                        includesAdd: Bool = true,
                        ceil: CGFloat = 24, floor: CGFloat = 16) -> Result {
        guard H > 0, cardW > 0 else { return Result(font: ceil, vpad: padMax, scroll: false) }
        let innerW = max(40, cardW - 64)                 // 32pt gutter each side
        // Compact done rows: single line at 15pt + generous padding + divider. Overestimated
        // on purpose (safe — leaves the active rows a little extra headroom).
        let doneRowH: CGFloat = 15 * 1.3 + 2 * 16 + 1
        let avail = H - CGFloat(doneCount) * doneRowH
        let n = CGFloat(active.count)

        func naturalTotal(_ f: CGFloat, _ p: CGFloat) -> CGFloat {
            guard let uf = UIFont(name: "Geist-Medium", size: f) else { return .greatestFiniteMagnitude }
            let para = NSMutableParagraphStyle(); para.lineSpacing = 2
            var sum: CGFloat = 0
            for t in active {
                let s = t.isEmpty ? "Untitled" : t
                let r = NSAttributedString(string: s, attributes: [.font: uf, .paragraphStyle: para])
                    .boundingRect(with: CGSize(width: innerW, height: .greatestFiniteMagnitude),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                sum += r.height.rounded(.up) + 2 * p
            }
            if includesAdd {
                sum += uf.lineHeight + 2 * p + addBottomExtra  // the "Add +" row (one line) with extra bottom air
            }
            sum += max(0, n + (includesAdd ? 1 : 0) - 1) * 1   // hairline dividers between active/add rows
            return sum + 4                      // safety epsilon vs SwiftUI's own line metrics
        }

        if naturalTotal(ceil, padMax) <= avail { return Result(font: ceil, vpad: padMax, scroll: false) }
        var p = padMax
        while p > padMin { p -= 1; if naturalTotal(ceil, p) <= avail { return Result(font: ceil, vpad: p, scroll: false) } }
        var f = ceil
        while f > floor { f -= 0.5; if naturalTotal(f, padMin) <= avail { return Result(font: f, vpad: padMin, scroll: false) } }
        return Result(font: floor, vpad: padMin, scroll: true)   // last resort
    }
}
