# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Maintenance

- Move CI to macOS 26 runners and update the repository metadata synchronization action.

## [1.1.0] - 2026-10-19

### Added

- Reduce multiple expressions within surrounding text while preserving prose, punctuation, and list markers and leaving ambiguous dates, phone numbers, and percentages unchanged.
- Add `MathReducer.reduce(_:)` for `NSAttributedString` and RTF/RTFD Services support, preserving formatting and attachments and giving each result its expression’s initial formatting.

### Changed

- **Breaking:** Evaluate multiline selections one line at a time and preserve surrounding whitespace and line breaks; expressions split across lines are no longer combined.

### Fixed

- Avoid parser crashes when postfix operators precede commas outside function calls.
- Unregister development builds and mounted DMG copies during `just uninstall` and refresh the Services cache to prevent macOS from falling back to leftover providers.

### Documentation

- Document embedded-expression rules and rich-text behavior, add examples, and include operator and function references in the README.
- Clarify uninstall cleanup, disk-image ejection, and refreshing stale Services menu entries.

### Maintenance

- Expand regression tests with seeded fuzzing, Unicode and prose boundaries, rich-text and attachment round trips, and uninstall registration cleanup.
- Add MDAT rules to generate README operator and function references from DDMathParser’s wiki.

## [1.0.0] - 2026-10-19

### Added

- Replace selected mathematical expressions with their results through the macOS Services menu or the default ⌘⇧M shortcut.
- Provide `MathReduceCore.MathReducer.reduce(_:)` for double-precision arithmetic, constants, trigonometry, implicit multiplication, factorials, and bitwise operations.
- Report localized `ReductionError` diagnostics without replacing invalid selections, with a 4 KB input limit and guards against nonfinite results, oversized factorials, and overflowing bitwise operands.
- Provide `--evaluate`, `--version`, and `--refresh-services` commands for direct evaluation, version reporting, and Services registration refresh.
- Provide universal Apple Silicon and Intel service bundles for macOS 15 or later, packaged as signed and notarized DMGs with SHA-256 checksums.

### Documentation

- Document Homebrew and manual installation, removal, calculation examples, supported operators, shortcut customization, and application compatibility.
- Add a development guide covering local builds, testing, signing credentials, notarization, publishing, and interrupted-release recovery.
- Archive the original Automator prototype, regular-expression notes, and process illustrations in `scrapbook`.

### Maintenance

- Set up Swift 6.2 and SwiftPM with pinned DDMathParser, regression tests, formatting and CI checks, and fastlane/just tooling for builds, installation, and resumable releases.

[Unreleased]: https://github.com/kitschpatrol/math-reduce/compare/v1.1.0...HEAD
[1.0.0]: https://github.com/kitschpatrol/math-reduce/releases/tag/v1.0.0
[1.1.0]: https://github.com/kitschpatrol/math-reduce/compare/v1.0.0...v1.1.0
