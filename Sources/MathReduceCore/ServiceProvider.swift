import AppKit

@MainActor
public final class ServiceProvider: NSObject {
  private let reducer = MathReducer()

  /// Rich representations requested through NSSendTypes, richest first. RTFD carries
  /// attachments such as images, which RTF silently drops.
  private static let richTypes: [NSPasteboard.PasteboardType] = [.rtfd, .rtf]

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
      // Services replace the entire selection, so text around an embedded expression
      // must be returned too. Rich text keeps its formatting and attachments.
      if let (type, richSelection) = Self.richSelection(on: pasteboard, matching: selection) {
        let result = try reducer.reduce(richSelection)
        try Self.write(result, as: type, to: pasteboard)
      } else {
        // Without a faithful rich representation, writing plain text back would
        // delete any attachment, leaving only its placeholder character behind.
        guard !selection.contains(Self.attachmentCharacter) else {
          throw ReductionError("The selection contains an attachment that cannot be preserved.")
        }
        let result = try reducer.reduce(selection)
        // Leave the selection intact if parsing or evaluation fails.
        pasteboard.clearContents()
        guard pasteboard.setString(result, forType: .string) else {
          throw ReductionError("The result could not be written to the pasteboard.")
        }
      }
    } catch {
      errorPointer?.pointee = error.localizedDescription as NSString
    }
  }

  private static let attachmentCharacter = Character("\u{FFFC}")

  /// Returns the richest representation whose text matches the plain-text selection.
  /// A mismatch means the representation lost content, such as RTF dropping an image.
  private static func richSelection(
    on pasteboard: NSPasteboard, matching selection: String
  ) -> (NSPasteboard.PasteboardType, NSAttributedString)? {
    for type in richTypes {
      guard let data = pasteboard.data(forType: type) else { continue }
      let decoded =
        type == .rtfd
        ? NSAttributedString(rtfd: data, documentAttributes: nil)
        : NSAttributedString(rtf: data, documentAttributes: nil)
      if let decoded, decoded.string == selection {
        return (type, decoded)
      }
    }
    return nil
  }

  private static func write(
    _ result: NSAttributedString, as type: NSPasteboard.PasteboardType, to pasteboard: NSPasteboard
  ) throws {
    let range = NSRange(location: 0, length: result.length)
    let data =
      type == .rtfd
      ? result.rtfd(from: range, documentAttributes: [:])
      : result.rtf(from: range, documentAttributes: [:])
    guard let data else {
      throw ReductionError("The result could not be encoded as rich text.")
    }
    pasteboard.clearContents()
    guard pasteboard.setData(data, forType: type),
      pasteboard.setString(result.string, forType: .string)
    else {
      throw ReductionError("The result could not be written to the pasteboard.")
    }
  }
}
