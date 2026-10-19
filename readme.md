<!-- title -->

# Math Reduce

<!-- /title -->

<!-- badges({ githubRelease: true, custom: { Homebrew: { image: "https://img.shields.io/badge/Homebrew-kitschpatrol%2Ftap%2Fmath--reduce-FBB040?logo=homebrew&logoColor=white", link: "https://github.com/kitschpatrol/homebrew-tap/blob/main/Casks/math-reduce.rb" } } }) -->

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/license/mit)
[![CI](https://github.com/kitschpatrol/math-reduce/actions/workflows/ci.yml/badge.svg)](https://github.com/kitschpatrol/math-reduce/actions/workflows/ci.yml)
[![GitHub Release](https://img.shields.io/github/v/release/kitschpatrol/math-reduce?label=Release)](https://github.com/kitschpatrol/math-reduce/releases/latest)
[![Homebrew](https://img.shields.io/badge/Homebrew-kitschpatrol%2Ftap%2Fmath--reduce-FBB040?logo=homebrew\&logoColor=white)](https://github.com/kitschpatrol/homebrew-tap/blob/main/Casks/math-reduce.rb)

<!-- /badges -->

<!-- short-description -->

**A system-wide macOS service to turn any text field into a calculator.**

<!-- /short-description -->

## Overview

Select a mathematical expression in an editable text field, then press <kbd>⌘ Command</kbd>-<kbd>⇧ Shift</kbd>-<kbd>M</kbd>. Math Reduce evaluates the expression and replaces the selection with its result.

It also appears as **Math Reduce** in the application's Services menu.

Requires **macOS 15 Sequoia or later**. Release builds support both Apple Silicon and Intel Macs.

## Installation

### Homebrew

[Homebrew](https://brew.sh/) is the easiest way to install Math Reduce:

```sh
brew install --cask kitschpatrol/tap/math-reduce
```

### Manual

Alternatively, download the DMG from [GitHub Releases](https://github.com/kitschpatrol/math-reduce/releases), open it, and copy `MathReduce.service` to `~/Library/Services` (create that folder if needed).

Releases are Developer ID signed and notarized, and the notarization ticket is stapled to the DMG.

After installing manually, refresh the Services roster:

```sh
~/Library/Services/MathReduce.service/Contents/MacOS/MathReduce --refresh-services
```

If the service doesn't appear, enable it in **System Settings → Keyboard → Keyboard Shortcuts → Services**. You can change its shortcut there. Restart the host application or log out and back in if its Services menu has not refreshed.

### Uninstall

For a Homebrew installation:

```sh
brew uninstall --cask kitschpatrol/tap/math-reduce
```

For a manual installation:

```sh
rm -rf ~/Library/Services/MathReduce.service
```

Eject any mounted Math Reduce disk image, then quit and reopen applications to refresh their Services menus. Development builds can also supply the service; see the [development guide](docs/development.md) for removing their registrations.

## Usage

### Basics

1. Select an expression:

   <span style="background-color: Highlight; color: HighlightText;">2.5 \* (10\*\*5 / sin(1.5) + 2PI)</span>

2. Press <kbd>⌘ Command</kbd>-<kbd>⇧ Shift</kbd>-<kbd>M</kbd>

3. Math Reduce replaces it with its result:

   <span style="background-color: Highlight; color: HighlightText;">250643.5340249492</span>

### Available operators

Parsing and evaluation use Dave DeLong's [DDMathParser](https://github.com/davedelong/DDMathParser), including constants, trigonometry in radians, and implicit multiplication. See the upstream [operators](https://github.com/davedelong/DDMathParser/wiki/Operators) and [functions](https://github.com/davedelong/DDMathParser/wiki/Built-in-Functions).

A few highlights:

- Use `**` for exponentiation: `2**10` → `1024`.
- `^` is bitwise XOR: `2^10` → `8`.
- `%` is modulo: `17 % 5` → `2`.

The entire selection must be an expression. Invalid expressions, division by zero, and nonfinite results leave the existing selection as-is.

Calculations use double-precision floating point. Bitwise operations require values within the signed 64-bit integer range. Expressions are limited to 4 KB of text to keep the service responsive.

### Xcode shortcut conflict

The shortcut conflicts with Xcode's **Debug → Debug Workflow → View Memory** binding. Change one of the shortcuts to use Math Reduce in Xcode.

Applications must support macOS Services and text replacement. Not every web or custom text field does.

### Shortcut customization

To change the default <kbd>⌘ Command</kbd>-<kbd>⇧ Shift</kbd>-<kbd>M</kbd> shortcut:

1. Open **System Settings → Keyboard → Keyboard Shortcuts → Services**.
2. Expand **Text** and make sure **Math Reduce** is enabled.
3. Double-click the shortcut to the right of **Math Reduce**, then press your preferred key combination.
4. Click **Done**, then quit and reopen the apps where you want to use the new shortcut.

## Background

Originally written in Objective-C in October 2013, Math Reduce was rewritten in Swift 6 in the Fall of 2026.

The `scrapbook` directory preserves the July 2012 prototype.

## Maintainers

[kitschpatrol](https://github.com/kitschpatrol)

## Acknowledgments

Math Reduce is a thin wrapper around Dave DeLong's [DDMathParser](https://github.com/davedelong/DDMathParser).

<!-- contributing -->

## Contributing

[Issues](https://github.com/kitschpatrol/math-reduce/issues) are welcome and appreciated.

Please open an issue to discuss changes before submitting a pull request. Unsolicited PRs (especially AI-generated ones) are unlikely to be merged.

This repository uses [MDAT](https://github.com/kitschpatrol/mdat) for readme placeholder expansion.

<!-- /contributing -->

See the [development guide](docs/development.md) for building, releases, and naming conventions.

<!-- license -->

## License

[MIT](license.txt) © [Eric Mika](https://ericmika.com)

<!-- /license -->

DDMathParser is copyright Dave DeLong and also available under the MIT license. Both licenses are included in the built service.
