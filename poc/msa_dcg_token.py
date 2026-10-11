#!/usr/bin/env python3
"""
MSA / Entra OAuth proof-of-concept for the Phone Link "Device Connectivity Gateway"
(DCG) scope.

What this does
--------------
Runs the standard Microsoft OAuth 2.0 *device-code* flow against the public MSA/Entra
token endpoints that the Link-to-Windows app also uses, requests a token for the DCG
resource, and prints:
  * the raw token response, and
  * the decoded (unverified) id_token / access_token claims — this is the closest
    analog to the "device registration payload" you can observe from the client side,
    since it carries the account/object/tenant identifiers DCG keys off of.

Endpoints observed in the APK (login hosts and the DCG resource audience):
  * authority : https://login.microsoftonline.com/consumers   (MSA consumers)
  * resource  : https://dcg.microsoft.com/   (scope: DCG.ReadWrite)
  * rings seen: dcg.microsoft.com, dcg-df.microsoft.com, dcg-beta.microsoft.com

IMPORTANT — read before running
--------------------------------
1. You must supply YOUR OWN registered Entra/MSA application client_id via the
   MSA_CLIENT_ID env var. This script deliberately does NOT ship Microsoft's
   first-party client_id: using the official app's identity to talk to Microsoft's
   servers would be impersonating that app, not interoperating with it.
2. `https://dcg.microsoft.com/DCG.ReadWrite` is a PROTECTED FIRST-PARTY resource.
   A normal user-registered app will almost certainly be refused consent for it
   (AADSTS65001 / AADSTS650057 / "invalid_scope"). That refusal is itself a useful
   finding: it tells you the real client must be a first-party identity plus a
   device-registration/attestation step you cannot reproduce off-platform. Run with
   SCOPE="openid profile offline_access" first to confirm the *mechanics* work, then
   try the DCG scope to see exactly how the server rejects a third party.
3. This only exercises Microsoft's public OAuth endpoints with your own credentials.
   It does not touch the paired PC or any other user's data.

Dependencies:  pip install msal
"""

import base64
import json
import os
import sys

try:
    import msal  # Microsoft Authentication Library (official)
except ImportError:
    sys.exit("Missing dependency. Run:  pip install msal")


# --- Configuration (all overridable by env vars) ---------------------------------
CLIENT_ID = os.environ.get("MSA_CLIENT_ID")  # REQUIRED: your own registered app
AUTHORITY = os.environ.get("MSA_AUTHORITY", "https://login.microsoftonline.com/consumers")

# Default to a harmless, universally-consentable scope so you can prove the flow works.
# Override to the DCG resource to observe how a third party is rejected:
#   SCOPE="https://dcg.microsoft.com/DCG.ReadWrite"
SCOPE = os.environ.get("MSA_SCOPE", "openid profile offline_access").split()


def _decode_jwt_noverify(token: str) -> dict | None:
    """Base64url-decode a JWT's payload WITHOUT signature verification (inspection only)."""
    try:
        payload_b64 = token.split(".")[1]
        payload_b64 += "=" * (-len(payload_b64) % 4)  # pad
        return json.loads(base64.urlsafe_b64decode(payload_b64))
    except Exception:
        return None


def main() -> int:
    if not CLIENT_ID:
        sys.exit(
            "Set MSA_CLIENT_ID to a client_id from an app you registered at\n"
            "  https://entra.microsoft.com  (App registrations -> New registration,\n"
            "  'Personal Microsoft accounts', enable public-client / device-code flow)."
        )

    app = msal.PublicClientApplication(CLIENT_ID, authority=AUTHORITY)

    print(f"Authority : {AUTHORITY}")
    print(f"Client ID : {CLIENT_ID}")
    print(f"Scopes    : {SCOPE}\n")

    # Device-code flow: the practical choice for a headless CLI PoC.
    flow = app.initiate_device_flow(scopes=SCOPE)
    if "user_code" not in flow:
        print("Failed to start device flow:")
        print(json.dumps(flow, indent=2))
        return 1

    print("=== Sign in to continue ===")
    print(flow["message"])  # e.g. "go to https://microsoft.com/devicelogin and enter CODE"
    print("\nWaiting for you to complete sign-in in the browser...\n")

    result = app.acquire_token_by_device_flow(flow)  # blocks until done/expired

    if "access_token" not in result:
        print("Token acquisition FAILED (this is expected for the DCG scope as a third party):")
        print(json.dumps(
            {k: result.get(k) for k in ("error", "error_description", "error_codes")},
            indent=2,
        ))
        return 2

    print("=== Token response (secrets truncated) ===")
    redacted = dict(result)
    for k in ("access_token", "refresh_token", "id_token"):
        if redacted.get(k):
            redacted[k] = redacted[k][:24] + f"...<{len(redacted[k])} chars>"
    print(json.dumps(redacted, indent=2, default=str))

    # The "device registration payload" analog: the identity claims the token carries.
    print("\n=== Decoded id_token claims (UNVERIFIED — inspection only) ===")
    claims = result.get("id_token_claims") or _decode_jwt_noverify(result.get("id_token", ""))
    interesting = ("oid", "sub", "tid", "preferred_username", "email", "name",
                   "aud", "iss", "iat", "exp", "xms_pdl", "xms_tdbr")
    if claims:
        print(json.dumps({k: claims[k] for k in interesting if k in claims}, indent=2))
    else:
        print("(no id_token returned)")

    print("\n=== Decoded access_token claims (UNVERIFIED) ===")
    at_claims = _decode_jwt_noverify(result.get("access_token", ""))
    if at_claims:
        # 'aud' here confirms whether the token is actually scoped to DCG.
        for k in ("aud", "appid", "scp", "roles", "oid", "tid", "iss"):
            if k in at_claims:
                print(f"  {k}: {at_claims[k]}")
    else:
        print("  (access_token is not a JWT / opaque)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
