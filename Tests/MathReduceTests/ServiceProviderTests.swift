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

  @Test func reducesExpressionsInPlainTextProse() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("It bakes 2 + 2 now\nand 3 * 3 later", forType: .string)
    var error: NSString?
    ServiceProvider().reduceMath(pasteboard, userData: nil, error: &error)
    #expect(error == nil)
    #expect(pasteboard.string(forType: .string) == "It bakes 4 now\nand 9 later")
  }

  @Test func keepsRichTextFormattingOutsideExpressions() throws {
    let regular = try #require(NSFont(name: "Helvetica", size: 12))
    let bold = try #require(NSFont(name: "Helvetica-Bold", size: 12))
    let link = try #require(URL(string: "https://example.com"))
    let selection = NSMutableAttributedString(
      string: "It bakes 2 + 2 now", attributes: [.font: regular])
    selection.addAttribute(.font, value: bold, range: NSRange(location: 3, length: 5))
    selection.addAttribute(.link, value: link, range: NSRange(location: 15, length: 3))
    let pasteboard = Self.pasteboard(with: selection, types: [.rtf])
    defer { pasteboard.releaseGlobally() }

    var error: NSString?
    ServiceProvider().reduceMath(pasteboard, userData: nil, error: &error)
    #expect(error == nil)
    #expect(pasteboard.string(forType: .string) == "It bakes 4 now")
    let result = try #require(
      pasteboard.data(forType: .rtf).flatMap {
        NSAttributedString(rtf: $0, documentAttributes: nil)
      })
    #expect(result.string == "It bakes 4 now")
    var boldRange = NSRange()
    let font = result.attribute(.font, at: 3, effectiveRange: &boldRange) as? NSFont
    #expect(font?.fontName == "Helvetica-Bold")
    #expect(boldRange == NSRange(location: 3, length: 5))
    var linkRange = NSRange()
    let resultLink = result.attribute(.link, at: 11, effectiveRange: &linkRange)
    #expect((resultLink as? URL ?? (resultLink as? String).flatMap(URL.init(string:))) == link)
    #expect(linkRange == NSRange(location: 11, length: 3))
  }

  @Test func keepsAttachmentsUsingRTFD() throws {
    let selection = Self.selectionWithAttachment()
    let pasteboard = Self.pasteboard(with: selection, types: [.rtfd, .rtf])
    defer { pasteboard.releaseGlobally() }

    var error: NSString?
    ServiceProvider().reduceMath(pasteboard, userData: nil, error: &error)
    #expect(error == nil)
    #expect(pasteboard.string(forType: .string) == "4 \u{FFFC} now")
    let result = try #require(
      pasteboard.data(forType: .rtfd).flatMap {
        NSAttributedString(rtfd: $0, documentAttributes: nil)
      })
    #expect(result.string == "4 \u{FFFC} now")
    #expect(result.attribute(.attachment, at: 2, effectiveRange: nil) is NSTextAttachment)
  }

  /// RTF drops attachments, and writing the plain text back would leave only their
  /// placeholder characters, so the selection must stay as it is.
  @Test(arguments: [[NSPasteboard.PasteboardType.rtf], []])
  func refusesToDropAttachments(types: [NSPasteboard.PasteboardType]) {
    let selection = Self.selectionWithAttachment()
    let pasteboard = Self.pasteboard(with: selection, types: types)
    defer { pasteboard.releaseGlobally() }
    let original = pasteboard.data(forType: .rtf)

    var error: NSString?
    ServiceProvider().reduceMath(pasteboard, userData: nil, error: &error)
    #expect(error != nil)
    #expect(pasteboard.string(forType: .string) == selection.string)
    #expect(pasteboard.data(forType: .rtf) == original)
  }

  /// Rich text that does not match the plain text is not trusted.
  @Test(arguments: [
    encoded(NSAttributedString(string: "Something else"), as: .rtf) ?? Data(),
    Data("not rich text".utf8),
  ])
  func fallsBackToPlainTextForMismatchedRichText(rtf: Data) {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    pasteboard.setData(rtf, forType: .rtf)
    pasteboard.setString("It bakes 2 + 2 now", forType: .string)

    var error: NSString?
    ServiceProvider().reduceMath(pasteboard, userData: nil, error: &error)
    #expect(error == nil)
    #expect(pasteboard.string(forType: .string) == "It bakes 4 now")
    #expect(pasteboard.data(forType: .rtf) == nil)
  }

  @Test func preservesRichPasteboardOnFailure() {
    let selection = NSAttributedString(string: "hello world")
    let pasteboard = Self.pasteboard(with: selection, types: [.rtfd, .rtf])
    defer { pasteboard.releaseGlobally() }
    let rtf = pasteboard.data(forType: .rtf)
    let rtfd = pasteboard.data(forType: .rtfd)

    var error: NSString?
    ServiceProvider().reduceMath(pasteboard, userData: nil, error: &error)
    #expect(error != nil)
    #expect(pasteboard.string(forType: .string) == "hello world")
    #expect(pasteboard.data(forType: .rtf) == rtf)
    #expect(pasteboard.data(forType: .rtfd) == rtfd)
  }

  /// Round-trips a selection through a text view as AppKit does for a Services request:
  /// the view writes its selection, the service runs, and the view reads the result.
  @Test(arguments: [false, true])
  func roundTripsThroughATextView(isRichText: Bool) throws {
    let bold = try #require(NSFont(name: "Helvetica-Bold", size: 12))
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
    view.isRichText = isRichText
    let selection = NSMutableAttributedString(string: "It bakes 2 + 2 now\n3 * 3")
    if isRichText {
      selection.addAttribute(.font, value: bold, range: NSRange(location: 3, length: 5))
    }
    view.textStorage?.setAttributedString(selection)
    view.setSelectedRange(NSRange(location: 0, length: selection.length))
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    #expect(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))

    var error: NSString?
    ServiceProvider().reduceMath(pasteboard, userData: nil, error: &error)
    #expect(error == nil)
    #expect(view.readSelection(from: pasteboard))
    #expect(view.string == "It bakes 4 now\n9")
    if isRichText {
      var range = NSRange()
      let font = view.textStorage?.attribute(.font, at: 3, effectiveRange: &range) as? NSFont
      #expect(font?.fontName == "Helvetica-Bold")
      #expect(range == NSRange(location: 3, length: 5))
    }
  }

  @Test func keepsAttachmentsThroughATextView() throws {
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
    view.isRichText = true
    view.importsGraphics = true
    view.textStorage?.setAttributedString(Self.selectionWithAttachment())
    view.setSelectedRange(NSRange(location: 0, length: view.textStorage?.length ?? 0))
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    #expect(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))

    var error: NSString?
    ServiceProvider().reduceMath(pasteboard, userData: nil, error: &error)
    #expect(error == nil)
    #expect(view.readSelection(from: pasteboard))
    #expect(view.string == "4 \u{FFFC} now")
    #expect(
      view.textStorage?.attribute(.attachment, at: 2, effectiveRange: nil) is NSTextAttachment)
  }

  /// Writes `selection` as a host application would for a Services request: the
  /// requested rich types plus plain text.
  private static func pasteboard(
    with selection: NSAttributedString, types: [NSPasteboard.PasteboardType]
  ) -> NSPasteboard {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    for type in types {
      if let data = encoded(selection, as: type) { pasteboard.setData(data, forType: type) }
    }
    pasteboard.setString(selection.string, forType: .string)
    return pasteboard
  }

  nonisolated private static func encoded(
    _ selection: NSAttributedString, as type: NSPasteboard.PasteboardType
  ) -> Data? {
    let range = NSRange(location: 0, length: selection.length)
    return type == .rtfd
      ? selection.rtfd(from: range, documentAttributes: [:])
      : selection.rtf(from: range, documentAttributes: [:])
  }

  /// "2 + 2 ", an inline PNG attachment, then " now".
  private static func selectionWithAttachment() -> NSAttributedString {
    let image = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    let png = image?.representation(using: .png, properties: [:]) ?? Data()
    let file = FileWrapper(regularFileWithContents: png)
    file.preferredFilename = "dot.png"
    let selection = NSMutableAttributedString(string: "2 + 2 ")
    selection.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: file)))
    selection.append(NSAttributedString(string: " now"))
    return selection
  }
}
