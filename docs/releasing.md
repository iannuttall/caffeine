# Release Caffeine

Caffeine ships as a notarized Developer ID app inside a DMG. Sparkle reads `appcast.xml` from
the public GitHub repository and verifies every update against the EdDSA public key in
`app.config.json`.

## Release workflow

A coding agent on the release Mac handles each release as a single PR:

1. Bump `MARKETING_VERSION` and `BUILD_NUMBER` in `version.env`.
2. Add a dated section to `CHANGELOG.md`.
3. Run `make release` to sign, notarize, and upload the DMG and checksum to a draft GitHub
   release.
4. Run `make appcast` to sign the DMG for Sparkle and update `appcast.xml`.
5. Commit everything and open (or update) the PR.

Merging that PR to `main` triggers the `publish-release` workflow. CI does not build or
notarize a new DMG. The workflow reads the newest appcast item, confirms the draft release
has matching assets, verifies the checksum, and publishes the release.

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

## What the agent does

The release agent bumps the version, then runs:

```sh
make check
make release
make appcast ARTIFACT=.build/artifacts/Caffeine-VERSION.dmg
```

`make release` signs Sparkle from the inside out, signs the CLI and app with hardened runtime,
launches the signed app, and builds a drag-install DMG. It submits that DMG to Apple, staples
the accepted ticket, runs Gatekeeper, and writes a SHA-256 checksum. If `gh` is available and
authenticated, it creates (or updates) a draft GitHub release tagged `vVERSION` with the DMG
and checksum. The draft stays private until the workflow publishes it.

`make appcast` signs the notarized DMG with the Sparkle private key and adds its item to
`appcast.xml`.

The agent commits `version.env`, `CHANGELOG.md`, and `appcast.xml`, then opens (or updates) a
PR. When the PR merges, the workflow publishes the draft release.

## Publish via the workflow

When `appcast.xml` merges to `main`, the `publish-release` workflow runs. It parses the newest
item in `appcast.xml`, validates that the draft release has matching assets with the expected
size and signature, verifies the checksum, and publishes the release at the merged commit.

If the release was already published, the workflow succeeds without changing anything.

Do not rebuild between `make release`, appcast signing, and merge. Sparkle checks the bytes,
so even a harmless rebuild produces a different signature.

## Verify a release

Mount the DMG and drag Caffeine to Applications. Check the installed app and artifact:

```sh
codesign --verify --deep --strict --verbose=2 /Applications/Caffeine.app
spctl --assess --type execute --verbose=4 /Applications/Caffeine.app
xcrun stapler validate .build/artifacts/Caffeine-VERSION.dmg
(cd .build/artifacts && shasum -a 256 -c Caffeine-VERSION.dmg.sha256)
```

Open the installed app and test a manual session, a timer, Agent Watch, and both hook removal
paths. Run `make power-check` while a session is active. A release is blocked if the app exits,
Sparkle rejects the update, or macOS does not accept and release the expected assertions.
