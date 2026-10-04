# Android APK signing (stable signature for in-place updates)

Android only lets you install an APK *over* an existing install when both APKs
are signed with the **same key**. CI's default debug signing uses a throwaway
key that differs per run, so without a fixed key each build is a different
"app" and you'd have to uninstall before installing a new build.

We fix this with **one key, kept out of the repo** (committing a signing key
leaks it). The key lives in a GitHub Actions secret; CI decodes it and signs
every APK with it. Do this once:

## 1. Generate the key (on your Mac, once)

```sh
keytool -genkeypair -v \
  -keystore companion.jks \
  -storepass <STOREPASS> -keypass <KEYPASS> \
  -alias companion \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=mac-phone-link companion, O=mac-phone-link, C=US"
```

Keep `companion.jks` somewhere safe and private (a password manager / backup).
If you lose it you can't ship in-place updates again — you'd have to uninstall
and reinstall with a new key.

## 2. Add the secrets to the repo

Base64 the keystore:

```sh
base64 -i companion.jks | pbcopy   # now in your clipboard
```

In GitHub → the repo → **Settings → Secrets and variables → Actions → New
repository secret**, add:

| Secret name                 | Value                                  |
|-----------------------------|----------------------------------------|
| `ANDROID_KEYSTORE_B64`      | the base64 string from above           |
| `ANDROID_KEYSTORE_PASSWORD` | your `<STOREPASS>`                      |
| `ANDROID_KEY_ALIAS`         | `companion`                            |
| `ANDROID_KEY_PASSWORD`      | your `<KEYPASS>`                        |

## 3. That's it

The next CI build signs the APK with your key. Every build after that shares
the same signature, so you can install each new `companion-apk` straight over
the previous one. (Bump `versionCode` in `android/app/build.gradle` for each
real release; Android blocks installing an *older* versionCode over a newer.)

Builds made **without** the secret (e.g. a fork, or before you add it) still
succeed — they just use default debug signing and won't share your signature.
