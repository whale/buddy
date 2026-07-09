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

    static func doneFont(for font: CGFloat) -> CGFloat {
        max(11, min(15, font - 9))
    }

    static func donePad(for vpad: CGFloat) -> CGFloat {
        max(6, min(16, vpad - 2))
    }

    /// - active: the active task texts (the big, possibly multi-line rows).
    /// - done: compact Donezo texts sitting above. They still participate in the fit
    ///   so a done-heavy list shrinks as one visual system instead of staying fixed.
    /// - height/width: the list card's available size. width is the card width (gutters removed inside).
    /// - ceil/floor: font ceiling & legibility floor (main view 24, morning 22).
    static func compute(active: [String], done: [String] = [], height H: CGFloat, width cardW: CGFloat,
                        includesAdd: Bool = true,
                        ceil: CGFloat = 24, floor: CGFloat = 16) -> Result {
        guard H > 0, cardW > 0 else { return Result(font: ceil, vpad: padMax, scroll: false) }
        let innerW = max(40, cardW - 64)                 // 32pt gutter each side
        let avail = H
        let n = CGFloat(active.count)
        let doneN = CGFloat(done.count)

        func naturalTotal(_ f: CGFloat, _ p: CGFloat) -> CGFloat {
            guard let uf = UIFont(name: "Geist-Medium", size: f) else { return .greatestFiniteMagnitude }
            let para = NSMutableParagraphStyle(); para.lineSpacing = 2
            var sum: CGFloat = 0
            let doneF = doneFont(for: f)
            let doneP = donePad(for: p)
            let doneUF = UIFont(name: "Geist-Regular", size: doneF) ?? .systemFont(ofSize: doneF)
            let doneWordUF = UIFont(name: "Geist-SemiBold", size: doneF) ?? .boldSystemFont(ofSize: doneF)
            for t in done {
                let labelW: CGFloat = 74
                let textW = max(40, innerW - labelW - 30)
                let s = t.isEmpty ? "Untitled" : t
                let r = NSAttributedString(string: s, attributes: [.font: doneUF])
                    .boundingRect(with: CGSize(width: textW, height: .greatestFiniteMagnitude),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                let wordH = doneWordUF.lineHeight
                sum += max(r.height.rounded(.up), wordH) + 2 * doneP
            }
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
            sum += max(0, doneN + n + (includesAdd ? 1 : 0) - 1) * 1   // hairline dividers between visible rows
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
