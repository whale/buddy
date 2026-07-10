import XCTest
import SwiftUI
@testable import Buddy

// MARK: - Escalation token parity
// Pins EscalationTheme to the shared contract at design/escalation-tokens.json —
// the single source of truth for both platforms (the Mac pins the same file via
// __buddy.smokeTest). If a token changes in the JSON without a matching Swift
// change (or vice versa), this fails. Change the design in the JSON FIRST.
final class EscalationTokenParityTests: XCTestCase {

    // Decoded contract: we only need the per-level token maps.
    private struct Contract: Decodable {
        let levels: [String: [String: String]]
    }

    private struct RGBA {
        let r: Double, g: Double, b: Double, a: Double
    }

    // Walk up from this file to the repo root: Tests → Buddy → ios → <root>.
    private var contractURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // Buddy/
            .deletingLastPathComponent()   // ios/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("design/escalation-tokens.json")
    }

    func testThemeMatchesSharedContract() throws {
        let data = try Data(contentsOf: contractURL)
        let contract = try JSONDecoder().decode(Contract.self, from: data)

        let cases: [(name: String, level: EscalationLevel)] =
            [("lvl0", .lvl0), ("lvl1", .lvl1), ("lvl2", .lvl2)]

        for (name, level) in cases {
            let json = try XCTUnwrap(contract.levels[name], "missing \(name) in contract")
            let theme = EscalationTheme(level: level)
            try assertToken(theme.cardBackground, json["card"],      "\(name).card")
            try assertToken(theme.ink,            json["ink"],       "\(name).ink")
            try assertToken(theme.inkDim,         json["inkDim"],    "\(name).inkDim")
            try assertToken(theme.glyph,          json["glyph"],     "\(name).glyph")
            try assertToken(theme.chromeInk,      json["chromeInk"], "\(name).chromeInk")
            try assertToken(theme.selBg,          json["selBg"],     "\(name).selBg")
            try assertToken(theme.selInk,         json["selInk"],    "\(name).selInk")
            try assertToken(theme.line,           json["line"],      "\(name).line")
        }
    }

    // MARK: helpers

    private func assertToken(_ color: Color, _ spec: String?, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let want = try XCTUnwrap(parse(try XCTUnwrap(spec, "missing token \(label)")),
                                 "unparseable token \(label)")
        let got = rgba(of: color)
        let tol = 0.01   // sRGB component tolerance (hex quantisation is 1/255 ≈ 0.004)
        XCTAssertEqual(got.r, want.r, accuracy: tol, "\(label) red", file: file, line: line)
        XCTAssertEqual(got.g, want.g, accuracy: tol, "\(label) green", file: file, line: line)
        XCTAssertEqual(got.b, want.b, accuracy: tol, "\(label) blue", file: file, line: line)
        XCTAssertEqual(got.a, want.a, accuracy: tol, "\(label) alpha", file: file, line: line)
    }

    // Parses "#rrggbb" and "rgba(r,g,b,a)" (0–255 channels, 0–1 alpha).
    private func parse(_ spec: String) -> RGBA? {
        let s = spec.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#"), s.count == 7 {
            var int: UInt64 = 0
            guard Scanner(string: String(s.dropFirst())).scanHexInt64(&int) else { return nil }
            return RGBA(r: Double((int >> 16) & 0xFF) / 255,
                        g: Double((int >> 8) & 0xFF) / 255,
                        b: Double(int & 0xFF) / 255,
                        a: 1)
        }
        if s.hasPrefix("rgba("), s.hasSuffix(")") {
            let parts = s.dropFirst(5).dropLast()
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 4 else { return nil }
            return RGBA(r: parts[0] / 255, g: parts[1] / 255, b: parts[2] / 255, a: parts[3])
        }
        return nil
    }

    // SwiftUI Color → sRGB components via UIKit.
    private func rgba(of color: Color) -> RGBA {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }
}
