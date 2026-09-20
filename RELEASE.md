# Releasing Peek

Peek auto-updates via [Sparkle](https://sparkle-project.org). Updates are served
from an `appcast.xml` published to this repo's **GitHub Releases**, and each build
is signed with an EdDSA key whose private half lives in your login keychain
(created once with Sparkle's `generate_keys`; the public half is in `Info.plist`).

## One-time setup
- **Developer ID Application** cert installed (Xcode ▸ Settings ▸ Accounts ▸
  Manage Certificates ▸ ➕ *Developer ID Application*).
- Notary credentials stored:
  ```
  xcrun notarytool store-credentials peek-notary \
    --apple-id <you@example.com> --team-id <TEAMID> --password <app-specific-pw>
  ```
- The Sparkle EdDSA private key is already in your keychain. To build releases on
  another machine/CI, export it: `.../bin/generate_keys -x private-key.pem` and
  keep it secret.

## Cut a release
1. Bump `CFBundleShortVersionString` (marketing) and `CFBundleVersion` (build) in
   `make-app.sh`.
2. Build + notarize + staple, producing `dist/Peek.zip`:
   ```
   NOTARIZE=1 NOTARY_PROFILE=peek-notary ./make-app.sh
   ```
3. Generate/refresh the appcast (signs the zip with the EdDSA key automatically):
   ```
   .build/artifacts/sparkle/Sparkle/bin/generate_appcast dist/
   ```
   This writes `dist/appcast.xml`. Add release notes as `dist/Peek.html` if wanted.
4. Create a GitHub Release for the new tag and upload **both** `dist/Peek.zip` and
   `dist/appcast.xml` as assets. The `SUFeedURL`
   (`releases/latest/download/appcast.xml`) always points at the newest release.

Existing installs check the feed on schedule and via **Check for Updates…** in the
menu, then download + verify the EdDSA signature before installing.
