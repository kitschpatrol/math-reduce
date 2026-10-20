import Foundation
import MathReduceCore
import Testing

/// Reduces random mixes of math and prose, checking properties every result must have.
@MainActor
struct ReductionFuzzTests {
  /// Fragments that exercise tokenizing, separators, grapheme clusters, and line breaks.
  /// "random" is left out so that every reduction is deterministic.
  private static let fragments = [
    "0", "1", "2", "7", "42", "3.5", ".5", "2.", "1e3", "0x1F", "0o7", "½", "²", "⁽", "⁾",
    "+", "-", "−", "*", "/", "×", "÷", "^", "%", "!", "!!", "**", "<<", "==", "=", "<", ">",
    "&", "|", "~", "√", "°", "(", ")", "(", ")", ",", ".", ":", ";", "?", "'", "\"", "“", "”",
    "‘", "’", "$", "€", "#", "•", "–", "—", "`", "[", "]", "_", " ", " ", " ", "\t", "\u{00A0}",
    "\n", "\r\n", "\r", "\u{2028}", "\u{2029}", "e", "E", "x", "pi", "PI", "π", "sin", "max",
    "and", "or", "yes", "no", "it", "The", "kg", "😀", "👩‍👩‍👧", "🇺🇸", "é", "e\u{301}", "\u{FFFC}",
  ]

  /// SplitMix64, so failures reproduce from the printed seed.
  private struct Generator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var value = state
      value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
      value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
      return value ^ (value >> 31)
    }
  }

  @Test(arguments: 0..<8)
  func reductionsKeepTheirInvariants(seed: UInt64) {
    var generator = Generator(state: seed)
    let reducer = MathReducer()
    for _ in 0..<1_000 {
      let count = Int.random(in: 0...24, using: &generator)
      let selection = (0..<count).map { _ in Self.fragments.randomElement(using: &generator)! }
        .joined()
      FileHandle.standardError.write(Data((selection.debugDescription + "\n").utf8))
      check(selection, reducer: reducer)
    }
  }

  private func check(_ selection: String, reducer: MathReducer) {
    let plain: String
    do {
      plain = try reducer.reduce(selection)
    } catch {
      #expect(
        throws: ReductionError.self, "\(selection.debugDescription)",
        performing: { try reducer.reduce(NSAttributedString(string: selection)) })
      return
    }
    let rich = try? reducer.reduce(NSAttributedString(string: selection)).string
    #expect(rich == plain, "rich and plain text differ for \(selection.debugDescription)")
    #expect(
      plain.count(where: \.isNewline) == selection.count(where: \.isNewline),
      "line breaks changed for \(selection.debugDescription)")
    #expect(
      Self.isUnchangedOutsideReplacements(selection, plain),
      "text changed outside the expressions in \(selection.debugDescription) → \(plain.debugDescription)"
    )
  }

  /// Replacements hold only number characters, so stripping the characters that can
  /// appear in an expression or a value from both strings must leave the same prose.
  private static func isUnchangedOutsideReplacements(_ selection: String, _ result: String) -> Bool
  {
    let lines = selection.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    let resultLines = result.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    guard lines.count == resultLines.count else { return false }
    let mathCharacters = Set(
      "0123456789.+-−*/×÷^%!&|~√°()⁽⁾,=<>½²" + "xXoOabcdefABCDEF" + "piPIπsinmaxandoryesnoeE_")
    func prose(_ line: Substring) -> String {
      String(line.filter { !mathCharacters.contains($0) && !$0.isWhitespace })
    }
    return zip(lines, resultLines).allSatisfy { prose($0) == prose($1) }
  }
}
