# Account Manager — Build & Release Notes

Project layout:

- `Account Manager/` — main app target (App/, Extensions/, Models/, Privilege/, Resources/, Services/, Shared/, Views/)
- `com.ihms.accountmanager.helper/` — privileged XPC helper (LaunchDaemon, runs as root)
- `Account Manager.xcodeproj` — uses Xcode 16 file-system-synchronized groups, so new `.swift` files added to either folder are picked up automatically (no manual "Add to target" step)

## Signing

- Team: `99NFK23KMA`
- Bundle IDs: `com.ihms.accountmanager` (app), `com.ihms.accountmanager.helper` (helper)
- Both targets must share the same Team so `SMAppService` will register the helper
- Sandbox is off (build setting, not entitlements) — required for the root helper and for the app's local dscl/SSH operations

## Privileged helper

The helper is fully implemented (`HelperDelegate.swift`, `HelperProtocol.swift`, `.plist`/`.entitlements`). It:

- Registers via `SMAppService.daemon` (`HelperClient.installIfNeeded()`)
- Detects and swaps in updated builds automatically (`helperBundledVersion` in `HelperProtocol.swift` — bump this whenever helper behavior changes)
- Runs `sysadminctl`/`dscl`/`rm` as root for deletions and password resets, with SecureToken admin-credential support for FileVault-protected accounts

## Building a Release

```
xcodebuild -scheme "Account Manager" -configuration Release \
  -derivedDataPath /tmp/am-release -allowProvisioningUpdates build
```

Building on the Synology CloudStorage-synced project folder can leave `com.apple.FinderInfo` extended attributes that break code-sign verification — strip them before installing/distributing:

```
xattr -cr "/tmp/am-release/Build/Products/Release/Account Manager.app"
```

## Publishing an update (Sparkle)

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the Xcode project (both app and helper targets).
2. Archive/build Release, zip the `.app`:
   ```
   ditto -c -k --keepParent "Account Manager.app" "AccountManager-<version>.zip"
   ```
3. Sign it with Sparkle's `sign_update` (private key lives in the macOS Keychain):
   ```
   ~/Library/Developer/Xcode/DerivedData/Account_Manager-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update AccountManager-<version>.zip
   ```
4. Upload the zip to a GitHub Release.
5. Add an `<item>` to `appcast.xml` with the real `sparkle:edSignature` and `length` from step 3, and commit it.

## Settings

| Setting | Location | Default |
|---|---|---|
| Appearance | Settings → Appearance | Auto |
| Default deletion mode | Settings → Deletion Defaults | Account + Files |
| Default file removal | Settings → Deletion Defaults | Hard Delete |
| Minimum protected UID | Settings → Policy Overrides | 200 |
| Staff / Office / Admin tags | Settings → Policy Overrides | _staff / _office / _administrator, IT |
| Require PIN on Launch / Lock Remote Hosts / Lock Settings | Settings → Security & Lock | Off |
| Use legacy deletion tool | Settings → Advanced | Off |
