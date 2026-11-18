#!/bin/bash
set -euo pipefail

# This script changes signing configuration only on a disposable GitHub runner.
[[ "${GITHUB_ACTIONS:-}" == "true" ]] || { echo "Run this script through GitHub Actions." >&2; exit 1; }

for name in APPLE_TEAM_ID APP_BUNDLE_ID DISTRIBUTION_CERTIFICATE_BASE64 \
    DISTRIBUTION_CERTIFICATE_PASSWORD PROVISIONING_PROFILE_BASE64 \
    ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_BASE64; do
    [[ -n "${!name:-}" ]] || { echo "Missing configuration: $name" >&2; exit 1; }
done

SIGNING_DIRECTORY=$(mktemp -d "$RUNNER_TEMP/album-signing.XXXXXX")
KEYCHAIN_PATH="$SIGNING_DIRECTORY/signing.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
PROFILE_DESTINATION=""

cleanup() {
    security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
    if [[ -n "$PROFILE_DESTINATION" ]]; then rm -f "$PROFILE_DESTINATION"; fi
    rm -rf "$SIGNING_DIRECTORY"
}
trap cleanup EXIT

printf '%s' "$DISTRIBUTION_CERTIFICATE_BASE64" | base64 --decode > "$SIGNING_DIRECTORY/certificate.p12"
printf '%s' "$PROVISIONING_PROFILE_BASE64" | base64 --decode > "$SIGNING_DIRECTORY/profile.mobileprovision"
printf '%s' "$ASC_PRIVATE_KEY_BASE64" | base64 --decode > "$SIGNING_DIRECTORY/AuthKey_$ASC_KEY_ID.p8"
chmod 600 "$SIGNING_DIRECTORY"/*

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$SIGNING_DIRECTORY/certificate.p12" -P "$DISTRIBUTION_CERTIFICATE_PASSWORD" \
    -k "$KEYCHAIN_PATH" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" > /dev/null
security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db

security cms -D -i "$SIGNING_DIRECTORY/profile.mobileprovision" > "$SIGNING_DIRECTORY/profile.plist"
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$SIGNING_DIRECTORY/profile.plist")
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c 'Print Name' "$SIGNING_DIRECTORY/profile.plist")
PROFILE_DIRECTORY="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$PROFILE_DIRECTORY"
PROFILE_DESTINATION="$PROFILE_DIRECTORY/$PROFILE_UUID.mobileprovision"
cp "$SIGNING_DIRECTORY/profile.mobileprovision" "$PROFILE_DESTINATION"

export PROFILE_UUID
export EXPORT_OPTIONS_PATH="$SIGNING_DIRECTORY/ExportOptions.plist"
python3 - <<'PY'
import os
import plistlib

options = {
    "method": "app-store-connect",
    "destination": "upload",
    "teamID": os.environ["APPLE_TEAM_ID"],
    "signingStyle": "manual",
    "signingCertificate": "Apple Distribution",
    "provisioningProfiles": {os.environ["APP_BUNDLE_ID"]: os.environ["PROFILE_UUID"]},
    "manageAppVersionAndBuildNumber": False,
    "uploadSymbols": True,
}
with open(os.environ["EXPORT_OPTIONS_PATH"], "wb") as output:
    plistlib.dump(options, output)
PY

ARCHIVE_ARGUMENTS=(
    -project AlbumSearch.xcodeproj
    -scheme AlbumSearch
    -configuration Release
    -destination 'generic/platform=iOS'
    -archivePath build/AlbumSearch.xcarchive
    CODE_SIGN_STYLE=Manual
    'CODE_SIGN_IDENTITY=Apple Distribution'
    "DEVELOPMENT_TEAM=$APPLE_TEAM_ID"
    "PRODUCT_BUNDLE_IDENTIFIER=$APP_BUNDLE_ID"
    "PROVISIONING_PROFILE_SPECIFIER=$PROFILE_NAME"
    "CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER.$GITHUB_RUN_ATTEMPT"
)
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    ARCHIVE_ARGUMENTS+=("MARKETING_VERSION=${GITHUB_REF_NAME#v}")
fi
xcodebuild archive "${ARCHIVE_ARGUMENTS[@]}"

# destination=upload exports and submits the signed archive to App Store Connect.
xcodebuild -exportArchive \
    -archivePath build/AlbumSearch.xcarchive \
    -exportPath build/Export \
    -exportOptionsPlist "$EXPORT_OPTIONS_PATH" \
    -authenticationKeyPath "$SIGNING_DIRECTORY/AuthKey_$ASC_KEY_ID.p8" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
