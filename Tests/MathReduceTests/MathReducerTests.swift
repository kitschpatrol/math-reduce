import Foundation
import MathReduceCore
import Testing

@MainActor
struct MathReducerTests {
  @Test(arguments: [
    ("2 + 3 * 4", "14"),
    ("(2 + 3) * 4", "20"),
    ("2**10", "1024"),
    ("2^10", "8"),
    ("17 % 5", "2"),
    ("2(3 + 4)", "14"),
    ("sin(PI / 2)", "1"),
    ("√9 + 2 × 3", "9"),
    ("0.5 + 0.25", "0.75"),
    ("5!", "120"),
    ("5.9 & 3", "1"),
    ("1 << -1", "0"),
    ("~0", "-1"),
    ("8 >> 2", "2"),
    ("1 | 2", "3"),
    ("max(-5, -2)", "-2"),
    ("MAX(0, 0)", "0"),
    ("median(3, 1, 2)", "2"),
    ("median(1, 9, 2, 3)", "2.5"),
    ("5!!", "15"),
    ("6!!", "48"),
    ("if(0, 1e30 ^ 1, 42)", "42"),
  ])
  func evaluatesExpression(expression: String, expected: String) throws {
    #expect(try MathReducer().reduce(expression) == expected)
  }

  /// A single line that is entirely an expression keeps DDMathParser's reading,
  /// including forms the prose scanner leaves alone.
  @Test(arguments: [
    ("e", "2.718281828459045"),
    ("PI", "3.141592653589793"),
    ("no", "0"),
    ("0x1F", "31"),
    ("0o17", "15"),
    ("1e3", "1000"),
    ("½", "0.5"),
    ("10-3", "7"),
    ("2026-10-19", "1997"),
    ("1 2 3", "6"),
    ("2 + 2 = 4", "1"),
    ("5 > 3", "1"),
    ("45°", "0.7853981633974483"),
    ("2 (3 + 4)", "14"),
    ("-5 + 2", "-3"),
    ("2 + 2.", "4"),
  ])
  func evaluatesWholeLine(expression: String, expected: String) throws {
    #expect(try MathReducer().reduce(expression) == expected)
  }

  @Test(arguments: [
    ("  2 + 2\n", "  4\n"),
    ("\t1 + 1 ", "\t2 "),
    ("\n\n2 * 3\n\n", "\n\n6\n\n"),
  ])
  func preservesSurroundingWhitespace(selection: String, expected: String) throws {
    #expect(try MathReducer().reduce(selection) == expected)
  }

  @Test func evaluatesArgumentlessRandom() throws {
    let result = try #require(Double(MathReducer().reduce("random")))
    #expect((0..<1).contains(result))
  }

  @Test(arguments: [
    ("1/0", "Cannot divide by zero. (At character 1.)"),
    ("  1/0", "Cannot divide by zero. (At character 3.)"),
    ("hello", "Unknown function: hello. (At character 1.)"),
    ("1, 2", "The selection does not contain a mathematical expression."),
    ("2 +", "The selection does not contain a complete mathematical expression. (At character 3.)"),
    ("hello world", "The selection does not contain a mathematical expression."),
    ("", "Select a mathematical expression first."),
  ])
  func explainsFailure(selection: String, message: String) {
    #expect {
      try MathReducer().reduce(selection)
    } throws: { error in
      (error as? ReductionError)?.errorDescription == message
    }
  }

  @Test func evaluatesReadmeExample() throws {
    let result = try #require(Double(MathReducer().reduce("2.5 * (10**5 / sin(1.5) + 2PI)")))
    #expect(abs(result - 250643.5340249492) < 0.000000001)
  }

  @Test func factorialBeyondIntegerRange() throws {
    let result = try #require(Double(MathReducer().reduce("21!")))
    #expect(abs(result / 5.109094217170944e19 - 1) < 1e-12)
  }

  @Test func doubleFactorialAvoidsIntermediateOverflow() throws {
    let result = try #require(Double(MathReducer().reduce("171!!")))
    let expected = stride(from: 171.0, through: 1, by: -2).reduce(1, *)
    #expect(abs(result / expected - 1) < 1e-12)
  }

  @Test(arguments: ["170!", "299!!", "300!!", "-9223372036854775808 & 1"])
  func acceptsNumericBoundaries(expression: String) throws {
    let result = try #require(Double(MathReducer().reduce(expression)))
    #expect(result.isFinite)
  }

  @Test func boundsInputBeforeRecursiveParsing() throws {
    let nested = String(repeating: "(", count: 2047) + "1" + String(repeating: ")", count: 2047)
    #expect(try MathReducer().reduce(nested) == "1")
    let padded = String(repeating: " ", count: 4095) + "1"
    #expect(try MathReducer().reduce(padded) == padded)
    for expression in [
      String(repeating: "(", count: 20_000) + "1", String(repeating: "π", count: 2049),
    ] {
      #expect(throws: ReductionError.self) { try MathReducer().reduce(expression) }
    }
  }

  @Test(arguments: [
    "", " \n", "2 +", "1/0", "sqrt(-1)", "10**1000", "$missing",
    "1e30 ^ 1", "sqrt(-1) & 1", "~1e30", "1 | 1e30", "1 << 1e30", "1e30 >> 1",
    "9223372036854775808 & 1", "-1e30 & 1", "1e1000 ^ 1", "1 ^ (1e30 ^ 1)",
    "1000000000000!", "factorial2(1000000000000)", "171!", "301!!", "1.5!!", "0!!",
    "max()", "median(1)", "and(1)", "factorial(1, 2)",
    // DDMathParser traps on postfix operators before a comma outside a function.
    "1!!°,1", "(1!!°,1)", "5!!!, 2", "1°°,1",
  ])
  func rejectsInvalidSelection(expression: String) {
    #expect(throws: ReductionError.self) { try MathReducer().reduce(expression) }
  }
}

@MainActor
struct AttributedReductionTests {
  private static let marker = NSAttributedString.Key("marker")

  private func attributed(_ parts: [(String, String?)]) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for (text, marker) in parts {
      let attributes: [NSAttributedString.Key: Any] = marker.map { [Self.marker: $0] } ?? [:]
      result.append(NSAttributedString(string: text, attributes: attributes))
    }
    return result
  }

  private func markers(in text: NSAttributedString) -> [String] {
    var markers: [String] = []
    text.enumerateAttribute(Self.marker, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      if let value = value as? String {
        markers.append("\((text.string as NSString).substring(with: range))=\(value)")
      }
    }
    return markers
  }

  @Test func keepsAttributesOutsideExpressions() throws {
    let selection = attributed([("It ", nil), ("bakes", "bold"), (" 2 + 2 ", nil), ("now", "link")])
    let result = try MathReducer().reduce(selection)
    #expect(result.string == "It bakes 4 now")
    #expect(markers(in: result) == ["bakes=bold", "now=link"])
  }

  @Test func givesEachValueItsExpressionsFirstAttributes() throws {
    let selection = attributed([
      ("2", "first"), (" + 2", "rest"), (" and ", nil), ("3 * 3", "second"), (".", "period"),
    ])
    let result = try MathReducer().reduce(selection)
    #expect(result.string == "4 and 9.")
    #expect(markers(in: result) == ["4=first", "9=second", ".=period"])
  }

  @Test func convertsRangesAcrossUTF16() throws {
    let selection = attributed([("😀 é 👩‍👩‍👧 ", "emoji"), ("2 + 2", nil), (" 🇺🇸", "flag")])
    let result = try MathReducer().reduce(selection)
    #expect(result.string == "😀 é 👩‍👩‍👧 4 🇺🇸")
    #expect(markers(in: result) == ["😀 é 👩‍👩‍👧 =emoji", " 🇺🇸=flag"])
  }

  @Test func keepsLineBreaksBetweenLines() throws {
    let selection = attributed([("1 + 1", "a"), ("\n", "break"), ("2 * 3", "b")])
    let result = try MathReducer().reduce(selection)
    #expect(result.string == "2\n6")
    #expect(markers(in: result) == ["2=a", "\n=break", "6=b"])
  }

  @Test func rejectsRichTextWithoutExpressions() {
    #expect(throws: ReductionError.self) {
      try MathReducer().reduce(attributed([("hello ", "a"), ("world", "b")]))
    }
  }
}
