import Foundation
import MathParser

/// Workarounds for the pinned DDMathParser revision's integer conversions, factorial
/// loops, and aggregate functions. Parsing and ordinary evaluation stay upstream.
struct EvaluationCompatibility: FunctionOverrider {
  func overrideFunction(_ function: String, state: EvaluationState) throws -> Double? {
    let name = function.lowercased()
    switch name {
    case "and", "or", "xor", "lshift", "rshift":
      guard state.arguments.count == 2 else { return nil }
    case "not", "factorial", "factorial2":
      guard state.arguments.count == 1 else { return nil }
    case "max":
      guard !state.arguments.isEmpty else { return nil }
    case "median":
      guard state.arguments.count >= 2 else { return nil }
    default:
      return nil
    }

    // Evaluate each operand once, with these same guards active for nested calls.
    // Re-evaluating the original expressions could change random() operands.
    var values = try state.arguments.map {
      try state.evaluator.evaluate($0, substitutions: state.substitutions)
    }
    guard values.allSatisfy(\.isFinite) else {
      throw ReductionError("The expression does not have a finite real result.")
    }

    var delegatedName = name
    switch name {
    case "and", "or", "not", "xor", "lshift", "rshift":
      // Upstream truncates fractions before converting to Int, but traps when
      // that conversion overflows. Int(exactly:) checks both boundaries safely.
      guard values.allSatisfy({ Int(exactly: $0.rounded(.towardZero)) != nil }) else {
        throw ReductionError("Bitwise operands must fit in a signed 64-bit integer.")
      }
    case "factorial":
      // Integer factorials above 170 cannot fit in Double. Upstream nevertheless
      // loops all the way to the operand, even after the result overflows.
      let value = values[0]
      guard value <= 170 || value.rounded(.down) != value else {
        throw ReductionError("The factorial is too large to represent.")
      }
    case "factorial2":
      let value = values[0]
      guard value >= 1, value.rounded(.down) == value else {
        throw MathParserError(kind: .invalidArguments, range: state.expressionRange)
      }
      guard value <= 300 else {
        throw ReductionError("The double factorial is too large to represent.")
      }
      // Upstream's factorial quotient overflows for odd operands starting at 171,
      // even when the double factorial itself is finite. Let its product function
      // evaluate the factors directly instead.
      values = stride(from: value, through: 1, by: -2).map { $0 }
      delegatedName = "product"
    case "max":
      // Upstream starts at Double.leastNormalMagnitude, producing the wrong
      // answer whenever all operands are zero or negative.
      return values.max()
    case "median":
      // Upstream takes the middle elements without sorting first.
      values.sort()
    default:
      break
    }

    let operands = values.map { Expression(kind: .number($0), range: state.expressionRange) }
    let expression = Expression(
      kind: .function(delegatedName, operands), range: state.expressionRange)
    var evaluator = state.evaluator
    evaluator.functionOverrider = nil
    return try evaluator.evaluate(expression)
  }
}
