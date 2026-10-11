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

## Known caveat — token cache needs a signed build
MSAL persists its token cache in the macOS keychain, which requires the app to
carry a **keychain-access-groups entitlement** and be signed with a real
identity. The current **ad-hoc** signed build (`codesign --sign -`) can hit
`errSecMissingEntitlement (-34018)` when MSAL tries to persist, which can break
silent token refresh (and, on some macOS versions, the interactive call too).

This is the same gap as notarization: once the CI **Developer ID** signing path
is wired (repo secrets `APPLE_DEVELOPER_ID` / `PROVISIONING_PROFILE`, see
`claude/handoff.md`), add an entitlements file with
`keychain-access-groups` (include MSAL's `com.microsoft.adalcache`) and pass
`--entitlements` to `codesign`. Until then, sign-in is best validated by running
a locally-built, locally-signed binary (`swift run PhoneLinkApp` with the env
var set) rather than a downloaded, quarantined bundle.
