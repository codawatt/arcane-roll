# Bug Report: Godot Android Release APK Signing Fails on Debian 13

**Project:** Arcane Roll
**Repository:** `codawatt/arcane-roll`
**Platform:** Debian 13 (Trixie), KDE Plasma 6, Wayland
**Status:** Partially resolved — manual release signing works, automatic Godot signing fails
**Priority:** High — blocks normal Android release exports

## 1. Problem Summary

Godot successfully builds and signs Android debug APKs, but fails to sign release APKs when **Export With Debug** is disabled.

The release APK is generated, but it does not have a valid signature and cannot be installed on Android.

**Important discovery:** The exact same release APK can be successfully signed manually with Android SDK's `apksigner`, using the existing release keystore.

This strongly suggests the problem lies in Godot's release signing configuration, credential handling, or signing command invocation — not in the release keystore itself.

## 2. System Environment

| Component                | Value                                |
| ------------------------ | ------------------------------------ |
| Operating system         | Debian GNU/Linux 13 (Trixie), x86_64 |
| Desktop                  | KDE Plasma 6.3.6                     |
| Window manager           | KWin / Wayland                       |
| Godot launcher           | Godot_v4.7.2-stable_linux.x86_64     |
| Android SDK              | `/home/dm/Android/Sdk`               |
| Android Build Tools      | 35.0.1                               |
| ADB                      | Working                              |
| Connected Android device | Detected successfully                |
| Android package ID       | `io.github.codawatt.arcaneroll`      |

The exact Godot Engine version has not yet been captured.

## 3. Godot Android Export Configuration

Current settings observed:

```text
Project → Export → Android

Keystore:
  Debug:             empty
  Debug User:        empty
  Debug Password:    empty

  Release:           /home/dm/keys/arcane-roll-release.keystore
  Release User:      rosca.dragos  (changed to arcaneroll)
  Release Password:  configured

Package:
  Unique Name:       io.github.codawatt.arcaneroll
  Signed:            enabled

Version:
  Code:              1
```

**Potential misconfiguration identified:**

The initial Godot screenshot showed the release user as `rosca.dragos`, while the inspected keystore contained a key with alias `arcaneroll`.

It has been corrected now to arcaneroll.

## 4. Error When Exporting Release APK

When **Export With Debug** is disabled, Godot reports:

```text
Set keystore/release_password

WARNING: ./editor/export/editor_export_platform.h:267
Code Signing: 'apksigner' returned with error #2

WARNING: Code Signing: output:
```

The resulting APK exists on disk but cannot be installed.

Attempting installation:

```bash
adb install builds/android/arcane-roll-1.0.0.apk
```

Produces:

```text
INSTALL_PARSE_FAILED_NO_CERTIFICATES
Failed to collect certificates
Attempt to get length of null array
```

The root cause is release signing failure.

## 5. Debug APK Verification — SUCCESS

Command:

```bash
/home/dm/Android/Sdk/build-tools/35.0.1/apksigner \
  verify --verbose --print-certs arcane-roll.apk
```

Output:

```text
Verifies
Verified using v1 scheme: false
Verified using v2 scheme: true
Verified using v3 scheme: true
Verified using v3.1 scheme: false
Verified using v4 scheme: false
Verified for SourceStamp: false
Number of signers: 1

Signer #1 certificate DN:
CN=Godot, OU=Godot Engine,
O=Stichting Godot, C=NL
```

Conclusion: Godot successfully signs debug APKs using its debug signing configuration.

## 6. Release APK Verification — FAILURE

Command:

```bash
/home/dm/Android/Sdk/build-tools/35.0.1/apksigner \
  verify --verbose --print-certs arcane-roll-1.0.0.apk
```

Output:

```text
DOES NOT VERIFY
ERROR: Missing META-INF/MANIFEST.MF
```

This error alone does not identify the full signing failure. APK Signature Scheme v2/v3 does not require v1 JAR signing.

However, the APK fails overall verification and cannot be installed.

Conclusion: Godot is producing an APK without a valid release signature.

## 7. Existing Release Keystore — VERIFIED

Release keystore:

```text
/home/dm/keys/arcane-roll-release.keystore
```

Verified using:

```bash
keytool -list \
  -keystore /home/dm/keys/arcane-roll-release.keystore \
  -alias arcaneroll
```

Result:

```text
arcaneroll, Oct 14, 2026, PrivateKeyEntry
Certificate fingerprint (SHA-256): [REDACTED]
```

The keystore is readable, the supplied keystore password works, and the `arcaneroll` key alias exists.

## 8. Manual Release Signing — SUCCESS

Manual signing was performed using:

```bash
/home/dm/Android/Sdk/build-tools/35.0.1/apksigner sign \
  --ks /home/dm/keys/arcane-roll-release.keystore \
  --ks-key-alias arcaneroll \
  --out arcane-roll-1.0.0-signed.apk \
  arcane-roll-1.0.0.apk
```

**Result: Successful.**

The existing release APK was successfully signed from the command line with the existing keystore.

This confirms that:

- The keystore is usable for APK signing.
- The `arcaneroll` key alias works.
- The Android SDK signing utility is functional.
- The generated release APK can be signed without rebuilding the project.
- Regenerating the keystore is unnecessary.

The user reported successful manual signing. The complete post-signing verification output has not been supplied.

## 9. Required Maintainer Investigation

### A. Verify Godot release keystore settings

Check the current Android export preset.

Confirm:

```text
keystore/release = /home/dm/keys/arcane-roll-release.keystore
keystore/release_user = arcaneroll
keystore/release_password = [VALID PASSWORD]
package/signed = true
```

Do not print or commit credentials.

The original `Release User` value did not match the verified key alias.

### B. Investigate Godot credential overrides

Check for environment variables that might override the configured release credentials.

In particular, inspect whether these are present:

```text
GODOT_ANDROID_KEYSTORE_RELEASE_PATH
GODOT_ANDROID_KEYSTORE_RELEASE_USER
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
```

Check against the environment actually inherited by the running Godot process, not only the interactive terminal.

Do not output password values.

### C. Compare Godot signing with manual signing

Determine why:

```text
Manual apksigner sign → SUCCESS
Godot release signing → FAILURE
```

Inspect:

- Actual keystore path received by Godot.
- Actual alias received by Godot.
- Whether a release password is provided.
- Whether keystore and key passwords differ.
- Which `apksigner` executable Godot invokes.
- Whether Godot's signing arguments match the working manual invocation.
- Whether Godot uses a different SDK or Java environment.
- Whether the release export preset is saved and loaded correctly.

### D. Capture diagnostic logs

Launch Godot from the terminal:

```bash
cd ~/code/repo/arcane-roll

/home/dm/.local/bin/godot-mono \
  --editor --path . --verbose
```

Export again with debugging disabled.

Capture the complete release signing error, excluding passwords and other credentials.

### E. Inspect project export configuration

Check:

```text
export_presets.cfg
```

Verify the Android export preset, release signing options, and any environment overrides.

Avoid committing passwords or unnecessarily modifying release signing identities.

If credentials are stored in an export configuration file, treat it as sensitive and redact before sharing logs or committing changes.

## 10. Reproduction Steps

1. Open Arcane Roll in Godot.
2. Open Project → Export → Android.
3. Enable **Signed**.
4. Configure the existing release keystore.
5. Export with **Export With Debug enabled**.
6. Observe a valid, signed debug APK.
7. Disable **Export With Debug**.
8. Export a release APK.
9. Observe `apksigner returned with error #2`.
10. Verify the exported APK and observe failure.
11. Sign the same APK manually with the existing release keystore.
12. Observe that manual signing succeeds.

## 11. Expected Behavior

Godot should automatically sign release APKs using:

```text
Keystore: /home/dm/keys/arcane-roll-release.keystore
Alias:    arcaneroll
```

The APK should pass:

```bash
apksigner verify --verbose --print-certs \
  builds/android/arcane-roll-1.0.0.apk
```

And install successfully:

```bash
adb install builds/android/arcane-roll-1.0.0.apk
```

## 12. Actual Behavior

Debug signing succeeds.

Release export generates an APK but fails automatic signing.

Manual signing of the release APK succeeds using the existing keystore.

## 13. Maintainer Instructions

**Primary objective:** Repair automatic Godot Android release signing without changing the existing application ID or release signing key.

Priorities:

1. Verify and correct the release key alias.
2. Check release password configuration and environment overrides.
3. Inspect the signing invocation and actual error output.
4. Compare Godot's signing environment with the working manual command.
5. Fix the underlying configuration or invocation issue.
6. Rebuild and verify a release APK directly from Godot.

Do not regenerate the release keystore, change the package identifier, or modify unrelated Neovim/LSP configuration.

**Current workaround:** Export the unsigned release APK from Godot and sign it manually using Android SDK `apksigner`.

**Resolution criteria:** Godot automatically produces a valid, signed, installable release APK with **Export With Debug disabled**, without any manual signing step.
