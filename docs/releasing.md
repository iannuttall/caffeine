# Release Caffeine

Caffeine ships as a notarized Developer ID app inside a DMG. Sparkle reads `appcast.xml` from
the public GitHub repository and verifies every update against the EdDSA public key in
`app.config.json`.

## Release workflow

1. Update `MARKETING_VERSION` and `BUILD_NUMBER` in `version.env`.
2. Add a dated section with the same version to `CHANGELOG.md`.
3. Run `make release` on the release Mac. This signs, notarizes, and creates a draft GitHub
   release with the DMG and checksum.
4. Run `make appcast ARTIFACT=.build/artifacts/Caffeine-VERSION.dmg` to sign the DMG for
   Sparkle and update `appcast.xml`.
5. Commit the `appcast.xml` change and merge it to `main`.
6. The `publish-release` workflow validates the draft and publishes it.

CI does not build or notarize a new DMG when `appcast.xml` changes. The workflow reads the
newest appcast item, confirms that the matching draft release already has the DMG and
checksum with the expected size and signature, verifies the checksum, and then publishes the
release.

## Set up the release Mac once

The Mac needs a `Developer ID Application` certificate and its private key in Keychain. Apple
notarization uses an App Store Connect API key stored outside this repository.

Set these environment variables through the private macOS signing config.

```sh
export APP_IDENTITY="Developer ID Application: Name (TEAMID)"
export ASC_KEY_ID="KEYID"
export ASC_ISSUER_ID="ISSUERID"
export ASC_KEY_PATH="$HOME/.config/macos/AuthKey_KEYID.p8"
export SPARKLE_PRIVATE_KEY_PATH="$HOME/.config/macos/sparkle-private-key"
```

The Sparkle private key must match the public key pinned in `app.config.json`. Never add the
private key, notarization key, or certificate export to the repository.

## Prepare the version

Start from a clean commit. Update `MARKETING_VERSION` and `BUILD_NUMBER` in `version.env`, then
add a dated section with the same version to `CHANGELOG.md`.

Run the checks and build the unsigned universal bundle.

```sh
make check
make package
```

`make package` builds the app, bundled CLI, and every Sparkle executable for both `arm64` and
`x86_64`. It does not use release credentials.

## Sign and notarize the DMG

Quit every running copy of Caffeine before starting the release.

```sh
make release
```

The release script signs Sparkle from the inside out, signs the CLI and app with hardened
runtime, launches the signed app, and builds a drag-install DMG. It submits that DMG to Apple,
staples the accepted ticket, runs Gatekeeper, and writes a SHA-256 checksum.

If `gh` is available and authenticated, the script creates (or updates) a draft GitHub release
tagged `vVERSION` with the DMG and checksum. The script does not overwrite a published release.

The script writes two final files.

```text
.build/artifacts/Caffeine-VERSION.dmg
.build/artifacts/Caffeine-VERSION.dmg.sha256
```

## Update the Sparkle feed

Sign the exact notarized DMG and add its entry to `appcast.xml`.

```sh
make appcast ARTIFACT=.build/artifacts/Caffeine-VERSION.dmg
```

Review and commit the generated appcast before merging to `main`. Installed copies read that
file directly from the `main` branch, so the feed URL and public key must not change after the
first release.

## Publish via the workflow

When the appcast commit merges to `main`, the `publish-release` workflow runs. It parses the
newest item in `appcast.xml`, validates that the draft release has matching assets, verifies
the checksum, and publishes the release at the merged commit.

If the release was already published, the workflow succeeds without changing anything.

Do not rebuild between `make release`, appcast signing, and merge. Sparkle checks the bytes, so
even a harmless rebuild produces a different signature.

## Check the exact artifact

Mount the DMG and drag Caffeine to Applications. Check the installed app and artifact with these
commands.

```sh
codesign --verify --deep --strict --verbose=2 /Applications/Caffeine.app
spctl --assess --type execute --verbose=4 /Applications/Caffeine.app
xcrun stapler validate .build/artifacts/Caffeine-VERSION.dmg
(cd .build/artifacts && shasum -a 256 -c Caffeine-VERSION.dmg.sha256)
```

Open the installed app and test a manual session, a timer, Agent Watch, and both hook removal
paths. Run `make power-check` while a session is active. A release is blocked if the app exits,
Sparkle rejects the update, or macOS does not accept and release the expected assertions.
