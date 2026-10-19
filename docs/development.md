# Development

Development requires Xcode 26 or later (Swift 6.2+), [fastlane](https://fastlane.tools) 2.239.0 or later, [just](https://github.com/casey/just), and [MDAT](https://github.com/kitschpatrol/mdat). MDAT is required by `just format` and `just lint` to keep generated README sections current. Install MDAT from the `kitschpatrol/tap` Homebrew tap:

```sh
brew install just fastlane
brew install kitschpatrol/tap/mdat
git clone https://github.com/kitschpatrol/math-reduce.git
cd math-reduce
just test
just build
```

Local builds and tests need no `.env`, 1Password access, or Apple signing credentials. `just init` configures release credentials; see [One-time setup](#one-time-setup) when preparing to publish.

`just build` creates an ad-hoc signed, universal `dist/MathReduce.service`. It does not install it. `just install` builds and copies the service to `~/Library/Services`, then refreshes Services. Run `just uninstall` to remove an existing installation first; the installer refuses to overwrite it, including Homebrew-managed installations.

To remove existing installations from a source checkout:

```sh
just uninstall
```

`just uninstall` removes the Homebrew cask if installed, unregisters existing Math Reduce copies from Launch Services, then removes Math Reduce bundles from `~/Library/Services` and `/Library/Services`, including renamed copies identified by their bundle ID. It updates the Services cache with macOS's `pbs` tool without building or launching the service. Removing a protected installation may prompt for your administrator password through `sudo`; run the recipe as your normal user.

macOS can register bundles outside the Services folders, including `dist/MathReduce.service`, temporary builds, and copies on mounted DMGs. The uninstaller unregisters these copies but preserves their files. This prevents macOS from falling back to a development build after the installed copy is removed. Other users' home folders are not deleted. Launching a preserved build or opening its disk image again can register it again; eject the Math Reduce DMG after installation or uninstallation. Quit and reopen apps if their Services menus still show a cached entry.

You can smoke-test the bundled executable directly:

```sh
dist/MathReduce.service/Contents/MacOS/MathReduce --evaluate '2**10'
dist/MathReduce.service/Contents/MacOS/MathReduce --version
```

`just test` runs Swift Testing suites for expression compatibility and the pasteboard callback, plus offline fastlane release checks in disposable Git repositories. Those checks replace Apple and GitHub calls, so they need no credentials or network. `just format` formats Swift and runs `mdat expand readme.md` to refresh generated sections, including badges. `just lint` checks Swift formatting and runs `mdat check readme.md` to detect stale generated content without changing files. CI runs the tests and universal bundle build on Sequoia.

Most `just` recipes invoke fastlane lanes. You can also use `fastlane mac build`, `fastlane mac test`, or `fastlane lanes` directly. The Homebrew fastlane installation supplies Ruby and the required gems; no separate Bundler setup or fastlane plugins are needed.

## Naming

Use **Math Reduce** when referring to the product in prose and user-visible labels. The other forms identify code, files, or packages:

| Name | Role |
| --- | --- |
| Math Reduce | Product name, Services menu label, bundle display names, DMG volume label, and Homebrew display name |
| `MathReduce` | Swift package, executable target and binary, and Services registration port |
| `MathReduceCore` | Swift library module |
| `MathReduce.service` | Installed bundle filename |
| `MathReduce-X.Y.Z-universal.dmg` | Release asset filename |
| `math-reduce` | Repository, Homebrew cask token, and default notarization profile |
| `com.kitschpatrol.MathReduce` | Stable bundle identifier, also used to identify installed copies during uninstall |

In `Resources/Info.plist`, `CFBundleDisplayName` and `CFBundleName` contain the product name, while `CFBundleExecutable` names the actual binary. `NSServices.NSMenuItem.default` controls the Services menu label. `NSPortName` must match the name passed to `NSRegisterServicesProvider` in Swift; changing the visible label does not require changing this registration name. Keep the existing bundle identifier stable across releases. See Apple's [bundle naming reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html) and [Services properties](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html).

## Layout

- `Sources/MathReduceCore`: evaluation wrapper and the Objective-C-visible Services callback, isolated to the main actor.
- `Sources/MathReduce`: the short-lived background service entry point and diagnostic commands.
- `Resources`: service metadata and DDMathParser's license.
- `Tests`: Swift Testing suites.
- `fastlane/Fastfile`: development and release lanes, including plist updates, Git commits and tags, and GitHub publication.
- `fastlane/lib/project.rb`: service bundle packaging, Apple signing commands, release receipts, and GitHub asset verification.
- `fastlane/tests`: offline checks for versioning, release failures, and recovery.
- `Resources/Info.plist`: the authoritative release version in `CFBundleShortVersionString`, with `CFBundleVersion` bumped to match. The release lane also updates `codemeta.json`.
- `scrapbook`: the original Automator prototype and design notes.

DDMathParser is consumed as the upstream `MathParser` SPM product. `Package.swift` pins revision `2e067fc17c36f4298649b6681d52286fe4ca388e`, which includes fixes after the `3.1.0` tag, notably factorials above 20. `Package.resolved` is committed. To update it, change the revision, run `swift package resolve`, and run the tests.

`EvaluationCompatibility` uses DDMathParser's function override API to guard unsafe bitwise integer conversions, reject oversized factorials, and correct its `max`, `median`, and double-factorial edge cases. Operand expressions are evaluated once; validated values are passed back to the upstream evaluator where possible. These workarounds are covered by regression tests and can be removed when equivalent upstream fixes are available. Inputs are capped at 4 KiB of UTF-8 text before entering the recursive parser, preventing stack overflow and excessive parsing time from large selections.

# Releases

The local fastlane workflow follows the version/commit/tag/publish pattern in `create-project`'s Electron templates. Fastlane manages the release lanes and provides the plist, Git, and GitHub actions. Service packaging uses Xcode's native signing tools. Notarization calls `notarytool` directly because fastlane's `notarize` action does not support Keychain profiles. Homebrew cask updates are managed separately after the GitHub release.

## One-time setup

1. Install fastlane, `just`, the GitHub CLI, and the 1Password CLI (`brew install fastlane just gh 1password-cli`). Enable CLI integration in 1Password and unlock the app. The GitHub token needs write access to this repository.
2. Install your **Developer ID Application** certificate and its private key in Keychain. `security find-identity -v -p codesigning` lists usable identities.
3. In the `Apple` item in your 1Password `Personal` vault, store the App Store Connect team API key's PEM contents in the `APP_STORE_DEV_KEY` password field, with its metadata in `APP_STORE_DEV_KEY_ID`, `APP_STORE_DEV_KEY_NAME`, and `APP_STORE_DEV_KEY_ISSUER_ID`. Check the signing identity and GitHub token references in `.template.env`, then run:

   ```sh
   just init
   ```

   The fastlane `setup` lane regenerates the ignored `.env` with owner-only read/write permissions (`0600`). It retrieves `APP_STORE_DEV_KEY` directly into a temporary `.p8` with the same permissions, restores PEM line breaks if the password field flattened them (or contains literal `\n` escapes), and checks that it is a valid App Store Connect private key. It then calls `notarytool store-credentials` to validate and import it into the `NOTARYTOOL_PROFILE` Keychain profile (default `math-reduce`). The temporary directory is removed on success or failure; the private key contents never enter `.env`. `APP_STORE_DEV_KEY_NAME` is used as a display label.

   Both `just` and fastlane load the root `.env`. Rerun `just init` after changing the template or rotating the key; it replaces `.env` and updates the Keychain profile. The signing identity must still match an installed Developer ID Application certificate and private key. GitHub authentication uses `GH_TOKEN`, then `GITHUB_TOKEN`, then the token from `gh auth token`.

## Publish

Start on a clean default branch that has been pushed to `origin`:

```sh
just release current     # publish the existing plist version without bumping
just release patch       # or minor / major
just release 2.0.0       # alternatively, choose an explicit newer X.Y.Z
# Equivalent: fastlane mac release bump:patch
```

For the initial 1.0 release, use `just release current` with the plist version set to `1.0.0`. This creates tag `v1.0.0` and publishes the signed, notarized release to GitHub. When the plist and `codemeta.json` already agree, it tags the existing commit without rewriting those files or creating a version commit. An existing release tag is never overwritten. Omitting the argument still defaults to `patch`.

The command:

1. Checks the branch, GitHub login, Developer ID identity, and notarization credentials, then runs tests.
2. Selects the current version or bumps both version fields in `Resources/Info.plist`, synchronizes `codemeta.json` if needed, builds both architectures, and copies the plist into `MathReduce.service`. The plist's release version determines the Git tag, release name, and asset filename.
3. Signs the service with the hardened runtime and a secure timestamp. Creates and signs `MathReduce-X.Y.Z-universal.dmg`, submits it for notarization, staples its ticket, and validates it with Gatekeeper.
4. Commits any version-file changes as `Release: vX.Y.Z`, creates the annotated `vX.Y.Z` tag, and pushes the branch and tag atomically.
5. Creates a draft GitHub release, uploads the signed DMG and its SHA-256 file, then publishes the release.
6. Downloads the published asset and verifies its SHA-256 against the signed local artifact before marking the release complete.

Only signed, notarized artifacts enter this publishing path. `just package` rehearses the build/sign/notarize steps at the current version without creating commits, tags, or releases. `just build` remains the local development build.

## Recovery

A build or notarization failure restores the original version files before any commit or push. After packaging, fastlane saves a receipt in ignored `dist/release-state.json` with the artifact checksum, version-file checksums, and source commit:

```sh
just resume                  # finish an interrupted release without bumping again
```

Keep `dist` until the release is complete: resume checks the artifact, version files, and release commit before continuing. `just package` refuses to overwrite an interrupted release's artifact. Resume reuses an existing commit, tag, and GitHub release. Draft assets can be retried; published release assets are never overwritten. If the final download or verification fails, resolve the failure and run `just resume` to verify the existing GitHub asset again. Set `GITHUB_REPOSITORY` to override the repository for a fork.

## Background

The Swift port retains the background-only `.service` bundle, `com.kitschpatrol.MathReduce` identifier, `MathReduce` port, `reduceMath:userData:error:` selector, and five-second process lifetime. macOS launches the provider again as needed.

The original bundle setup followed Andy Lee's [Writing a .service bundle](https://www.notesfromandy.com/2013/04/05/writing-a-service-bundle/) tutorial and [CopySelector](https://github.com/aglee/copyselector).

## Shortcuts

Choose a combination that your target applications don't already use. See [Shortcut customization](../readme.md#shortcut-customization) for the steps in System Settings.

See Apple's [keyboard shortcut guide](https://support.apple.com/guide/mac-help/keyboard-shortcuts-mchlp2262/15.0/mac/15.0) for more details.
