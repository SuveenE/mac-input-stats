# Release Guide

## Overview

Releasing a new version requires two types of signing:

- **Apple codesign + notarization** — lets users install the app without Gatekeeper warnings. This is between you and Apple.
- **Sparkle EdDSA signing** — lets the running app verify that an update is legitimate. Prevents someone from hijacking the update feed to push malicious updates. This is between your app and your future releases.

Both are required. Without Apple signing, users can't install. Without Sparkle signing, the app refuses to apply updates.

## Prerequisites

- Developer ID Application certificate installed in Keychain
- Apple ID with app-specific password for notarization
- Sparkle EdDSA private key in your macOS Keychain (generated via `generate_keys`)
- Sparkle CLI tools (download from [Sparkle releases](https://github.com/sparkle-project/Sparkle/releases))
- [`create-dmg`](https://github.com/create-dmg/create-dmg) installed

## Steps

### 0. Bump version numbers

Update both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.pbxproj` (both Debug and Release configs):

- `MARKETING_VERSION` → the new version string (e.g., `1.0.1`)
- `CURRENT_PROJECT_VERSION` → increment the build number (e.g., `2`)

Sparkle compares `shortVersionString` from the appcast against `CFBundleShortVersionString` (derived from `MARKETING_VERSION`). If you forget this, users who already have the new version will still see an update prompt.

### 1. Archive

```bash
BUILDDIR="$(mktemp -d)"

xcodebuild archive \
  -project MacInputStats.xcodeproj \
  -scheme MacInputStats \
  -configuration Release \
  -archivePath "$BUILDDIR/MacInputStats.xcarchive" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

### 2. Sign with Developer ID

```bash
EXPORT="$BUILDDIR/export"
mkdir -p "$EXPORT"
cp -R "$BUILDDIR/MacInputStats.xcarchive/Products/Applications/MacInputStats.app" "$EXPORT/"

codesign --force --deep --sign "YOUR_CERT_HASH" \
  --options runtime \
  --timestamp \
  --entitlements MacInputStats/MacInputStats.entitlements \
  "$EXPORT/MacInputStats.app"
```

Replace `YOUR_CERT_HASH` with your Developer ID Application certificate SHA-1 hash. Find it with:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 3. Notarize

```bash
ditto -c -k --keepParent "$EXPORT/MacInputStats.app" "$BUILDDIR/MacInputStats.zip"

xcrun notarytool submit "$BUILDDIR/MacInputStats.zip" \
  --apple-id "YOUR_APPLE_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD" \
  --team-id "YOUR_TEAM_ID" \
  --wait

xcrun stapler staple "$EXPORT/MacInputStats.app"
```

### 4. Create DMG

```bash
DMG="$HOME/Desktop/MacInputStats-vX.Y.Z.dmg"

create-dmg \
  --volname "Mac Input Stats" \
  --volicon "$EXPORT/MacInputStats.app/Contents/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "MacInputStats.app" 150 190 \
  --app-drop-link 450 190 \
  --no-internet-enable \
  "$DMG" \
  "$EXPORT/MacInputStats.app"
```

### 5. Sign and notarize the DMG

```bash
codesign --force --sign "YOUR_CERT_HASH" --timestamp "$DMG"

xcrun notarytool submit "$DMG" \
  --apple-id "YOUR_APPLE_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD" \
  --team-id "YOUR_TEAM_ID" \
  --wait

xcrun stapler staple "$DMG"
```

### 6. Sign with Sparkle EdDSA

```bash
/path/to/Sparkle/bin/sign_update "$DMG"
```

This outputs `sparkle:edSignature="..."` and `length="..."` — you'll need these for the appcast.

### 7. Update appcast.xml

Add a new `<item>` block to `appcast.xml` with the version numbers, download URL, and signature:

```xml
<item>
    <title>Version X.Y.Z</title>
    <pubDate>DATE_HERE</pubDate>
    <sparkle:version>BUILD_NUMBER</sparkle:version>
    <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    <enclosure
        url="https://github.com/SuveenE/mac-input-stats/releases/download/vX.Y.Z/MacInputStats-vX.Y.Z.dmg"
        sparkle:edSignature="SIGNATURE_HERE"
        length="LENGTH_HERE"
        type="application/octet-stream" />
</item>
```

### 8. Publish

```bash
# Push updated appcast.xml to main
git add appcast.xml && git commit -m "Update appcast for vX.Y.Z" && git push

# Create GitHub release
gh release create vX.Y.Z "$DMG" --title "vX.Y.Z" --notes "Release notes here"
```

## Verifying a release

```bash
# Verify Apple signing
spctl -a -t open --context context:primary-signature -v "$DMG"
# Expected: "accepted, source=Notarized Developer ID"

# Verify app signing
codesign -dvv "$EXPORT/MacInputStats.app" 2>&1 | grep Authority
# Expected: "Authority=Developer ID Application: ..."
```

## Sparkle key management

The EdDSA private key lives in your macOS Keychain. To back it up or use in CI:

```bash
# Export private key
/path/to/Sparkle/bin/generate_keys -x

# View existing public key
/path/to/Sparkle/bin/generate_keys
```

The public key is baked into the app via `SUPublicEDKey` in `Info.plist`. If you lose the private key, you cannot sign future updates — existing installs will reject them.
