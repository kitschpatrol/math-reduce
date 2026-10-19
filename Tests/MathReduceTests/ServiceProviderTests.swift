import AppKit
import MathReduceCore
import Testing

@MainActor
struct ServiceProviderTests {
  @Test func replacesTextUsingServicesSelector() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("2**10", forType: .string)
    let provider = ServiceProvider()
    #expect(provider.responds(to: NSSelectorFromString("reduceMath:userData:error:")))
    var error: NSString? = "stale error"
    provider.reduceMath(pasteboard, userData: nil, error: &error)
    #expect(error == nil)
    #expect(pasteboard.string(forType: .string) == "1024")
  }

  @Test(arguments: ["1 / 0", "1e30 ^ 1", "1000000000000!", "sqrt(-1)"])
  func preservesPasteboardOnFailure(expression: String) {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString(expression, forType: .string)
    var error: NSString?
    ServiceProvider().reduceMath(pasteboard, userData: nil, error: &error)
    #expect(error != nil)
    #expect(pasteboard.string(forType: .string) == expression)
  }

  @Test func rejectsNonTextPasteboard() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setData(Data([1, 2, 3]), forType: .png)
    var error: NSString?
    ServiceProvider().reduceMath(pasteboard, userData: nil, error: &error)
    #expect(error != nil)
    #expect(pasteboard.data(forType: .png) == Data([1, 2, 3]))
    ServiceProvider().reduceMath(pasteboard, userData: nil, error: nil)
  }
}
