# Microsoft sign-in setup

The onboarding "Sign in with Microsoft" step performs a **real MSAL interactive
sign-in** (`MicrosoftSignIn.makeSignInAction` → `DCGAuthenticator`). It is wired
and functional, but it needs two things the project deliberately does **not**
ship: your **own Entra app registration** and a **properly signed** build.

## Why there's no built-in client id
We never embed a Microsoft first-party client id — that would impersonate the
official app, not interoperate with it. So you register your own Entra
application and supply its client id. See `Sources/DCGAuth/DCGAuth.swift` for the
first-party constraint on the DCG resource scope specifically.

## Is there an alternative to registering an Entra app?
**No.** OAuth / MSAL fundamentally require a `client_id` from an app
registration — there is no registration-free sign-in, and reusing someone
else's (or a first-party) client id is impersonation, which this project will
not do. Registration is free and a **personal Microsoft account** can do it
(no paid Azure subscription needed for a public client).

Because the DCG resource is first-party-gated anyway (a third-party token
won't be accepted there yet), the onboarding sign-in step is **optional**: a
**"Skip for now"** link advances past it so you can explore the app without an
Entra id. Sign-in becomes meaningful once the pairing/first-party path is
solved; until then, skipping loses nothing functional.

## 1. Register an Entra application
1. Azure Portal → *Microsoft Entra ID* → *App registrations* → *New
   registration*.
2. Supported account types: *Personal Microsoft accounts* (MSA) — matches the
   `…/consumers` authority used by default.
3. Add a **Redirect URI** of platform *macOS* (or a custom "Mobile and desktop"
   URI): `msauth.com.maclink.phonelink://auth`
   (scheme = `msauth.` + the bundle id `com.maclink.phonelink`).
4. Copy the **Application (client) ID** (a GUID).

The bundle already registers that scheme in `Info.plist`
(`CFBundleURLTypes`, see `scripts/package-app.sh`), so the auth callback returns
to the app.

## 2. Provide the client id (any one of)
Resolved in this priority order by `MicrosoftSignIn.resolvedClientId()`:
1. **Env var** — `PHONELINK_MSAL_CLIENT_ID=<guid>` (handy for `swift run`).
2. **Onboarding field** — paste the GUID into the text field on the sign-in
   step; it persists to the `PhoneLinkMSALClientId` UserDefaults key.
3. **Info.plist** — add a `PhoneLinkMSALClientId` string entry.

## 3. Scopes
Sign-in requests the universally-consentable diagnostic scopes
(`openid profile offline_access`) so the flow completes and returns your account
name — this proves the mechanics. The **DCG resource scope**
(`https://dcg.microsoft.com/DCG.ReadWrite`) is first-party-gated and requested
separately by the transport layer; expect it to be refused for a third-party app
(`AADSTS65001` / `invalid_scope`). That refusal is itself a finding, not a bug in
this client.

## Token cache needs a signed build — signing path (now wired)
MSAL persists its token cache in the macOS keychain, which requires the app to
carry a **keychain-access-groups entitlement** and be signed with a real
identity. A pure **ad-hoc** build (`codesign --sign -`) can hit
`errSecMissingEntitlement (-34018)` when MSAL persists, breaking silent refresh.

The signing path is now in place:
- **`scripts/PhoneLink.entitlements`** — `keychain-access-groups` with
  `$(AppIdentifierPrefix)com.microsoft.adalcache` (MSAL's group, which
  `MicrosoftSignIn` targets via `keychainGroup`) + the app's own group, plus the
  network client/server entitlements for hardened runtime.
- **`scripts/package-app.sh`** — honors `CODESIGN_IDENTITY` and
  `CODESIGN_ENTITLEMENTS`. With a real identity it signs with `--options runtime`
  (hardened) and applies the entitlements; with the default `-` it stays ad-hoc
  and entitlement-free (an ad-hoc build has no `AppIdentifierPrefix` to resolve,
  so entitlements are intentionally skipped there).
- **`.github/workflows/build-app.yml`** — imports a Developer ID cert into a
  throwaway keychain, packages with the identity + entitlements, then notarizes
  and staples. Gated on secrets; falls back to ad-hoc when they're absent.

Required repo secrets for the real path:
`MACOS_CERTIFICATE` (base64 Developer ID Application .p12), `MACOS_CERTIFICATE_PWD`,
`MACOS_SIGN_IDENTITY` (e.g. `Developer ID Application: Name (TEAMID)`), and for
notarization `AC_API_KEY_ID`, `AC_API_ISSUER_ID`, `AC_API_KEY_P8` (base64 .p8).

Until you have a Developer ID, sign-in is best validated by running a
locally-built binary (`PHONELINK_MSAL_CLIENT_ID=<guid> swift run PhoneLinkApp`),
which uses your login keychain directly.
