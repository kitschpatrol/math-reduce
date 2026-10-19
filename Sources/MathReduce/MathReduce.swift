import AppKit
import MathReduceCore

@main
@MainActor
enum MathReduce {
  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--refresh-services"] {
      NSUpdateDynamicServices()
      return
    }
    if arguments == ["--version"] {
      print(
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
          ?? "development")
      return
    }
    if arguments.first == "--evaluate", arguments.count == 2 {
      do {
        print(try MathReducer().reduce(arguments[1]))
      } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
      }
      return
    }

    autoreleasepool {
      let provider = ServiceProvider()
      // This registration name must match NSPortName in Info.plist.
      // The visible "Math Reduce" menu label is configured separately by NSMenuItem.
      NSRegisterServicesProvider(provider, NSServiceProviderName("MathReduce"))
      // Retain the short-lived service lifecycle: macOS launches us again on demand.
      withExtendedLifetime(provider) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 5))
      }
    }
  }
}
