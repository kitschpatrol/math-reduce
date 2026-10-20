<!-- title -->

# Math Reduce

<!-- /title -->

<!-- badges({ githubRelease: true, custom: { Homebrew: { image: "https://img.shields.io/badge/Homebrew-kitschpatrol%2Ftap%2Fmath--reduce-FBB040?logo=homebrew&logoColor=white", link: "https://github.com/kitschpatrol/homebrew-tap/blob/main/Casks/math-reduce.rb" } } }) -->

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/license/mit)
[![CI](https://github.com/kitschpatrol/math-reduce/actions/workflows/ci.yml/badge.svg)](https://github.com/kitschpatrol/math-reduce/actions/workflows/ci.yml)
[![GitHub Release](https://img.shields.io/github/v/release/kitschpatrol/math-reduce?label=Release)](https://github.com/kitschpatrol/math-reduce/releases/latest)
[![Homebrew](https://img.shields.io/badge/Homebrew-kitschpatrol%2Ftap%2Fmath--reduce-FBB040?logo=homebrew&logoColor=white)](https://github.com/kitschpatrol/homebrew-tap/blob/main/Casks/math-reduce.rb)

<!-- /badges -->

<!-- short-description -->

**A system-wide macOS service that turns any text field into a calculator.**

<!-- /short-description -->

## Overview

Select a mathematical expression in an editable text field, then press <kbd>⌘ Command</kbd>-<kbd>⇧ Shift</kbd>-<kbd>M</kbd>. Math Reduce evaluates the expression and replaces the selection with its result.

It also appears as **Math Reduce** in the application's Services menu.

Requires macOS 15 Sequoia or later. Release builds support both Apple Silicon and Intel Macs.

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

   `2.5 * (10**5 / sin(1.5) + 2PI)`

2. Press <kbd>⌘ Command</kbd>-<kbd>⇧ Shift</kbd>-<kbd>M</kbd>

3. Math Reduce replaces it with its result:

   `250643.5340249492`

### Expressions in text

The selection can include surrounding text. Math Reduce replaces each expression it finds, line by line, and leaves the rest as written:

`There's a 50/50 chance it's easy as PI.` → `There's a 1 chance it's easy as 3.141592653589793.`

Ambiguous text such as dates, phone numbers, and percentages is left alone. To evaluate an expression exactly as written, select it by itself.

Replacement works in rich text documents as well, preserving formatting and images around each reduced expression.

Applications must support macOS Services and text replacement. This is the case in almost all native macOS apps — and even some well-written Electron apps like Obsidian — but not every web-based app or custom text field will necessarily work with Math Reduce.

### Available operators

Parsing and evaluation use Dave DeLong's [DDMathParser](https://github.com/davedelong/DDMathParser), including constants, trigonometry in radians, and implicit multiplication. See DDMathParser's wiki pages on [operators](https://github.com/davedelong/DDMathParser/wiki/Operators) and [functions](https://github.com/davedelong/DDMathParser/wiki/Functions), portions of which are duplicated below:

<!-- operators -->

| Operator                   | Function                | Description                        |
| -------------------------- | ----------------------- | ---------------------------------- |
| `+`                        | `add`                   | addition and unary positive        |
| `-` or `−`                 | `subtract` and `negate` | subtraction and negation           |
| `*` or `×`                 | `multiply`              | multiplication                     |
| `/` or `÷`                 | `divide`                | division                           |
| `%`                        | `mod` or `percent`      | modulus or a percentage of a value |
| `!`                        | `factorial`             | factorial                          |
| `!!`                       | `factorial2`            | double factorial                   |
| `**`                       | `pow`                   | exponentiation                     |
| `º` or `°` or `∘`          | `dtor`                  | converts the value to radians      |
| `√`                        | `sqrt`                  | square root                        |
| `∛`                        | `cuberoot`              | cubic root                         |
| `&`                        | `and`                   | bitwise and                        |
| `\|`                       | `or`                    | bitwise or                         |
| `^`                        | `xor`                   | bitwise xor                        |
| `~`                        | `not`                   | bitwise not                        |
| `<<`                       | `lshift`                | bitwise left shift                 |
| `>>`                       | `rshift`                | bitwise right shift                |
| `==` or `=`                | `l_eq`                  | equal                              |
| `!=` or `≠`                | `l_neq`                 | not equal                          |
| `<`                        | `l_lt`                  | less than                          |
| `>`                        | `l_gt`                  | greater than                       |
| `<=` or `=<` or `≤` or `≯` | `l_ltoe`                | less than or equal                 |
| `>=` or `=>` or `≥` or `≮` | `l_gtoe`                | greater than or equal              |
| `&&` or `∧`                | `l_and`                 | logical and                        |
| `\|\|` or `∨`              | `l_or`                  | logical or                         |
| `!` or `¬`                 | `l_not`                 | logical not                        |

<!-- /operators -->

Many function keywords are also supported:

<!-- functions -->

`phi`, `ϕ`, `pi`, `π`, `pi_2`, `pi_4`, `tau`, `τ`, `sqrt2`, `e`, `log2e`, `log10e`, `ln2`, `ln10`, `sqrt`, `log`, `ln`, `log2`, `exp`, `ceil`, `floor`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `csc`, `sec`, `cotan`, `acsc`, `asec`, `acotan`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`, `csch`, `sech`, `cotanh`, `acsch`, `asech`, `acotanh`, `versin`, `vercosin`, `coversin`, `covercosin`, `haversin`, `havercosin`, `hacoversin`, `hacovercosin`, `exsec`, `excsc`, `crd`, `dtor`, `rtod`, `sum`, `∑`, `product`, `∏`, `count`, `min`, `max`, `median`, `stddev`, `average`, `random`, `nthroot`, `l_if`

<!-- /functions -->

A selection without an expression that can be evaluated is left as-is, including division by zero and nonfinite results.

Calculations use double-precision floating point. Bitwise operations require values within the signed 64-bit integer range. Selections are limited to 4 KB of text to keep the service responsive.

### Xcode shortcut conflict

The shortcut conflicts with Xcode's **Debug → Debug Workflow → View Memory** binding. Change one of the shortcuts to use Math Reduce in Xcode.

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

See the [development guide](docs/development.md) for building, releases, naming conventions, and implementation details.

<!-- license -->

## License

[MIT](license.txt) © [Eric Mika](https://ericmika.com)

<!-- /license -->
