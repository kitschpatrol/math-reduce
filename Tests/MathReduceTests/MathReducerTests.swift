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
    ("  2 + 2\n", "4"),
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
    #expect(try MathReducer().reduce(String(repeating: " ", count: 4095) + "1") == "1")
    for expression in [
      String(repeating: "(", count: 20_000) + "1", String(repeating: "π", count: 2049),
    ] {
      #expect(throws: ReductionError.self) { try MathReducer().reduce(expression) }
    }
  }

  @Test(arguments: [
    "", " \n", "2 +", "(2+3", "1/0", "sqrt(-1)", "10**1000", "hello 2 + 3", "$missing",
    "1e30 ^ 1", "sqrt(-1) & 1", "~1e30", "1 | 1e30", "1 << 1e30", "1e30 >> 1",
    "9223372036854775808 & 1", "-1e30 & 1", "1e1000 ^ 1", "1 ^ (1e30 ^ 1)",
    "1000000000000!", "factorial2(1000000000000)", "171!", "301!!", "1.5!!", "0!!",
    "max()", "median(1)", "and(1)", "factorial(1, 2)",
  ])
  func rejectsInvalidSelection(expression: String) {
    #expect(throws: ReductionError.self) { try MathReducer().reduce(expression) }
  }
}
