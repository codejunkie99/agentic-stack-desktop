# Releasing Agentic Stack Desktop

The chosen release route is **Sparkle 2.9.6 preview updates authenticated with
EdDSA**. Valid ad-hoc app signatures can be used for this preview update route;
Developer ID signing and notarization are a separate first-install trust and
notarized-distribution path, not prerequisites for these preview updates.
Sparkle authentication does not establish macOS first-install/Gatekeeper
acceptance. Label the preview as unnotarized and explain that macOS may block
its first launch. See [Sparkle's archive authentication procedure](https://sparkle-project.org/documentation/publishing/).

Keep credentials and private keys in Keychain; never export them or put them
in commands, logs or the repository. Replace angle-bracket placeholders locally.

## Chosen route: Sparkle preview updates

1. Use the existing verified preview 7 artifacts. The production ZIP is
   `Agentic Stack-macOS.zip`, 30,095,377 bytes, SHA256
   `93be0acd7a085be391d67fd5e9f76e434d3307b87992beffae1b5e91438aa8b3`.
   Preserve the checked ad-hoc app, ZIP, DMG and server archive bytes. If a new
   build is needed, use the ad-hoc mode below, increment beyond the live feed,
   and repeat package/update verification for its new bytes.
2. Authenticate the exact final enclosure using the existing
   `agentic-stack-desktop` Keychain account. The production preview ZIP already
   has a verified signature; the following is the signing/verification command
   sequence for the chosen archive. Resolve tools into temporary storage because
   the build deletes its Swift scratch directory:

   ```sh
   preview_artifacts='<ABSOLUTE_VERIFIED_PREVIEW_DIRECTORY>'
   preview_tools="$(mktemp -d /private/tmp/agentic-sparkle-tools.XXXXXX)"
   swift package --package-path apps/macos --scratch-path "$preview_tools" resolve
   sparkle_sign="$preview_tools/artifacts/sparkle/Sparkle/bin/sign_update"
   enclosure="$preview_artifacts/Agentic Stack-macOS.zip"
   test -x "$sparkle_sign"
   ed_signature="$("$sparkle_sign" --account agentic-stack-desktop -p "$enclosure")"
   "$sparkle_sign" --account agentic-stack-desktop --verify "$enclosure" "$ed_signature"
   stat -f '%z' "$enclosure"
   printf '%s\n' "$ed_signature"
   shasum -a 256 "$enclosure" "$preview_artifacts/Agentic-Stack-macOS-arm64.dmg"
   ```

3. Prepare the appcast with the exact ZIP signature, byte length and asset URL.
   The local `appcast.xml` now includes build 7 and preserves build 6. Its ZIP
   URL ends in `Agentic.Stack-macOS.zip`; upload the verified ZIP bytes under
   that exact asset name. The installer separately uses preview 7's DMG SHA256
   `4a89b1d68567856f10fc59a9c2eb5259f1906f4bfc020589a8bb6b5db64ebead`.
   A ZIP signature/length cannot be reused for the DMG. Check XML and metadata
   against the receipts before publication.
4. Preserve the actual updater QA scope: real native app copies completed
   Check for Updates → download → Install and Relaunch from build 6 to 7;
   About reported `0.19.1 (7)`. A unique QA bundle ID, a launcher enforcing
   isolated data on every launch, a loopback feed and a separately EdDSA-signed
   QA archive protected production data. This verifies update mechanics, not
   production HTTPS delivery, Developer ID, notarization or first-install trust.
5. Publish only through the explicit release action. At preparation time the
   live feed remains build 6; preview 7 metadata is local and nothing is
   published. Upload the exact verified assets before exposing the new feed
   item, then re-download and compare hashes and verify the live update path.
   A missing Developer ID identity does not block this chosen preview route;
   retain the honest unnotarized/first-install limitation in release copy.

## Optional: Developer ID and notarized distribution

The following procedure is separate from the preview route above. It requires
an existing Developer ID Application identity and an authenticated `notarytool`
Keychain profile, plus hardened runtime, secure timestamps and accepted Apple
notarization. These checks are requirements for this optional route, not claims
that the current preview passed. See Apple's
[notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

### 1. Build outside FileProvider storage

Run from the repository root in Bash. Keep the app and working archives under
`/private/tmp`, outside Documents/iCloud/FileProvider, through signing,
notarization and validation. Finder metadata can invalidate a signed bundle.

```sh
set -euo pipefail
release_root="$(mktemp -d /private/tmp/agentic-stack-release.XXXXXX)"
signing_identity='<DEVELOPER_ID_APPLICATION_NAME_OR_FULL_SHA1>'
notary_profile='<NOTARYTOOL_KEYCHAIN_PROFILE>'

security find-identity -v -p codesigning
curl --proto '=https' --tlsv1.2 --fail --location \
  'https://raw.githubusercontent.com/codejunkie99/agentic-stack-desktop/main/appcast.xml' \
  --output "$release_root/live-appcast.xml"
xmllint --xpath '//*[local-name()="version"]/text()' "$release_root/live-appcast.xml"
```

Choose an integer build number greater than **every build in the live feed**;
the local `appcast.xml` and Git commit count can be stale. Update release notes
and the intended release tag separately. For a self-contained desktop bundle,
provide a relocatable arm64 Python root containing executable `bin/python3`:

```sh
next_build='<NEXT_BUILD_GREATER_THAN_LIVE_FEED>'
python_root='<ABSOLUTE_RELOCATABLE_ARM64_PYTHON_ROOT>'
AGENTIC_BUILD_VERSION="$next_build" \
AGENTIC_SIGNING_IDENTITY="$signing_identity" \
  bash scripts/build-macos-app.sh --output "$release_root" \
  --python-root "$python_root"
app="$release_root/Agentic Stack.app"
```

`--python-root` is optional. Omitting it produces a bundle that needs a suitable
external Python; record and test that dependency rather than describing it as
self-contained. The standalone server archive also requires Python 3.10+.

The build invokes `scripts/sign-macos-app.py`. For Developer ID signing it signs
nested Mach-O files and containers from the inside out, including Python's
interpreter, extension modules and dylibs, Sparkle helpers/XPC services,
frameworks and the outer app. It adds hardened runtime and secure timestamps,
preserves the Downloader service's required entitlements and verifies the
result. `--deep` is used for verification, not recursive signing. See
[Sparkle's manual code-signing guidance](https://sparkle-project.org/documentation/sandboxing/#code-signing).

For an already staged, complete app, the equivalent signing entry point is:

```sh
python3 scripts/sign-macos-app.py "$app" --identity "$signing_identity"
```

Do all payload changes before signing. Do not sign again after notarization or
stapling; changing code requires a new signing/notarization cycle. The build's
initial ZIP and DMG are intermediate artifacts, not the final public assets.

### 2. Inspect the signed app

```sh
codesign --verify --deep --strict --verbose=2 "$app"
codesign --display --verbose=4 "$app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist"
```

Require the intended Developer ID authority/team, `runtime` flag and secure
`Timestamp`, plus the intended build, feed and existing Sparkle public key.
Inspect nested executable signatures too, especially bundled Python and
Sparkle services; an outer strict signature alone is insufficient. Reject
shipping `get-task-allow` entitlements. Apple's
[notarization troubleshooting guide](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)
explains these checks.

When Python is bundled, check its signature and actual imports:

```sh
codesign --display --verbose=4 "$app/Contents/Resources/python/bin/python3"
"$app/Contents/Resources/python/bin/python3" \
  -c 'import ssl, sqlite3; print(ssl.OPENSSL_VERSION, sqlite3.sqlite_version)'
```

Run the applicable Python/native tests and inspect the staged payload for
private runtime data, credential files, unsafe paths and escaping symlinks.
Verify bundled service launch and native behavior on isolated QA data. Record
actual results, source commit and bundle identity; a successful build alone is
not a release receipt.

### 3. Notarize the app, then staple it

Create a separate submission ZIP. Use the existing Keychain profile without
passing account passwords or API keys. Require `Accepted` before continuing:

```sh
ditto -c -k --sequesterRsrc --keepParent "$app" "$release_root/notary-app.zip"
xcrun notarytool submit "$release_root/notary-app.zip" \
  --keychain-profile "$notary_profile" --wait --output-format json \
  > "$release_root/notary-app-result.json"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["id"],r["status"]); sys.exit(r["status"] != "Accepted")' \
  "$release_root/notary-app-result.json"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
```

If submission fails, remains in progress, or reports any status other than
`Accepted`, stop. Preserve its submission ID and fetch the log before fixing
and resubmitting:

```sh
xcrun notarytool info '<SUBMISSION_ID>' --keychain-profile "$notary_profile"
xcrun notarytool log '<SUBMISSION_ID>' --keychain-profile "$notary_profile" \
  "$release_root/notary-failure.json"
```

ZIP files cannot be stapled directly. Staple the app, then recreate its
archives. Apple's [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
covers submission, status/log retrieval and stapling.

### 4. Rebuild final archives and notarize the DMG

Create a new final ZIP and rebuild the DMG **from the stapled app**. Do not reuse
the build's earlier archives. Preserve framework symlinks and the ticket:

```sh
zip="$release_root/Agentic Stack-macOS.zip"
dmg="$release_root/Agentic-Stack-macOS-arm64.dmg"
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
python3 scripts/build-macos-dmg.py "$app" "$dmg"
codesign --force --sign "$signing_identity" --timestamp "$dmg"
codesign --verify --strict --verbose=2 "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" \
  --wait --output-format json > "$release_root/notary-dmg-result.json"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["id"],r["status"]); sys.exit(r["status"] != "Accepted")' \
  "$release_root/notary-dmg-result.json"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
hdiutil verify "$dmg"
codesign --verify --strict "$dmg"
```

If distributing a DMG, require its own Developer ID Application signature and
accepted/stapled notarization, even when Sparkle uses the ZIP. For a failed DMG
submission, use the same `info`/`log` commands with its submission ID. Do not
rebuild or modify the final DMG after stapling. Signatures and hashes below
must cover these final bytes.

### 5. Test the local distribution

Extract the final ZIP and mount the final DMG read-only. Validate both copies;
install the local artifact into a disposable directory, not over a user's app:

```sh
qa_root="$(mktemp -d /private/tmp/agentic-stack-release-qa.XXXXXX)"
ditto -x -k "$zip" "$qa_root/zip"
mkdir "$qa_root/mount" "$qa_root/Applications"
hdiutil attach "$dmg" -mountpoint "$qa_root/mount" -nobrowse -readonly
codesign --verify --deep --strict "$qa_root/zip/Agentic Stack.app"
xcrun stapler validate "$qa_root/zip/Agentic Stack.app"
codesign --verify --deep --strict "$qa_root/mount/Agentic Stack.app"
xcrun stapler validate "$qa_root/mount/Agentic Stack.app"
ditto "$qa_root/mount/Agentic Stack.app" "$qa_root/Applications/Agentic Stack.app"
hdiutil detach "$qa_root/mount"
spctl --assess --type execute --verbose=4 "$qa_root/Applications/Agentic Stack.app"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"
```

Compare ZIP/DMG app contents, symlinks and build identity. Launch the copied app
in an isolated QA user/data environment; inspect the actual native UI and
bundled service process. Check first launch through Finder with normal download
quarantine, including an offline launch where practical. Do not remove
quarantine or bypass Gatekeeper to turn a failed release check into a pass.
Apple describes final policy assessment in its
[notarization troubleshooting guide](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).

`scripts/install-macos.sh` downloads its hardcoded published release. Running
it unchanged tests that old remote asset, not this candidate. Its candidate
install test must use this exact local DMG, preserving checksum verification,
copy and backup behavior in a disposable harness. Do not treat the installer's
quarantine removal as Gatekeeper evidence. Quit only the QA app and detach only
the QA mount before removing your temporary QA directory.

### 6. Authenticate the final Sparkle enclosure

Choose exactly which archive the appcast enclosure will download. This example
uses the ZIP; set `enclosure="$dmg"` if the feed will use the final DMG instead.
The build deletes its disposable Swift scratch directory, so resolve the pinned
package dependencies into separate temporary storage to obtain `sign_update`.
This needs network access when the binary artifact is not cached; no build is
required.

```sh
enclosure="$zip"
swift package --package-path apps/macos \
  --scratch-path "$release_root/sparkle-tools" resolve
sparkle_sign="$release_root/sparkle-tools/artifacts/sparkle/Sparkle/bin/sign_update"
test -x "$sparkle_sign"
ed_signature="$("$sparkle_sign" --account agentic-stack-desktop -p "$enclosure")"
"$sparkle_sign" --account agentic-stack-desktop --verify "$enclosure" "$ed_signature"
stat -f '%z' "$enclosure"
printf '%s\n' "$ed_signature"
shasum -a 256 "$zip" "$dmg" "$release_root/Agentic Stack-server.zip" \
  > "$release_root/SHA256SUMS"
```

Use the verified public signature and byte length for that exact enclosure in
`appcast.xml`; its URL must name that same release asset. Set `sparkle:version`
to the new `CFBundleVersion`, and update the release notes URL. A ZIP signature
or length cannot authenticate the DMG, or vice versa. See
[Sparkle's update publishing procedure](https://sparkle-project.org/documentation/publishing/).

Update `RELEASE_TAG` and `EXPECTED_SHA256` in `scripts/install-macos.sh` using
the **final DMG's independent SHA256**, even when the appcast uses ZIP. Check XML
with `xmllint --noout appcast.xml`, compare every enclosure/installer value to
the final receipts, and test Sparkle's update path with a private test feed.
Any archive mutation requires fresh hashes and a fresh Sparkle signature.

### 7. Publish only after explicit release authorization

Keep preparation and publication separate. After artifact, installation,
Gatekeeper and updater checks pass, obtain the explicit release action before
pushing the public appcast/tag or publishing GitHub Release assets. Upload the
verified bytes and ensure the enclosure asset is available before exposing the
new feed item. Re-download published assets, compare hashes and check the live
feed and update path. Preserve source/build, notarization IDs, validations,
archive hashes and the public Sparkle signature as release evidence.

## Ad-hoc preview build mode

For a preview build, omit `AGENTIC_SIGNING_IDENTITY` or set it to `-`.
The helper retains ad-hoc signing and strict integrity verification. These
checks do not establish Developer ID signing, notarization or Gatekeeper
acceptance. EdDSA-authenticated preview updates can use this mode; first-install
trust remains separate. Label the artifact accordingly; Sparkle does not make
it a notarized release.
