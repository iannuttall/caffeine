# Release Caffeine

Caffeine ships as a notarized Developer ID app inside a DMG. Sparkle reads `appcast.xml` from
the public GitHub repository and verifies every update against the EdDSA public key in
`app.config.json`.

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

Review and commit the generated appcast before publishing the GitHub release. Installed copies
read that file directly from the `main` branch, so the feed URL and public key must not change
after the first release.

## Publish the GitHub release

Tag and upload the same files that were notarized and signed for Sparkle.

```sh
VERSION=0.1.0
git tag "v$VERSION"
git push origin "v$VERSION"

gh release create "v$VERSION" \
  ".build/artifacts/Caffeine-$VERSION.dmg" \
  ".build/artifacts/Caffeine-$VERSION.dmg.sha256" \
  --title "Caffeine $VERSION" \
  --generate-notes
```

Do not rebuild between `make release`, appcast signing, and upload. Sparkle checks the bytes, so
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
