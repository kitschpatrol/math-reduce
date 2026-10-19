<!-- title -->

# MathReduce

<!-- /title -->

<!-- badges -->

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/license/mit)

<!-- /badges -->

<!-- short-description -->

**A system-wide macOS service to turn any text field into a calculator.**

<!-- /short-description -->

## Overview

MathReduce is a system-wide [macOS service](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/introduction.html) that will calculate simple mathematical expressions in a chunk of selected text anywhere in the system.

Just highlight some text and press <kbd>⌘ Command</kbd>-<kbd>⇧ Shift</kbd>-<kbd>M</kbd> to see bits of math replaced with reduced values.

## Getting started

### Dependencies

MathReduce requires macOS 11.5 or later. Building it requires Xcode.

[DDMathParser](https://github.com/davedelong/DDMathParser) is included as a git submodule and compiled into the service. The submodule is pinned to DDMathParser's [`1.1` branch](https://github.com/davedelong/DDMathParser/tree/1.1), the Objective-C version of the library.

MathReduce was written in October 2013 with Xcode 5 for OS X 10.8. It was updated for Xcode 7.2 and DDMathParser 1.1 in December 2015, and its deployment target was raised to macOS 11.5 in February 2026. It still builds with Xcode 26.3.

### Installation

Clone the repository with its submodule, then open the project in Xcode:

```sh
git clone --recurse-submodules https://github.com/kitschpatrol/math-reduce.git
open math-reduce/MathReduce.xcodeproj
```

If you've already cloned the repository without the submodule, run `git submodule update --init` from the repository root.

For now… just build the project in Xcode. This will invoke a script that copies the resulting `MathReduce.service` binary to `~/Library/Services`, and then calls a few additional commands to refresh the system-wide services roster. (However, logging out and logging back in still might be necessary to get MathReduce to show up in the services menu and in order for it to work properly via the shortcut.)

If you don't care for the default keyboard shortcut, it's easy to change to your liking via System Settings --> Keyboard --> Keyboard Shortcuts --> Services.

## Usage

Say you've typed in the following text in TextEdit, a Gmail message, or maybe Xcode:

- I wonder what the value of 2.5 \* (10\*\*5 / sin(1.5) + 2PI) is?

Select the text in question:

- I wonder what the value of <mark>2.5 \* (10\*\*5 / sin(1.5) + 2PI)</mark> is?

Press <kbd>⌘ Command</kbd>-<kbd>⇧ Shift</kbd>-<kbd>M</kbd> and the mystery math is replaced with:

- I wonder what the value of 250643.5340249492 is?

In addition to the system-wide keyboard shortcut, MathReduce is also accessible through any application's services menu (assuming there's text selected).

And that's it. In essence, any editable text field in the system becomes a canvas for extracting values from mathematical expressions.

Note some of the neat things in the example above… constants like PI and e are available, as well as trigonometric functions. See the full list of [operators](https://github.com/davedelong/DDMathParser/wiki/Operators/ca377bc87315404889866212abc44de6d00cfbc3) and [functions](https://github.com/davedelong/DDMathParser/wiki/Built-in-Functions/80080bae6875cbeec8ae4ec3c5cb802277acc3f3) supported by MathReduce's underlying parser.

Use `**` for exponents. DDMathParser 1.1 treats `^` as bitwise XOR, so `2^10` reduces to `8`.

MathReduce evaluates the entire selection as one expression, so select only the math. If the selection isn't a valid expression (for example, because it includes the surrounding words), the service returns an error instead of a result.

## Updating bundled libraries

DDMathParser is a git submodule pinned to the latest commit on its `1.1` branch. The Xcode project compiles the source files in `DDMathParser/DDMathParser` directly into the MathReduce target, so files added or removed upstream also need to be added to or removed from the target. DDMathParser 2.0 and later are written in Swift, so moving past 1.1 would take more than updating the submodule.

## Background

### Implementation notes

MathReduce is packaged as a background-only `.service` bundle. [`main.m`](MathReduce/main.m) registers [`KPMathReduceServiceProvider`](MathReduce/KPMathReduceServiceProvider.m) as the provider for the `MathReduce` port, then runs for at most five seconds before exiting. macOS launches it again the next time the service is invoked.

The service is declared under `NSServices` in [`MathReduce-Info.plist`](MathReduce/MathReduce-Info.plist), with the menu item name "Math Reduce" and an uppercase `M` as its key equivalent. The provider's `reduceMath:userData:error:` method reads the selected text from the pasteboard, parses and evaluates it with DDMathParser's default evaluator, and writes the result back to the pasteboard to replace the selection.

The bundle setup follows Andy Lee's [Writing a .service bundle](https://www.notesfromandy.com/2013/04/05/writing-a-service-bundle/) tutorial and his [CopySelector](https://github.com/aglee/copyselector) template project.

The [`scrapbook`](scrapbook) folder holds an earlier prototype from July 2012: an Automator service ([`Math Reduce.workflow`](<scrapbook/Math Reduce.workflow>)) that ran a Python script to find math in a chunk of text with a regular expression and evaluate each match. The folder also has notes on those regular expressions, an OmniGraffle document, and an [illustration of the process](scrapbook/math-reduce-process.jpg).

### Known issues

- There's no release build with a binary yet.

- There's no animated GIF illustrating the process yet.

- The <kbd>⌘ Command</kbd>-<kbd>⇧ Shift</kbd>-<kbd>M</kbd> shortcut is in conflict with a default key combination in Xcode. By default, Xcode uses this as a shortcut to the Debug Menu > Debug Workflow > View Memory command. This key mapping must be cleared in the Xcode settings in order for MathReduce to work properly inside Xcode:

  1. Open the settings window to the "Key Bindings" tab.
  2. Search for "view memory" in the key binding search bar.
  3. Clear the "key" field for the Debug Workflow > View Memory entry.

- Since MathReduce uses the Mac's native services framework, it's only compatible with text fields implemented with Mac-native toolkits. (Luckily this turns out to be most of your day-to-day text fields.)

## Maintainers

[kitschpatrol](https://github.com/kitschpatrol)

## Acknowledgments

MathReduce is a very thin wrapper around Dave DeLong's superlative [DDMathParser](https://github.com/davedelong/DDMathParser) library.

<!-- contributing -->

## Contributing

[Issues](https://github.com/kitschpatrol/math-reduce/issues) are welcome and appreciated.

Please open an issue to discuss changes before submitting a pull request. Unsolicited PRs (especially AI-generated ones) are unlikely to be merged.

This repository uses [MDAT](https://github.com/kitschpatrol/mdat) for readme placeholder expansion.

<!-- /contributing -->

<!-- license -->

## License

[MIT](license.txt) © [Eric Mika](https://ericmika.com)

<!-- /license -->

DDMathParser, which is included as a submodule and compiled into the service, is copyright Dave DeLong and is also available under the MIT license.
