set dotenv-load
export FASTLANE_SKIP_UPDATE_CHECK := "1"
export FASTLANE_HIDE_CHANGELOG := "1"
export FASTLANE_OPT_OUT_USAGE := "1"

default:
    @just --list

# Populate .env from 1Password and configure notarization credentials in Keychain.
init:
    fastlane mac setup

# Compile and run Swift and release-workflow regression tests.
test:
    fastlane mac test

# Build a universal, ad-hoc signed service for local development.
build:
    fastlane mac build

# Install a development build in ~/Library/Services and refresh Services.
install:
    fastlane mac install

# Uninstall Homebrew and manual copies from user and system Services folders.
uninstall:
    fastlane mac uninstall

# Build, Developer ID sign, notarize, and staple a release DMG without publishing.
package:
    fastlane mac package

# Publish current, patch/minor/major, or an explicit newer X.Y.Z to GitHub.
release bump="patch":
    fastlane mac release {{quote("bump:" + bump)}}

# Finish an interrupted release from its recorded local state.
resume:
    fastlane mac resume

# Check Swift formatting and generated README sections.
lint:
    swift format lint --strict --recursive Package.swift Sources Tests
    mdat check readme.md

# Format Swift and refresh generated README sections.
format:
    swift format format --in-place --recursive Package.swift Sources Tests
    mdat expand readme.md
