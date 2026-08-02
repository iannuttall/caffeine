# How to release Caffeine

Release builds use the same Developer ID and App Store Connect key flow as Scheduler.

1. Update `version.env` and add a dated matching section to `CHANGELOG.md`.
2. Add the public Sparkle EdDSA key to `app.config.json` before the first release.
3. Export `APP_IDENTITY`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH` from the private macOS signing config.
4. Run `make release`. The notarized universal zip lands in `.build/artifacts`.
5. Set `SPARKLE_PRIVATE_KEY_PATH` and run `make appcast ZIP=.build/artifacts/Caffeine-<version>-universal.zip`.
6. Commit `appcast.xml`, tag the version, and upload the exact signed zip to the GitHub release.

The app and bundled CLI are built for arm64 and x86_64. Sparkle's nested services are signed inside-out before the app. The release script then verifies the signature, submits a temporary zip to Apple, staples the accepted ticket to the app, runs Gatekeeper assessment, and creates the download zip.

Signing and notarization cannot be fully tested without the private credentials. `make package` still verifies that every shipped executable and Sparkle component has both architectures.
