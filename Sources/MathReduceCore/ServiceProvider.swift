import AppKit

@MainActor
public final class ServiceProvider: NSObject {
  private let reducer = MathReducer()

  /// This Objective-C selector is the macOS Services ABI; the error is an NSString**, not NSError**.
  @objc(reduceMath:userData:error:)
  public func reduceMath(
    _ pasteboard: NSPasteboard,
    userData: String?,
    error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>?
  ) {
    errorPointer?.pointee = nil
    guard let selection = pasteboard.string(forType: .string) else {
      errorPointer?.pointee = "The selection does not contain plain text."
      return
    }

    do {
      let result = try reducer.reduce(selection)
      // Leave the selection intact if parsing or evaluation fails.
      pasteboard.clearContents()
      guard pasteboard.setString(result, forType: .string) else {
        throw ReductionError("The result could not be written to the pasteboard.")
      }
    } catch {
      errorPointer?.pointee = error.localizedDescription as NSString
    }
  }
}
