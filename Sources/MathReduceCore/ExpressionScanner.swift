import Foundation
import MathParser

/// Finds candidate expressions embedded in one line of prose.
///
/// A candidate is a maximal run of math tokens bounded by words, punctuation, or the
/// ends of the line. Runs are replaced whole or left alone: trimming operators or
/// operands from a run that fails to evaluate could change its meaning, turning
/// "2 + 3 * x" into "5 * x". Only edges that cannot change the value are trimmed.
///
/// Prose readings win over DDMathParser's when they conflict, because a wrong
/// replacement silently corrupts text while a missed one is easy to notice and
/// select directly. Selecting an expression by itself bypasses this scanner.
struct ExpressionScanner {
  /// A run of text to evaluate in place.
  struct Candidate {
    let range: Range<String.Index>
    /// The leading sign of a run that follows a word, as in "x - 5 + 2". The sign may
    /// be a binary operator joining the run to that word, so the value must keep an
    /// explicit sign: "x - 3" rather than "x 3".
    let sign: Sign?
  }

  struct Sign {
    /// The sign as written, such as "-", "−", or "+".
    let text: String
    /// The whitespace between the sign and its operand, kept in the result.
    let spacing: String
  }

  private struct Token {
    enum Kind {
      case number
      /// An operator, parenthesis, or argument separator.
      case symbol
      /// A constant, or a function name followed directly by "(".
      case name
      /// Prose containing letters or digits. Math touching a word belongs to it.
      case word
      /// Prose without letters or digits, such as sentence punctuation or quotes.
      case punctuation
    }

    var kind: Kind
    let text: String
    let range: Range<String.Index>
    /// A vulgar fraction such as "½", which DDMathParser adds to a preceding number.
    var isFraction = false

    func touches(_ next: Token) -> Bool { range.upperBound == next.range.lowerBound }
  }

  /// Constants that stand alone in prose. Functions that also accept zero arguments,
  /// such as "sum", "count", "random", "yes", and "no", only count when called with
  /// parentheses. Euler's number needs parentheses too, since "e" is a common word
  /// and a common label suffix, as in "vitamin e" or "room 2E".
  private static let constants: Set<String> = [
    "pi", "π", "pi_2", "pi_4", "tau", "τ", "tau_2", "tau_4", "tau_8", "phi", "ϕ", "sqrt2",
    "log2e", "log10e", "ln2", "ln10",
  ]

  /// Operators that mean something else in prose: "50%" is a percentage rather than
  /// a modulo, "20°" a temperature rather than radians, and "~5" an approximation
  /// rather than a bitwise complement.
  private static let proseOperatorFunctions: Set<String> = ["mod", "dtor", "not"]
  /// Comparisons read as statements in prose: "2 + 2 = 4" should not become "1".
  private static let comparisonFunctions: Set<String> = [
    "l_eq", "l_neq", "l_lt", "l_gt", "l_ltoe", "l_gtoe",
  ]
  private static let signs: Set<String> = ["+", "-", "−"]
  private static let factorials: Set<String> = ["!", "!!"]

  private let configuration: Configuration
  private let functionNames: Set<String>
  private let operatorCharacters: Set<Character>
  private let proseOperatorCharacters: Set<Character>
  private let comparisonTokens: Set<String>

  /// - Parameters:
  ///   - configuration: The parser configuration used to evaluate candidates.
  ///   - functionNames: Lowercased names of every function the evaluator can call.
  init(configuration: Configuration, functionNames: Set<String>) {
    self.configuration = configuration
    self.functionNames = functionNames
    let operators = configuration.operatorSet.operators
    func tokens(of functions: Set<String>) -> [String] {
      operators.filter { functions.contains($0.function) }.flatMap(\.tokens)
    }
    operatorCharacters = Set(operators.flatMap(\.tokens).flatMap { $0 + $0.lowercased() })
    proseOperatorCharacters = Set(
      tokens(of: Self.proseOperatorFunctions).filter { $0.count == 1 }.compactMap(\.first))
    comparisonTokens = Set(tokens(of: Self.comparisonFunctions))
  }

  /// Returns the candidate expressions in `line`, a range of `text`, in order.
  func candidates(in text: String, line: Range<String.Index>) -> [Candidate] {
    let content = Self.contentStart(of: line, in: text)..<line.upperBound
    let tokens = tokens(in: text, line: content)
    return runs(of: tokens).compactMap { candidate(from: $0, of: tokens, in: text) }
  }

  /// Whether `line` may be evaluated whole, as DDMathParser reads it. A line with
  /// prose words is not: DDMathParser reads every word as a function, so
  /// "max(1, 2) and (3, 4)" would evaluate as max(1, 2) × and(3, 4). Neither is a
  /// list item such as "- 2 + 2", which it reads as -2 + 2. A single word, such as
  /// "e" or "random", can still be selected and evaluated by itself.
  func isExpression(in text: String, line: Range<String.Index>) -> Bool {
    guard Self.contentStart(of: line, in: text) == line.lowerBound else { return false }
    let tokens = tokens(in: text, line: line)
    guard tokens.count > 1 else { return true }
    // A comma outside a function's arguments never evaluates, and DDMathParser traps
    // on some, such as "1!!°,1", instead of reporting an error.
    var parentheses: [Bool] = []
    for (index, token) in tokens.enumerated() {
      if token.kind == .word { return false }
      guard token.kind == .symbol else { continue }
      switch token.text {
      case "(": parentheses.append(Self.opensCall(index > 0 ? tokens[index - 1] : nil, token))
      case ")": _ = parentheses.popLast()
      case ",": if parentheses.last != true { return false }
      default: break
      }
    }
    return true
  }

  /// Returns where a line's content starts, after any list marker such as "- ", "* ",
  /// "• ", "1. ", "2) ", or "a) ". DDMathParser would read "- 2 + 2" as -2 + 2.
  static func contentStart(of line: Range<String.Index>, in text: String) -> String.Index {
    let characters = text[line]
    guard let first = characters.first else { return line.lowerBound }
    var index = characters.index(after: characters.startIndex)
    if !"-*+•‣◦⁃–—".contains(first) {
      let digits = characters.prefix(while: \.isASCIIDigit)
      if (1...3).contains(digits.count) {
        index = digits.endIndex
      } else if !(first.isASCII && first.isLetter) {
        return line.lowerBound
      }
      guard index < characters.endIndex, ".)".contains(characters[index]) else {
        return line.lowerBound
      }
      index = characters.index(after: index)
    }
    guard index < characters.endIndex, characters[index].isWhitespace,
      let content = characters[index...].firstIndex(where: { !$0.isWhitespace })
    else {
      return line.lowerBound
    }
    return content
  }

  // MARK: - Tokens

  private func tokens(in text: String, line: Range<String.Index>) -> [Token] {
    var tokens: [Token] = []
    var pieceStart = line.lowerBound
    var index = line.lowerBound
    while index < line.upperBound {
      let next = text.index(after: index)
      if isSeparator(at: index, in: text, line: line) {
        tokens += tokenize(text, pieceStart..<index)
        let joinsWord =
          index > line.lowerBound && next < line.upperBound
          && text[text.index(before: index)].isAlphanumeric && text[next].isAlphanumeric
        // Punctuation between letters or digits, as in "10:30" or "it’s", is part
        // of a word.
        tokens.append(
          Token(
            kind: joinsWord ? .word : .punctuation, text: String(text[index]),
            range: index..<next))
        pieceStart = next
      }
      index = next
    }
    tokens += tokenize(text, pieceStart..<line.upperBound)
    return markingJoinedNumbers(tokens)
  }

  /// Prose punctuation is split off before tokenizing. DDMathParser would otherwise
  /// read an apostrophe or quote as the start of a quoted variable that swallows the
  /// following text, read "$" as a variable, and absorb characters such as ":" or
  /// "“" into identifiers, as in "Total:2" or "“2".
  private func isSeparator(
    at index: String.Index, in text: String, line: Range<String.Index>
  ) -> Bool {
    let character = text[index]
    if character == "." {
      // A period beside a digit is a decimal point; otherwise it ends a sentence.
      let before = index > line.lowerBound ? text[text.index(before: index)] : nil
      let afterIndex = text.index(after: index)
      let after = afterIndex < line.upperBound ? text[afterIndex] : nil
      return before?.isASCIIDigit != true && after?.isASCIIDigit != true
    }
    if proseOperatorCharacters.contains(character) { return true }
    // Math symbols stay, since some name functions, such as "∑". Other symbols, such
    // as "`", "©", and emoji, are prose.
    guard
      character.isPunctuation || character.isCurrencySymbol
        || (character.isSymbol && !character.isMathSymbol)
    else { return false }
    // Underscores appear in constant names such as "pi_2", and superscript
    // parentheses in exponents such as "2⁽³⁾".
    return character != "_" && !"⁽⁾".contains(character)
      && !operatorCharacters.contains(character)
  }

  private func tokenize(_ text: String, _ piece: Range<String.Index>) -> [Token] {
    guard !piece.isEmpty else { return [] }
    let source = text[piece]
    let raw: [RawToken]
    do {
      raw = try Tokenizer(string: String(source), configuration: configuration).tokenize()
    } catch {
      // With quotes, "$", and stray periods split off, every remaining character
      // starts some token. Should tokenizing still fail, treat the piece as prose.
      return [Token(kind: .word, text: String(source), range: piece)]
    }

    // DDMathParser reports token ranges as Character offsets. Hexadecimal and octal
    // ranges start after their "0x" or "0o" prefix.
    let boundaries = Array(source.indices) + [piece.upperBound]
    return raw.enumerated().map { position, token in
      let next = raw.indices.contains(position + 1) ? raw[position + 1] : nil
      let prefix = token is HexNumberToken || token is OctalNumberToken ? 2 : 0
      return Token(
        kind: kind(of: token, next: next), text: token.string,
        range: boundaries[token.range.lowerBound - prefix]..<boundaries[token.range.upperBound],
        isFraction: token is FractionNumberToken)
    }
  }

  private func kind(of token: RawToken, next: RawToken?) -> Token.Kind {
    switch token {
    case is OperatorToken:
      if comparisonTokens.contains(token.string.lowercased()) { return .punctuation }
      // Word operators read as prose.
      return token.string.contains(where: \.isLetter) ? .word : .symbol
    case is ExponentToken:
      return .symbol
    case is IdentifierToken:
      let name = token.string.lowercased()
      if let next, next is OperatorToken, next.string == "(",
        next.range.lowerBound == token.range.upperBound, functionNames.contains(name)
      {
        return .name
      }
      if Self.constants.contains(name) { return .name }
      return token.string.contains(where: \.isAlphanumeric) ? .word : .punctuation
    case is VariableToken:
      return .word
    default:
      return .number
    }
  }

  /// Numbers touching each other form one word, as in the version "1.2.3", which
  /// DDMathParser would multiply as 1.2 × .3. A grouping comma, as in "1,000",
  /// joins numbers too: DDMathParser cannot parse it, and the digits on either side
  /// must not be reduced separately. Marking the joint as a word leaves every run
  /// touching it alone.
  private func markingJoinedNumbers(_ tokens: [Token]) -> [Token] {
    var marked = tokens
    for index in tokens.indices.dropFirst() {
      let previous = tokens[index - 1]
      let token = tokens[index]
      guard previous.kind == .number, previous.touches(token) else { continue }
      let next = index + 1 < tokens.count ? tokens[index + 1] : nil
      let continuesNumber = token.kind == .number && !token.isFraction
      let isGroupingComma =
        token.kind == .symbol && token.text == ","
        && next.map {
          $0.kind == .number && token.touches($0) && Self.isDigitGroup($0.text)
        } == true
      if continuesNumber || isGroupingComma { marked[index].kind = .word }
    }
    return marked
  }

  /// Whether `text` continues a number after a grouping comma: three digits,
  /// optionally followed by a fraction, as in the "000" of "1,000" or "1,000.5".
  private static func isDigitGroup(_ text: String) -> Bool {
    let digits = text.prefix(while: \.isASCIIDigit)
    return digits.count == 3 && (digits.endIndex == text.endIndex || text[digits.endIndex] == ".")
  }

  // MARK: - Runs

  /// Splits tokens into runs of math, returning the token index range of each run.
  private func runs(of tokens: [Token]) -> [Range<Int>] {
    var runs: [Range<Int>] = []
    var start = 0
    // Whether each open parenthesis in the current run begins a function's arguments.
    var parentheses: [Bool] = []
    for (index, token) in tokens.enumerated() {
      let previous = index > start ? tokens[index - 1] : nil
      // Commas separate prose clauses and list items, as in "2 + 2, 3 + 3" or
      // "(2 + 2, then 3)", except between a function's arguments.
      let separates =
        token.kind == .word || token.kind == .punctuation
        || (token.kind == .symbol && token.text == "," && parentheses.last != true)
      if separates || previous.map({ Self.isSpacedApart($0, token) }) == true {
        if start < index { runs.append(start..<index) }
        start = separates ? index + 1 : index
        parentheses = []
      }
      if !separates, token.kind == .symbol {
        if token.text == "(" { parentheses.append(Self.opensCall(previous, token)) }
        if token.text == ")" { _ = parentheses.popLast() }
      }
    }
    if start < tokens.count { runs.append(start..<tokens.count) }
    return runs
  }

  /// Whether `token`, an open parenthesis, begins a function's arguments, as in "max(".
  private static func opensCall(_ previous: Token?, _ token: Token) -> Bool {
    guard let previous else { return false }
    return previous.kind == .name && previous.touches(token)
  }

  /// Whether a space between two operands separates values rather than implying
  /// multiplication: "1 2 3" lists numbers, and "Table 5 (6)" and "Smith (2026) 2"
  /// are parentheticals. Names still multiply, as in "2 pi", and a fraction after a
  /// number completes it, as in "1 ½".
  private static func isSpacedApart(_ previous: Token, _ token: Token) -> Bool {
    let endsOperand = previous.kind == .number || (previous.kind == .symbol && previous.text == ")")
    let startsOperand =
      (token.kind == .number && !token.isFraction) || (token.kind == .symbol && token.text == "(")
    return endsOperand && startsOperand && !previous.touches(token)
  }

  private func candidate(from run: Range<Int>, of tokens: [Token], in text: String) -> Candidate? {
    let before = run.lowerBound > 0 ? tokens[run.lowerBound - 1] : nil
    let after = run.upperBound < tokens.count ? tokens[run.upperBound] : nil
    // Math touching a word belongs to it, as in "f(2)", "abc123+4", or "5kg".
    if let before, before.kind == .word, before.touches(tokens[run.lowerBound]) { return nil }
    if let after, after.kind == .word, tokens[run.upperBound - 1].touches(after) { return nil }
    if isNumbering(tokens[run]) { return nil }

    var lower = run.lowerBound
    var upper = run.upperBound
    // Runs contain no prose, so every parenthesis in them is a symbol.
    var opens = tokens[run].count(where: { $0.text == "(" })
    var closes = tokens[run].count(where: { $0.text == ")" })
    while lower < upper {
      if tokens[lower].text == "(", opens > closes {
        // Prose parentheses, as in "(roughly 2 + 2)", can leave one unmatched.
        lower += 1
        opens -= 1
      } else if tokens[upper - 1].text == ")", closes > opens {
        upper -= 1
        closes -= 1
      } else if Self.factorials.contains(tokens[upper - 1].text) {
        // A trailing "!" ends a sentence: "I won 5!" Factorials elsewhere still work.
        upper -= 1
      } else {
        break
      }
    }
    guard lower < upper else { return nil }

    let first = tokens[lower]
    let last = tokens[upper - 1]
    // A lone number, even signed or in parentheses, is already reduced. Replacing
    // "(2026)" with "2026" would only drop the parentheses.
    let operands = tokens[lower..<upper].filter {
      !($0.kind == .symbol && ($0.text == "(" || $0.text == ")" || Self.signs.contains($0.text)))
    }
    if operands.count == 1, operands[0].kind == .number { return nil }
    // Signs and parentheses alone, as in "x -", have nothing to evaluate.
    if operands.isEmpty { return nil }

    var end = last.range.upperBound
    if last.kind == .number, last.text.hasSuffix(".") {
      // "2 + 2." ends a sentence; "2." and "2" have the same value.
      end = text.index(before: end)
    }
    var sign: Sign?
    if Self.signs.contains(first.text), lower == run.lowerBound, before?.kind == .word {
      let spacing = text[first.range.upperBound..<tokens[lower + 1].range.lowerBound]
      sign = Sign(text: first.text, spacing: String(spacing))
    }
    return Candidate(range: first.range.lowerBound..<end, sign: sign)
  }

  /// Dates, phone numbers, and ranges such as "2026-10-19", "555-1234", or "10-20"
  /// join numbers with unspaced hyphens, and dates such as "10/19/2026" chain
  /// unspaced slashes. Prose rarely means subtraction or division there.
  private func isNumbering(_ tokens: ArraySlice<Token>) -> Bool {
    var slashes = 0
    for index in tokens.indices.dropFirst().dropLast() {
      let token = tokens[index]
      let previous = tokens[index - 1]
      let next = tokens[index + 1]
      guard previous.kind == .number, next.kind == .number, previous.touches(token),
        token.touches(next)
      else { continue }
      if token.text == "-" { return true }
      if token.text == "/" { slashes += 1 }
    }
    return slashes >= 2
  }
}

extension Character {
  fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
  fileprivate var isAlphanumeric: Bool { isLetter || isNumber }
}
