import Foundation
import MathReduceCore
import Testing

/// Expressions inside prose, and selections spanning several lines.
@MainActor
struct EmbeddedExpressionTests {
  @Test(arguments: [
    (
      "It bakes PI * 1 + 23.22712957677745 tested.",
      "It bakes 26.36872223036724 tested."
    ),
    (
      "This is 1 + 1 my way or the PI way.",
      "This is 2 my way or the 3.141592653589793 way."
    ),
    ("hello 2 + 3", "hello 5"),
    ("The total is 2 + 2.", "The total is 4."),
    ("use PI.", "use 3.141592653589793."),
    ("2+2, 3+3", "4, 6"),
    ("x = 2 + 2; y = 3 * 3", "x = 4; y = 9"),
    ("x: (1920 - (2 * 160)) / 2, parent: this", "x: 800, parent: this"),
    ("sum(1, 2, 3) apples", "6 apples"),
    ("max(-5, -2) is larger", "-2 is larger"),
    ("max(1, 2) and (3, 4)", "2 and (3, 4)"),
    ("SIN(0) and Pi", "0 and 3.141592653589793"),
    ("sin(PI/2) is one", "1 is one"),
    ("τ / 2 equals π", "3.141592653589793 equals 3.141592653589793"),
    ("2 pi radians", "6.283185307179586 radians"),
    ("costs .5 + .25 each", "costs 0.75 each"),
    ("about 1e3 + 1 items", "about 1001 items"),
    ("0x1F + 1 in hex", "32 in hex"),
    ("the octal 0o17 + 1 here", "the octal 16 here"),
    ("0xff+1 and 0XA + 0", "256 and 10"),
    ("2 × 3 ÷ 4 cups", "1.5 cups"),
    ("√16 + 1 apples", "5 apples"),
    ("2² + 1 equals five", "5 equals five"),
    ("1 ½ + 1 cups", "2.5 cups"),
    ("5! + 1 ways", "121 ways"),
    ("2**10 bytes", "1024 bytes"),
    ("In 2026 2+2 is 4", "In 2026 4 is 4"),
    ("2\u{00A0}+\u{00A0}2 apples", "4 apples"),
    ("2 + 1/0 or 2 + 2", "2 + 1/0 or 4"),
  ])
  func reducesExpressionsInProse(selection: String, expected: String) throws {
    #expect(try MathReducer().reduce(selection) == expected)
  }

  @Test(arguments: [
    ("It's 2+2 and that's 3*3.", "It's 4 and that's 9."),
    ("He said \"2+2\" is 4", "He said \"4\" is 4"),
    ("He said “2+2” is 4", "He said “4” is 4"),
    ("He said '2+2' is 4", "He said '4' is 4"),
    ("$5 + 3 total", "$8 total"),
    ("€5 + 3 total", "€8 total"),
    ("`2+2` in code", "`4` in code"),
    ("🍕 2+2 🍕", "🍕 4 🍕"),
    ("[2+2] and {3*3}", "[4] and {9}"),
    ("e.g. 2+2", "e.g. 4"),
    ("2+2?!", "4?!"),
    ("2+2!?", "4!?"),
    ("2+2...", "4..."),
    ("2+2…", "4…"),
    ("(2+2).", "4."),
    ("sin(0).", "0."),
    ("That is 2 + 3!", "That is 5!"),
  ])
  func keepsSurroundingPunctuation(selection: String, expected: String) throws {
    #expect(try MathReducer().reduce(selection) == expected)
  }

  @Test(arguments: [
    ("(roughly 2 + 2)", "(roughly 4)"),
    ("the answer (2+2) is", "the answer 4 is"),
    ("It costs (1 + 2)", "It costs 3"),
    ("(2 + 2, then 3)", "(4, then 3)"),
    ("(2+3", "(5"),
    ("2+3)", "5)"),
    ("Table 5 (6) shows 2+2", "Table 5 (6) shows 4"),
    ("Smith (2026) said 2+2", "Smith (2026) said 4"),
    ("Figure 2 (3+4)", "Figure 2 7"),
  ])
  func handlesParentheses(selection: String, expected: String) throws {
    #expect(try MathReducer().reduce(selection) == expected)
  }

  /// A sign after a word may be a binary operator joining the expression to that word,
  /// so the value keeps an explicit sign and the original spacing.
  @Test(arguments: [
    ("x - 5 + 2", "x - 3"),
    ("x -5 + 9", "x +4"),
    ("x − 5 + 2", "x − 3"),
    ("x + 5 - 9", "x - 4"),
    ("x + 2 * 3", "x + 6"),
    ("Total: -5 + 9", "Total: 4"),
    ("-5 + 9 degrees", "4 degrees"),
  ])
  func keepsLeadingSigns(selection: String, expected: String) throws {
    #expect(try MathReducer().reduce(selection) == expected)
  }

  @Test(arguments: [
    ("- 2+2 apples", "- 4 apples"),
    ("* 2+2", "* 4"),
    ("+ 2+2", "+ 4"),
    ("• 2+2", "• 4"),
    ("– 2+2", "– 4"),
    ("1. 2+2", "1. 4"),
    ("1) 2+2", "1) 4"),
    ("12. 2+2", "12. 4"),
    ("a) 3*3", "a) 9"),
    ("- [ ] 2+2 todo", "- [ ] 4 todo"),
    ("> 2+2 quoted", "> 4 quoted"),
    ("# 2+2 heading", "# 4 heading"),
  ])
  func keepsListMarkers(selection: String, expected: String) throws {
    #expect(try MathReducer().reduce(selection) == expected)
  }

  @Test(arguments: [
    ("1 + 1\n1 + 1", "2\n2"),
    ("1 + 1\r\n2 + 2", "2\r\n4"),
    ("1 + 1\r2 + 2", "2\r4"),
    ("1 + 1\u{2028}2 + 2", "2\u{2028}4"),
    ("1 + 1\u{2029}2 + 2", "2\u{2029}4"),
    ("2 + 2\n\nThe answer\n3 * 3", "4\n\nThe answer\n9"),
    ("\t1 + 1 \n 2 + 2\t", "\t2 \n 4\t"),
    ("Total:\n2 + 2", "Total:\n4"),
    ("PI\n2 + 2", "3.141592653589793\n4"),
    ("- 1 + 1\n- 2 * 3", "- 2\n- 6"),
    // On a line of its own within a larger selection, a lone number or word is
    // prose, as are forms such as "5!" that read differently in prose.
    ("No\n2 + 2", "No\n4"),
    ("e\n2 + 2", "e\n4"),
    ("0x1F\n2 + 2", "0x1F\n4"),
    ("5!\n2 + 2", "5!\n4"),
    ("1.50\n2 + 2", "1.50\n4"),
  ])
  func reducesEachLineSeparately(selection: String, expected: String) throws {
    #expect(try MathReducer().reduce(selection) == expected)
  }

  /// Prose that resembles math is left alone, because a wrong replacement silently
  /// corrupts text while a missed one can be selected and reduced directly.
  @Test(arguments: [
    // Words, including words that name functions DDMathParser would call.
    "hello world", "I have 3 apples", "the sum of 2 and 3", "I pick 2 random numbers",
    "yes no", "Vitamin e is good", "a 'quoted' word", "It's", "(see below)",
    // Math touching a word belongs to it.
    "f(2+2)", "Total:2+2", "abc123+4", "5kg + 3kg", "Room 2E", "2e", "COVID-19 cases",
    "e-mail me", "v1.2.3 + 1 build",
    // Removing operands would change the meaning of an incomplete expression.
    "2 + 3 * x", "(1 +\n2)", "x -", "x + ", "it −", "x (-)", "word ()",
    // Numbers that are already reduced, even in parentheses or with a sign.
    "the value (5) is", "Smith (2026) wrote", "It was -5 today", "It was +5 today",
    "It was −5 today", "1 2 3 go", "1, 2, 3", "1.50 apples", "0x1F apples",
    // Sentence punctuation after a number.
    "I won 5!", "Wow, 100!!",
    // Numbering: versions, dates, times, phone numbers, ranges, and grouping.
    "1.2.3 is out", "2026-10-19 meeting", "10/19/2026 is the date", "10:30 am",
    "555-1234 call", "1-800-555-1234 call", "pages 10-20", "x is 2-1", "10–20 minutes",
    "1,000 + 500 dollars", "1,000,000 people", "1,000.50 + 1 total",
    // Operators that mean something else in prose.
    "Save 50% + 10% now", "50 % 7 later", "It was 20° + 5° warmer", "It takes ~5 minutes",
    "So 5 > 3 here", "x <= 10",
  ])
  func leavesProseAlone(selection: String) {
    #expect(throws: ReductionError.self) { try MathReducer().reduce(selection) }
  }

  /// Prose around a real expression stays exactly as written.
  @Test(arguments: [
    ("So 2 + 2 = 4", "So 4 = 4"),
    ("if 5 > 2 + 2 then", "if 5 > 4 then"),
    ("Meeting on 2026-10-19 costs 5*20", "Meeting on 2026-10-19 costs 100"),
    ("Call 555-1234 for 2+2", "Call 555-1234 for 4"),
    ("pages 10-20 and 2 + 2", "pages 10-20 and 4"),
    ("on 10/19/2026 we had 3*3", "on 10/19/2026 we had 9"),
    ("at 10:30 we had 3*3", "at 10:30 we had 9"),
    ("version 1.2.3 has 2*3 bugs", "version 1.2.3 has 6 bugs"),
    ("Save 50% today on 2*3 things", "Save 50% today on 6 things"),
    ("It takes ~5 minutes or 2*3", "It takes ~5 minutes or 6"),
    ("Room 2E has 2*3 seats", "Room 2E has 6 seats"),
    ("It costs 1,000 + 500 or 2 + 2", "It costs 1,000 + 500 or 4"),
    ("It is 1/0 but 2+2", "It is 1/0 but 4"),
    ("x + 2 * y or 2 + 2", "x + 2 * y or 4"),
    // Each argument of an unknown function is reduced separately.
    ("foo(1, 2 + 2)", "foo(1, 4)"),
    ("f(x, 3 * 3)", "f(x, 9)"),
  ])
  func reducesOnlyTheExpressions(selection: String, expected: String) throws {
    #expect(try MathReducer().reduce(selection) == expected)
  }

  @Test func reducesLargeProseQuickly() throws {
    let sentence = "It is (1 + 1) * 2, then x - 5 + 2; "
    let selection = String(repeating: sentence, count: 4096 / sentence.utf8.count)
    let expected = String(
      repeating: "It is 4, then x - 3; ", count: 4096 / sentence.utf8.count)
    let start = ContinuousClock.now
    #expect(try MathReducer().reduce(selection) == expected)
    #expect(ContinuousClock.now - start < .seconds(5))
  }
}
