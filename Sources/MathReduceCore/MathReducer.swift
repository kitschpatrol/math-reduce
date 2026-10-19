import Foundation
import MathParser

/// DDMathParser supplies parsing and evaluation. Its mutable objects stay on the main actor,
/// alongside the Services callback, rather than being shared between concurrent requests.
@MainActor
public struct MathReducer {
  private var evaluator: Evaluator
  private var configuration: Configuration

  public init() {
    evaluator = Evaluator()
    evaluator.functionOverrider = EvaluationCompatibility()
    configuration = Configuration()
    configuration.operatorSet = OperatorSet()
  }

  public func reduce(_ selection: String) throws -> String {
    // DDMathParser recursively parses and evaluates expressions. Bound input
    // before parsing so a large selection cannot overflow its stack or stall Services.
    guard selection.utf8.count <= 4096 else {
      throw ReductionError("Select a shorter expression (at most 4 KB of text).")
    }
    guard !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ReductionError("Select a mathematical expression first.")
    }

    do {
      let expression = try MathParser.Expression(string: selection, configuration: configuration)
      let value = try evaluator.evaluate(expression)
      guard value.isFinite else {
        throw ReductionError("The expression does not have a finite real result.")
      }
      // Keep the original service's locale-independent NSNumber formatting, including
      // whole numbers without a trailing .0 and a decimal point for fractions.
      return NSNumber(value: value).stringValue
    } catch let error as MathParserError {
      throw ReductionError(Self.message(for: error))
    }
  }

  private static func message(for error: MathParserError) -> String {
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
      reason = "Select a complete mathematical expression without surrounding text."
    }
    return "\(reason) (At character \(error.range.lowerBound + 1).)"
  }
}

public struct ReductionError: LocalizedError, Sendable {
  public let errorDescription: String?

  public init(_ message: String) {
    errorDescription = message
  }
}
