# Release Helix

You are running the Helix release pipeline. Follow each phase in order. Stop immediately if any step fails and report the error. Ask for confirmation before proceeding to Phase 4 (Publish).

If $ARGUMENTS is provided, use it as the new version number. Otherwise, auto-increment the PATCH component of the current version (YYYY.M.PATCH format, e.g. 2026.2.0 -> 2026.2.1). If the current month or year has changed, reset accordingly (e.g. 2026.2.3 in March -> 2026.3.0).

## Context

- **Project root**: the Helix directory containing Package.swift and project.yml
- **Bundle ID**: com.hexul.Helix
- **Signing identity**: "Developer ID Application: Alexandru Geana (7G4UQW35EL)"
- **Team ID**: 7G4UQW35EL
- **Notarization**: `xcrun notarytool` with API key at `~/.appstoreconnect/config.json`
- **Sparkle sign_update**: `DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update`
- **Appcast**: `appcast.xml` in repo root
- **Homebrew tap**: `hex/homebrew-tap` repo, cask at `Casks/helix.rb`
- **Website repo**: `hex/hexul.com`, Helix page at `helix/` directory

---

## Phase 1: Pre-flight Checks

### 1.1 Clean Git State
- Verify on `main` branch
- Verify no uncommitted changes (`git status --porcelain` should be empty)
- Verify up to date with remote (`git fetch origin && git diff HEAD origin/main --quiet`)
- If any check fails, STOP and report

### 1.2 Run Tests
Clean build cache first (SPM cache can be stale from mutagen sync across endpoints):
```
swift package clean
swift test --package-path .
```
- All tests must pass. If any fail, STOP and report.

### 1.3 Secrets Scan
Search the entire repo for potential secrets. Flag and STOP if any are found:
- Grep for patterns: `PRIVATE KEY`, `api_key`, `secret`, `password`, `token`, `credential` (case insensitive)
- Check for `.env` files, `*.p8` files, `*.pem` files
- Ignore `DerivedData/`, `.build/`, and test fixtures
- If anything suspicious is found, list the files and STOP

### 1.4 Documentation Check
- Verify `README.md` exists and is non-empty
- Verify `LICENSE` exists
- Check that the version in README badges will be updated (note the current version)
- Check that any new features added since last tag are mentioned in README (compare `git log` since last tag against README features list). If README needs updating, STOP and list what's missing.

---

## Phase 2: Version Bump

### 2.1 Determine New Version
- Read current version from `project.yml` (`CFBundleShortVersionString`)
- Calculate new version using YYYY.M.PATCH format:
  - If $ARGUMENTS is provided, use that exact version
  - Otherwise: use current year and month. If year+month match current version, increment PATCH. If they differ, reset PATCH to 0.
- Display: `Current: X.Y.Z -> New: A.B.C` and proceed

### 2.2 Update Version in Files
Update the version string in ALL of these locations:
- `project.yml`: `CFBundleShortVersionString`
- `README.md`: version badge (`version-NEWVERSION-blue`)
- Increment `CFBundleVersion` (the integer build number) by 1

---

## Phase 3: Build, Sign & Package

### 3.1 Regenerate Xcode Project
```
xcodegen generate
```

### 3.2 Build Release Archive
```
xcodebuild archive \
  -project Helix.xcodeproj \
  -scheme Helix \
  -configuration Release \
  -archivePath build/Helix.xcarchive \
  CODE_SIGN_IDENTITY="Developer ID Application: Alexandru Geana (7G4UQW35EL)" \
  DEVELOPMENT_TEAM=7G4UQW35EL \
  CODE_SIGN_STYLE=Manual
```

### 3.3 Export App
```
xcodebuild -exportArchive \
  -archivePath build/Helix.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

Create `ExportOptions.plist` if it doesn't exist:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>7G4UQW35EL</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
```

### 3.4 Notarize
Zip the app first (notarytool requires a zip, not a bare .app):
```
ditto -c -k --keepParent build/export/Helix.app build/Helix-notarize.zip
```
Then submit using absolute paths:
```
xcrun notarytool submit /absolute/path/to/build/Helix-notarize.zip \
  --key ~/.appstoreconnect/AuthKey_B9ZAC83PUL.p8 \
  --key-id B9ZAC83PUL \
  --issuer 69a6de8e-e98e-47e3-e053-5b8c7c11a4d1 \
  --wait
```
- Must complete with status "Accepted"
- If rejected, fetch the log with `xcrun notarytool log <submission-id> ...` and STOP

### 3.5 Staple
```
xcrun stapler staple build/export/Helix.app
```

### 3.6 Create DMG
```
hdiutil create -volname "Helix" \
  -srcfolder build/export/Helix.app \
  -ov -format UDZO \
  "build/Helix-VERSION.dmg"
```
Replace VERSION with the new version number.

### 3.7 Sparkle Sign
```
DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update "build/Helix-VERSION.dmg"
```
- Capture the output: it prints `sparkle:edSignature="..." length="..."`
- Save both the `edSignature` and `length` values for the appcast

### 3.8 Verify
```
spctl --assess --type execute --verbose build/export/Helix.app
codesign --verify --deep --strict build/export/Helix.app
```
- Both must pass

---

**STOP HERE and ask for confirmation before publishing.** Show:
- New version number
- DMG file size
- Sparkle signature (first 20 chars...)
- Summary of what will be published

---

## Phase 4: Publish

### 4.1 Update Appcast
Add a new `<item>` entry to `appcast.xml` inside the `<channel>` element:
```xml
<item>
    <title>Version VERSION</title>
    <pubDate>RFC822_DATE</pubDate>
    <sparkle:version>BUILD_NUMBER</sparkle:version>
    <sparkle:shortVersionString>VERSION</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    <enclosure
        url="https://github.com/hex/Helix/releases/download/vVERSION/Helix-VERSION.dmg"
        type="application/octet-stream"
        sparkle:edSignature="ED_SIGNATURE"
        length="FILE_LENGTH"
    />
</item>
```
- VERSION: the new version string
- BUILD_NUMBER: the new CFBundleVersion integer
- RFC822_DATE: current date in RFC 822 format (e.g. "Mon, 09 Feb 2026 12:00:00 +0000")
- ED_SIGNATURE and FILE_LENGTH: from the sign_update output in step 3.7

### 4.2 Commit & Tag
```
git add project.yml README.md appcast.xml ExportOptions.plist
git commit -m "Release vVERSION"
git tag vVERSION
```

### 4.3 Push
```
git push origin main --tags
```

### 4.4 GitHub Release
```
gh release create vVERSION build/Helix-VERSION.dmg \
  --title "Helix VERSION" \
  --generate-notes
```

### 4.5 Update Homebrew Tap
Calculate SHA256 of the DMG:
```
shasum -a 256 build/Helix-VERSION.dmg
```

Then update `Casks/helix.rb` in `hex/homebrew-tap`:
- Update `version` to the new version
- Update `sha256` to the DMG's SHA256

Use the GitHub API to update the file:
```
gh api repos/hex/homebrew-tap/contents/Casks/helix.rb \
  --method PUT \
  -f message="Update Helix to VERSION" \
  -f content="BASE64_CONTENT" \
  -f sha="CURRENT_FILE_SHA"
```

### 4.6 Update Website (if needed)
Check `hex/hexul.com` repo for a `helix/` directory. If it contains version numbers or download links, update them to the new version. If no changes are needed, skip this step.

---

## Phase 5: Cleanup

- Remove the `build/` directory
- Report the release summary:
  - Version released
  - GitHub release URL
  - DMG download URL
  - Homebrew install command: `brew install --cask hex/tap/helix`
  - Appcast updated
  - Tap updated
