import Foundation
import MathParser

/// DDMathParser supplies parsing and evaluation. Its mutable objects stay on the main actor,
/// alongside the Services callback, rather than being shared between concurrent requests.
@MainActor
public struct MathReducer {
  private struct Replacement {
    let range: Range<String.Index>
    let value: String
  }

  private var evaluator: Evaluator
  private var configuration: Configuration
  private let scanner: ExpressionScanner

  public init() {
    evaluator = Evaluator()
    evaluator.functionOverrider = EvaluationCompatibility()
    configuration = Configuration()
    configuration.operatorSet = OperatorSet()
    // The evaluator is case-insensitive, so its default functions match lowercased names.
    let functionNames = Set(Function.standardFunctions.flatMap(\.names).map { $0.lowercased() })
    scanner = ExpressionScanner(configuration: configuration, functionNames: functionNames)
  }

  /// Replaces each mathematical expression in `selection` with its value.
  ///
  /// A single line that is entirely an expression is evaluated as written. Otherwise,
  /// each line is searched separately for expressions within surrounding text, so
  /// "It bakes 2 + 3 now" becomes "It bakes 5 now". Text around each expression,
  /// including surrounding whitespace and line breaks, is preserved.
  ///
  /// - Throws: `ReductionError` when the selection contains no expression to reduce.
  public func reduce(_ selection: String) throws -> String {
    var result = ""
    var cursor = selection.startIndex
    for replacement in try replacements(in: selection) {
      result += selection[cursor..<replacement.range.lowerBound]
      result += replacement.value
      cursor = replacement.range.upperBound
    }
    result += selection[cursor...]
    return result
  }

  /// Replaces each mathematical expression in rich text, as `reduce(_:)` does for plain
  /// text. Each value takes the attributes of its expression's first character; all other
  /// text, attributes, and attachments are unchanged.
  ///
  /// - Throws: `ReductionError` when the selection contains no expression to reduce.
  public func reduce(_ selection: NSAttributedString) throws -> NSAttributedString {
    let text = selection.string
    let result = NSMutableAttributedString(attributedString: selection)
    // Replace from the end so earlier ranges stay valid.
    for replacement in try replacements(in: text).reversed() {
      result.replaceCharacters(in: NSRange(replacement.range, in: text), with: replacement.value)
    }
    return result
  }

  private func replacements(in selection: String) throws -> [Replacement] {
    // DDMathParser recursively parses and evaluates expressions. Bound input
    // before parsing so a large selection cannot overflow its stack or stall Services.
    guard selection.utf8.count <= 4096 else {
      throw ReductionError("Select less text (at most 4 KB).")
    }
    let lines = Self.lines(in: selection)
    guard !lines.isEmpty else {
      throw ReductionError("Select a mathematical expression first.")
    }

    // DDMathParser reads a line break as a space, so "1 + 1⏎1 + 1" would evaluate as
    // 1 + 1 × 1 + 1. Only a single line is tried whole, which keeps forms the scanner
    // leaves alone in prose, such as "0x1F", "50 % 7", or "5!", working when selected.
    var wholeLineError: Error?
    if lines.count == 1, scanner.isExpression(in: selection, line: lines[0]) {
      do {
        return [Replacement(range: lines[0], value: try evaluate(lines[0], in: selection))]
      } catch {
        wholeLineError = error
      }
    }

    let replacements = lines.flatMap { line in
      scanner.candidates(in: selection, line: line).compactMap { candidate -> Replacement? in
        // Many candidates are prose that only resembles math, so a failure here
        // means "not an expression" rather than an error to report.
        guard let value = try? evaluate(candidate.range, in: selection) else { return nil }
        guard let sign = candidate.sign else {
          return Replacement(range: candidate.range, value: value)
        }
        let isNegative = value.hasPrefix("-")
        let resultSign = isNegative ? (sign.text == "+" ? "-" : sign.text) : "+"
        let magnitude = isNegative ? value.dropFirst() : Substring(value)
        return Replacement(range: candidate.range, value: resultSign + sign.spacing + magnitude)
      }
    }
    guard !replacements.isEmpty else {
      throw wholeLineError
        ?? ReductionError("The selection does not contain a mathematical expression.")
    }
    return replacements
  }

  /// Evaluates `range` of `selection`, formatting the value as the original service did.
  private func evaluate(_ range: Range<String.Index>, in selection: String) throws -> String {
    do {
      let expression = try MathParser.Expression(
        string: String(selection[range]), configuration: configuration)
      let value = try evaluator.evaluate(expression)
      guard value.isFinite else {
        throw ReductionError("The expression does not have a finite real result.")
      }
      // Keep the original service's locale-independent NSNumber formatting, including
      // whole numbers without a trailing .0 and a decimal point for fractions.
      return NSNumber(value: value).stringValue
    } catch let error as MathParserError {
      let offset = selection.distance(from: selection.startIndex, to: range.lowerBound)
      throw ReductionError(Self.message(for: error, offset: offset))
    }
  }

  /// Returns the range of each line with surrounding whitespace trimmed, skipping blank
  /// lines. Every Unicode line break separates lines, including "\r\n" and U+2029.
  private static func lines(in text: String) -> [Range<String.Index>] {
    var lines: [Range<String.Index>] = []
    var start = text.startIndex
    while start < text.endIndex {
      let end = text[start...].firstIndex(where: \.isNewline) ?? text.endIndex
      let line = text[start..<end]
      if let first = line.firstIndex(where: { !$0.isWhitespace }),
        let last = line.lastIndex(where: { !$0.isWhitespace })
      {
        lines.append(first..<text.index(after: last))
      }
      start = end < text.endIndex ? text.index(after: end) : end
    }
    return lines
  }

  /// - Parameter offset: The Character offset of the evaluated text within the selection,
  ///   so reported positions count from the start of the selection.
  private static func message(for error: MathParserError, offset: Int) -> String {
    let reason: String
    switch error.kind {
    case .divideByZero:
      reason = "Cannot divide by zero."
    case .unknownFunction(let name):
      reason = "Unknown function: \(name)."
    case .unknownVariable(let name):
      reason = "Unknown variable: \(name)."
    case .missingOpenParenthesis, .missingCloseParenthesis:
      reason = "The parentheses are unbalanced."
    case .invalidArguments, .emptyFunctionArgument:
      reason = "The function arguments are invalid."
    default:
      reason = "The selection does not contain a complete mathematical expression."
    }
    return "\(reason) (At character \(offset + error.range.lowerBound + 1).)"
  }
}

public struct ReductionError: LocalizedError, Sendable {
  public let errorDescription: String?

  public init(_ message: String) {
    errorDescription = message
  }
}
